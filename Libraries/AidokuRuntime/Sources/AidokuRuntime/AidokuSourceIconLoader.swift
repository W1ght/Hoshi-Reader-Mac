import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public protocol AidokuSourceIconTransport: Sendable {
    func data(
        for request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool
    ) async throws -> (Data, HTTPURLResponse)
}

public struct AidokuDefaultSourceIconTransport: AidokuSourceIconTransport {
    public init() {}

    public func data(
        for request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        try await AidokuHTTPClient.data(
            for: request,
            maximumBytes: maximumBytes,
            insecureTransportApproved: insecureTransportApproved
        )
    }
}

/// Loads the small identity image shown beside an Aidoku source.
///
/// Installed sources use their already validated `icon.png`. Sources that have
/// not been installed use the source-list `iconURL`, with the same insecure
/// transport decision as the owning list. Both paths are decoded under a
/// bounded pixel budget and normalized before entering memory or disk caches.
public actor AidokuSourceIconLoader {
    public enum Location: Hashable, Sendable {
        case installedSource(URL)
        case remote(URL, insecureTransportApproved: Bool)

        fileprivate var identity: String {
            switch self {
            case .installedSource(let directory):
                "installed\u{1f}\(directory.standardizedFileURL.path)"
            case .remote(let url, let approved):
                "remote\u{1f}\(url.absoluteString)\u{1f}\(approved)"
            }
        }
    }

    private struct CacheKey: Hashable, Sendable {
        let sourceID: String
        let sourceVersion: Int
        let location: Location

        var identity: String {
            "\(sourceID)\u{1f}\(sourceVersion)\u{1f}\(location.identity)"
        }
    }

    private struct InFlightLoad {
        let id: UUID
        let sourceGeneration: UUID?
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Data, any Error>]
    }

    private static let maximumEncodedBytes = 4 * 1_024 * 1_024
    private static let maximumDecodedBytes = 16 * 1_024 * 1_024
    private static let maximumDimension = 2_048
    private static let maximumCacheBytes: Int64 = 64 * 1_024 * 1_024
    private static let maximumCacheFiles = 512
    private static let negativeCacheLifetime: TimeInterval = 30

    private let cacheRoot: URL
    private let fileManager: FileManager
    private let transport: any AidokuSourceIconTransport
    private let downloads = AidokuAsyncPermitPool(limit: 4)
    private let memoryCache = NSCache<NSString, NSData>()
    private var failedAt: [CacheKey: Date] = [:]
    private var sourceGenerations: [String: UUID] = [:]
    private var inFlight: [CacheKey: InFlightLoad] = [:]

    public init(
        cacheDirectory: URL,
        fileManager: FileManager = .default,
        transport: any AidokuSourceIconTransport = AidokuDefaultSourceIconTransport()
    ) {
        cacheRoot = cacheDirectory.appendingPathComponent("source-icons", isDirectory: true)
        self.fileManager = fileManager
        self.transport = transport
        memoryCache.totalCostLimit = 32 * 1_024 * 1_024
        memoryCache.countLimit = Self.maximumCacheFiles
    }

    public func data(
        sourceID: String,
        sourceVersion: Int,
        location: Location
    ) async throws -> Data {
        guard AidokuPackageValidator.isSafeSourceID(sourceID), sourceVersion >= 0 else {
            throw AidokuRuntimeError.invalidSourceID
        }
        let key = CacheKey(
            sourceID: sourceID,
            sourceVersion: sourceVersion,
            location: location
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
        do {
            let data = try await sharedLoad(for: key, sourceGeneration: sourceGeneration)
            try Task.checkCancellation()
            guard sourceGenerations[sourceID] == sourceGeneration else {
                throw CancellationError()
            }
            return data
        } catch {
            if sourceGenerations[sourceID] == sourceGeneration,
               !Self.isCancellation(error) {
                failedAt[key] = Date()
            }
            throw error
        }
    }

    public func invalidateSource(_ sourceID: String) throws {
        guard AidokuPackageValidator.isSafeSourceID(sourceID) else {
            throw AidokuRuntimeError.invalidSourceID
        }
        failedAt = failedAt.filter { $0.key.sourceID != sourceID }
        sourceGenerations[sourceID] = UUID()
        memoryCache.removeAllObjects()
        for key in inFlight.keys where key.sourceID == sourceID {
            cancelLoad(for: key)
        }
        let sourceCache = cacheRoot.appendingPathComponent(sourceID, isDirectory: true)
        if fileManager.fileExists(atPath: sourceCache.path) {
            try fileManager.removeItem(at: sourceCache)
        }
    }

    private func sharedLoad(for key: CacheKey, sourceGeneration: UUID?) async throws -> Data {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var load = inFlight[key] {
                    load.waiters[waiterID] = continuation
                    inFlight[key] = load
                    return
                }

                let loadID = UUID()
                let location = key.location
                let sourceID = key.sourceID
                let transport = transport
                let downloads = downloads
                let task = Task { [weak self] in
                    do {
                        let data = try await downloads.withPermit {
                            switch location {
                            case .installedSource(let directory):
                                return try Self.loadInstalledIcon(
                                    sourceID: sourceID,
                                    sourceDirectory: directory
                                )
                            case .remote(let url, let approved):
                                return try await Self.loadRemoteIcon(
                                    url: url,
                                    insecureTransportApproved: approved,
                                    transport: transport
                                )
                            }
                        }
                        await self?.completeLoad(
                            for: key,
                            id: loadID,
                            result: .success(data)
                        )
                    } catch {
                        await self?.completeLoad(
                            for: key,
                            id: loadID,
                            result: .failure(error)
                        )
                    }
                }
                inFlight[key] = InFlightLoad(
                    id: loadID,
                    sourceGeneration: sourceGeneration,
                    task: task,
                    waiters: [waiterID: continuation]
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: key, loadID: nil, waiterID: waiterID) }
        }
    }

    private func completeLoad(
        for key: CacheKey,
        id: UUID,
        result: Result<Data, any Error>
    ) {
        guard let load = inFlight[key], load.id == id else { return }
        inFlight[key] = nil
        switch result {
        case .success(let data):
            guard sourceGenerations[key.sourceID] == load.sourceGeneration else {
                for continuation in load.waiters.values {
                    continuation.resume(throwing: CancellationError())
                }
                return
            }
            failedAt[key] = nil
            let memoryKey = key.identity as NSString
            memoryCache.setObject(data as NSData, forKey: memoryKey, cost: Self.imageCost(data))
            store(data, for: key)
            for continuation in load.waiters.values {
                continuation.resume(returning: data)
            }
        case .failure(let error):
            for continuation in load.waiters.values {
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancelWaiter(
        for key: CacheKey,
        loadID: UUID?,
        waiterID: UUID
    ) {
        guard var load = inFlight[key],
              loadID == nil || load.id == loadID,
              let continuation = load.waiters.removeValue(forKey: waiterID) else { return }
        if load.waiters.isEmpty {
            inFlight[key] = nil
            load.task.cancel()
        } else {
            inFlight[key] = load
        }
        continuation.resume(throwing: CancellationError())
    }

    private func cancelLoad(for key: CacheKey) {
        guard let load = inFlight.removeValue(forKey: key) else { return }
        load.task.cancel()
        for continuation in load.waiters.values {
            continuation.resume(throwing: CancellationError())
        }
    }

    private static func loadInstalledIcon(
        sourceID: String,
        sourceDirectory: URL
    ) throws -> Data {
        guard sourceDirectory.standardizedFileURL.lastPathComponent == sourceID else {
            throw AidokuRuntimeError.invalidSourceID
        }
        let iconURL = sourceDirectory.appendingPathComponent("icon.png", isDirectory: false)
        guard iconURL.standardizedFileURL.path.hasPrefix(
            sourceDirectory.standardizedFileURL.path + "/"
        ) else {
            throw AidokuRuntimeError.unsafeArchivePath("icon.png")
        }
        let values = try iconURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumEncodedBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return try normalizedImageData(boundedFileData(at: iconURL))
    }

    private static func loadRemoteIcon(
        url: URL,
        insecureTransportApproved: Bool,
        transport: any AidokuSourceIconTransport
    ) async throws -> Data {
        try AidokuSourceListParser.validateRemoteURL(
            url,
            insecureTransportConfirmed: insecureTransportApproved
        )
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Niratan AidokuRuntime/1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(
            for: request,
            maximumBytes: maximumEncodedBytes,
            insecureTransportApproved: insecureTransportApproved
        )
        guard (200..<300).contains(response.statusCode) else {
            throw AidokuSourceIconHTTPError(statusCode: response.statusCode)
        }
        return try normalizedImageData(data)
    }

    private func cachedData(for key: CacheKey) -> Data? {
        let url = cacheURL(for: key)
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let size = values.fileSize,
        size > 0,
        size <= Self.maximumEncodedBytes,
        let data = try? Self.boundedFileData(at: url),
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
            // Icons remain available from the memory cache when disk caching fails.
        }
    }

    private func cacheURL(for key: CacheKey) -> URL {
        cacheRoot
            .appendingPathComponent(key.sourceID, isDirectory: true)
            .appendingPathComponent(String(key.sourceVersion), isDirectory: true)
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
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            files.append((url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast))
        }
        var bytes = files.reduce(Int64(0)) { $0 + $1.size }
        while files.count > Self.maximumCacheFiles || bytes > Self.maximumCacheBytes {
            files.sort { $0.date < $1.date }
            let oldest = files.removeFirst()
            if (try? fileManager.removeItem(at: oldest.url)) != nil { bytes -= oldest.size }
        }
    }

    private static func normalizedImageData(_ data: Data) throws -> Data {
        let source = try boundedImageSource(data)
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw AidokuRuntimeError.runtimeFailure("Source icon is not a supported image")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AidokuRuntimeError.runtimeFailure("Source icon could not be normalized")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination),
              output.length > 0,
              output.length <= maximumEncodedBytes else {
            throw AidokuRuntimeError.runtimeFailure("Source icon could not be normalized")
        }
        return output as Data
    }

    private static func boundedFileData(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var output = Data()
        while output.count <= maximumEncodedBytes {
            let remaining = maximumEncodedBytes + 1 - output.count
            guard remaining > 0,
                  let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
                  !chunk.isEmpty else { break }
            output.append(chunk)
        }
        guard !output.isEmpty, output.count <= maximumEncodedBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return output
    }

    private static func validateImage(_ data: Data) throws {
        let source = try boundedImageSource(data)
        guard CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) != nil else {
            throw AidokuRuntimeError.runtimeFailure("Source icon is not a supported image")
        }
    }

    @discardableResult
    private static func boundedImageSource(_ data: Data) throws -> CGImageSource {
        guard !data.isEmpty,
              data.count <= maximumEncodedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 1,
              height > 1,
              width <= maximumDimension,
              height <= maximumDimension,
              width <= maximumDecodedBytes / max(4, height) else {
            throw AidokuRuntimeError.runtimeFailure("Source icon is not a supported image")
        }
        return source
    }

    private static func imageCost(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= Int.max / max(4, height) else { return data.count }
        return max(data.count, width * height * 4)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? AidokuRuntimeError) == .cancelled
            || (error as? URLError)?.code == .cancelled
    }
}

private struct AidokuSourceIconHTTPError: LocalizedError, Sendable {
    let statusCode: Int
    var errorDescription: String? { "Source icon request returned HTTP \(statusCode)" }
}
