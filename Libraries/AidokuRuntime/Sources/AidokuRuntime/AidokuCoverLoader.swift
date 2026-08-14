import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol AidokuCoverRuntime: Sendable {
    func mangaDetails(_ manga: AidokuManga, chapters: Bool) async throws -> AidokuManga
    func imageRequest(url value: String, context: [String: String]) async throws -> AidokuImageRequest
}

extension AidokuSourceRuntime: AidokuCoverRuntime {}

public protocol AidokuImageTransport: Sendable {
    func data(
        for request: URLRequest,
        maximumBytes: Int,
        usesSystemProxy: Bool
    ) async throws -> (Data, HTTPURLResponse)
}

public struct AidokuDefaultImageTransport: AidokuImageTransport {
    public init() {}

    public func data(
        for request: URLRequest,
        maximumBytes: Int,
        usesSystemProxy: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        try await AidokuHTTPClient.data(
            for: request,
            maximumBytes: maximumBytes,
            usesSystemProxy: usesSystemProxy
        )
    }
}

/// Resolves, validates, coalesces, and caches remote source cover images.
///
/// Browse metadata is frequently stale or contains a lazy-loading/CDN URL that no
/// longer works. A failed initial cover is therefore refreshed once through the
/// source's detail endpoint. Only data that decodes as a bounded raster image is
/// cached; HTML soft-404 responses never become permanent gray cover entries.
public actor AidokuCoverLoader {
    private struct CacheKey: Hashable, Sendable {
        let sourceID: String
        let sourceVersion: Int
        let mangaKey: String
        let advertisedCoverURL: String
        let usesSystemProxy: Bool

        var identity: String {
            [sourceID, String(sourceVersion), mangaKey, advertisedCoverURL, String(usesSystemProxy)]
                .joined(separator: "\u{1f}")
        }
    }

    private struct InFlightTask {
        let id: UUID
        let task: Task<Data, Error>
    }

    private static let maximumCoverCacheBytes: Int64 = 256 * 1_024 * 1_024
    private static let maximumCoverCacheFiles = AidokuLimits.maximumCacheEntries
    private static let negativeCacheLifetime: TimeInterval = 30

    private let cacheRoot: URL
    private let fileManager: FileManager
    private let transport: any AidokuImageTransport
    private let memoryCache = NSCache<NSString, NSData>()
    private let globalDownloads = AidokuAsyncPermitPool(limit: 8)
    private var sourceDownloads: [String: AidokuAsyncPermitPool] = [:]
    private var inFlight: [CacheKey: InFlightTask] = [:]
    private var failedAt: [CacheKey: Date] = [:]
    private var sourceGenerations: [String: UUID] = [:]

    public init(
        cacheDirectory: URL,
        fileManager: FileManager = .default,
        transport: any AidokuImageTransport = AidokuDefaultImageTransport()
    ) {
        cacheRoot = cacheDirectory
        self.fileManager = fileManager
        self.transport = transport
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
    }

    public func data(
        sourceID: String,
        sourceVersion: Int,
        manga: AidokuManga,
        runtime: any AidokuCoverRuntime,
        maximumParallelRequests: Int = 4,
        usesSystemProxy: Bool = true
    ) async throws -> Data {
        guard AidokuPackageValidator.isSafeSourceID(sourceID), sourceVersion >= 0 else {
            throw AidokuRuntimeError.invalidSourceID
        }
        let key = CacheKey(
            sourceID: sourceID,
            sourceVersion: sourceVersion,
            mangaKey: manga.key,
            advertisedCoverURL: manga.coverURL ?? "",
            usesSystemProxy: usesSystemProxy
        )
        let memoryKey = key.identity as NSString
        let sourceGeneration = sourceGenerations[sourceID]
        if let data = memoryCache.object(forKey: memoryKey) as Data? {
            return data
        }
        if let data = cachedData(for: key) {
            memoryCache.setObject(data as NSData, forKey: memoryKey, cost: Self.imageCost(data))
            return data
        }
        if let failureDate = failedAt[key],
           Date().timeIntervalSince(failureDate) < Self.negativeCacheLifetime {
            throw AidokuRuntimeError.sourceUnavailable
        }
        if let current = inFlight[key] {
            let data = try await current.task.value
            guard sourceGenerations[sourceID] == sourceGeneration else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            return data
        }

        let sourceLimiter = sourceDownloads[sourceID] ?? {
            let limiter = AidokuAsyncPermitPool(limit: min(max(1, maximumParallelRequests), 5))
            sourceDownloads[sourceID] = limiter
            return limiter
        }()
        let globalLimiter = globalDownloads
        let transport = transport
        let taskID = UUID()
        let task = Task<Data, Error> {
            try await Self.load(
                manga: manga,
                runtime: runtime,
                transport: transport,
                sourceLimiter: sourceLimiter,
                globalLimiter: globalLimiter,
                usesSystemProxy: usesSystemProxy
            )
        }
        inFlight[key] = InFlightTask(id: taskID, task: task)
        do {
            let data = try await task.value
            guard sourceGenerations[sourceID] == sourceGeneration,
                  inFlight[key]?.id == taskID else { throw CancellationError() }
            inFlight[key] = nil
            failedAt[key] = nil
            memoryCache.setObject(data as NSData, forKey: memoryKey, cost: Self.imageCost(data))
            store(data, for: key)
            try Task.checkCancellation()
            return data
        } catch {
            if inFlight[key]?.id == taskID {
                inFlight[key] = nil
                if !Self.isCancellation(error) { failedAt[key] = Date() }
            }
            throw error
        }
    }

    public func removeSource(_ sourceID: String) throws {
        try invalidateSource(sourceID)
    }

    public func invalidateSource(_ sourceID: String) throws {
        guard AidokuPackageValidator.isSafeSourceID(sourceID) else {
            throw AidokuRuntimeError.invalidSourceID
        }
        inFlight = inFlight.filter { key, current in
            guard key.sourceID == sourceID else { return true }
            current.task.cancel()
            return false
        }
        failedAt = failedAt.filter { $0.key.sourceID != sourceID }
        sourceDownloads[sourceID] = nil
        sourceGenerations[sourceID] = UUID()
        memoryCache.removeAllObjects()
        let sourceCache = cacheRoot.appendingPathComponent(sourceID, isDirectory: true)
        if fileManager.fileExists(atPath: sourceCache.path) {
            try fileManager.removeItem(at: sourceCache)
        }
    }

    private static func load(
        manga: AidokuManga,
        runtime: any AidokuCoverRuntime,
        transport: any AidokuImageTransport,
        sourceLimiter: AidokuAsyncPermitPool,
        globalLimiter: AidokuAsyncPermitPool,
        usesSystemProxy: Bool
    ) async throws -> Data {
        var attempted = Set<String>()
        var lastError: Error = AidokuRuntimeError.sourceUnavailable

        if let initial = normalizedURLString(manga.coverURL), attempted.insert(initial).inserted {
            do {
                return try await loadOne(
                    initial,
                    runtime: runtime,
                    transport: transport,
                    sourceLimiter: sourceLimiter,
                    globalLimiter: globalLimiter,
                    usesSystemProxy: usesSystemProxy
                )
            } catch {
                if isCancellation(error) { throw error }
                lastError = error
            }
        }

        do {
            let refreshed = try await runtime.mangaDetails(manga, chapters: false)
            if let refreshedURL = normalizedURLString(refreshed.coverURL),
               attempted.insert(refreshedURL).inserted {
                return try await loadOne(
                    refreshedURL,
                    runtime: runtime,
                    transport: transport,
                    sourceLimiter: sourceLimiter,
                    globalLimiter: globalLimiter,
                    usesSystemProxy: usesSystemProxy
                )
            }
        } catch {
            if isCancellation(error) { throw error }
            lastError = error
        }
        throw lastError
    }

    private static func loadOne(
        _ value: String,
        runtime: any AidokuCoverRuntime,
        transport: any AidokuImageTransport,
        sourceLimiter: AidokuAsyncPermitPool,
        globalLimiter: AidokuAsyncPermitPool,
        usesSystemProxy: Bool
    ) async throws -> Data {
        if let inline = inlineImageData(value) {
            return try normalizedImageData(inline)
        }
        var lastError: Error = AidokuRuntimeError.sourceUnavailable
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let imageRequest = try await runtime.imageRequest(url: value, context: [:])
                var request = URLRequest(url: imageRequest.url)
                request.timeoutInterval = 30
                imageRequest.headers.forEach {
                    request.setValue($0.value, forHTTPHeaderField: $0.key)
                }
                let finalizedRequest = request
                let (data, response) = try await sourceLimiter.withPermit {
                    try await globalLimiter.withPermit {
                        try await transport.data(
                            for: finalizedRequest,
                            maximumBytes: AidokuLimits.maximumImageBytes,
                            usesSystemProxy: usesSystemProxy
                        )
                    }
                }
                guard (200..<300).contains(response.statusCode) else {
                    let error = AidokuCoverHTTPError(statusCode: response.statusCode)
                    if attempt == 0, error.isTransient {
                        lastError = error
                        try await Task.sleep(for: .milliseconds(250))
                        continue
                    }
                    throw error
                }
                return try normalizedImageData(data)
            } catch {
                if isCancellation(error) { throw error }
                lastError = error
                if attempt == 0, isTransient(error) {
                    try await Task.sleep(for: .milliseconds(250))
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func cachedData(for key: CacheKey) -> Data? {
        let url = cacheURL(for: key)
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= AidokuLimits.maximumImageBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              (try? Self.validateImage(data)) != nil else {
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    private func store(_ data: Data, for key: CacheKey) {
        let url = cacheURL(for: key)
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            pruneCache()
        } catch {
            // The memory cache remains usable when Application Support is unavailable.
        }
    }

    private func cacheURL(for key: CacheKey) -> URL {
        cacheRoot
            .appendingPathComponent(key.sourceID, isDirectory: true)
            .appendingPathComponent(String(key.sourceVersion), isDirectory: true)
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent(Self.sha256(key.identity), isDirectory: false)
    }

    private func pruneCache() {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: cacheRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        var files: [(url: URL, size: Int64, date: Date)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.deletingLastPathComponent().lastPathComponent == "covers",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files.append((url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast))
        }
        var bytes = files.reduce(Int64(0)) { $0 + $1.size }
        while files.count > Self.maximumCoverCacheFiles || bytes > Self.maximumCoverCacheBytes {
            files.sort { $0.date < $1.date }
            let oldest = files.removeFirst()
            if (try? fileManager.removeItem(at: oldest.url)) != nil { bytes -= oldest.size }
        }
    }

    private static func normalizedURLString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func inlineImageData(_ value: String) -> Data? {
        guard value.hasPrefix("data:image/"),
              let comma = value.firstIndex(of: ","),
              value[..<comma].lowercased().contains(";base64") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }

    private static func validateImage(_ data: Data) throws {
        let source = try boundedImageSource(data)
        guard CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) != nil else {
            throw AidokuRuntimeError.runtimeFailure("Cover response is not a supported image")
        }
    }

    private static func normalizedImageData(_ data: Data) throws -> Data {
        let source = try boundedImageSource(data)
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw AidokuRuntimeError.runtimeFailure("Cover response is not a supported image")
        }
        let hasAlpha: Bool
        switch thumbnail.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            hasAlpha = true
        default:
            hasAlpha = false
        }
        let type = hasAlpha ? UTType.png.identifier : UTType.jpeg.identifier
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            type as CFString,
            1,
            nil
        ) else {
            throw AidokuRuntimeError.runtimeFailure("Cover response could not be normalized")
        }
        let options: CFDictionary = hasAlpha
            ? [:] as CFDictionary
            : [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        CGImageDestinationAddImage(destination, thumbnail, options)
        guard CGImageDestinationFinalize(destination),
              output.length > 0,
              output.length <= AidokuLimits.maximumImageBytes else {
            throw AidokuRuntimeError.runtimeFailure("Cover response could not be normalized")
        }
        return output as Data
    }

    private static func boundedImageSource(_ data: Data) throws -> CGImageSource {
        guard !data.isEmpty, data.count <= AidokuLimits.maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 1, height > 1,
              width <= 16_384, height <= 16_384,
              width <= AidokuLimits.maximumImageBytes / max(4, height) else {
            throw AidokuRuntimeError.runtimeFailure("Cover response is not a supported image")
        }
        return source
    }

    private static func imageCost(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= Int.max / max(4, height) else { return data.count }
        return max(data.count, width * height * 4)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let error = error as? AidokuCoverHTTPError { return error.isTransient }
        guard let error = error as? URLError else { return false }
        return [
            .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
        ].contains(error.code)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? AidokuRuntimeError) == .cancelled
            || (error as? URLError)?.code == .cancelled
    }
}

private struct AidokuCoverHTTPError: LocalizedError, Sendable {
    let statusCode: Int
    var isTransient: Bool {
        statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
    }
    var errorDescription: String? { "Cover request returned HTTP \(statusCode)" }
}

actor AidokuAsyncPermitPool {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var permits: Int
    private var waiters: [Waiter] = []

    var waitingCount: Int { waiters.count }

    init(limit: Int) { permits = max(1, limit) }

    func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if permits > 0 {
            permits -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
