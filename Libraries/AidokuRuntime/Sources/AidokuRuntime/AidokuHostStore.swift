import AppKit
import Foundation
import JavaScriptCore
import SwiftSoup
import Wasm3
import WebKit

final class AidokuHostStore: @unchecked Sendable {
    typealias NetworkHandler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias LogHandler = @Sendable (String) -> Void

    struct NetworkRequest {
        var method: String
        var url: URL?
        var headers: [String: String] = [:]
        var body: Data?
        var timeout: TimeInterval = 30
        var response: NetworkResponse?
    }

    struct NetworkResponse {
        let url: URL
        let statusCode: Int
        let headers: [String: String]
        let data: Data
    }

    final class Canvas {
        let width: Int
        let height: Int
        let bitmap: NSBitmapImageRep
        let context: CGContext

        init?(width: Int, height: Int) {
            guard width > 0, height > 0,
                  width <= 16_384, height <= 16_384,
                  width <= AidokuLimits.maximumImageBytes / max(4, height),
                  let bitmap = NSBitmapImageRep(
                      bitmapDataPlanes: nil,
                      pixelsWide: width,
                      pixelsHigh: height,
                      bitsPerSample: 8,
                      samplesPerPixel: 4,
                      hasAlpha: true,
                      isPlanar: false,
                      colorSpaceName: .deviceRGB,
                      bitmapFormat: [.alphaNonpremultiplied],
                      bytesPerRow: width * 4,
                      bitsPerPixel: 32
                  ), let bitmapData = bitmap.bitmapData else {
                return nil
            }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: bitmapData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bitmap.bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            self.width = width
            self.height = height
            self.bitmap = bitmap
            self.context = context
        }

        func pngData() -> Data? { bitmap.representation(using: .png, properties: [:]) }
    }

    enum Item {
        case bytes(Data)
        case request(NetworkRequest)
        case document(Document)
        case node(Node)
        case element(Element)
        case elements([Element])
        case nodes([Node])
        case jsContext(JavaScriptCore.JSContext)
        case webView(AidokuIsolatedWebView)
        case canvas(Canvas)
        case image(NSImage, Data)
        case font(NSFont)
    }

    private let lock = NSRecursiveLock()
    private var nextDescriptor: Int32 = 1
    private var items: [Int32: Item] = [:]
    private var defaults: [String: Data]
    private var registeredDefaults: [String: Data] = [:]
    private let defaultsWriter: @Sendable ([String: Data]) -> Void
    private let permits: DispatchSemaphore
    private let maximumParallelRequests: Int
    private var cookies: [AidokuStoredCookie]
    private let sourceUserAgent: String
    private let sourceID: String
    private let networkHandler: NetworkHandler?
    private let logHandler: LogHandler
    private static let globalPermits = DispatchSemaphore(value: 12)
    private var rateLimitPermits = 0
    private var rateLimitPeriod: Int64 = 0
    private var rateLimitPeriodStart: Int64 = 0
    private var rateLimitRequestsInPeriod = 0
    private(set) var cancelled = false
    private var partialResults: [Data] = []
    private var latestNetworkError: String?
    private var latestSourceDiagnostic: String?
    private var pendingWebsiteVerificationRequest: AidokuWebsiteVerificationRequest?

    init(
        defaults: [String: Data],
        maximumParallelRequests: Int,
        cookies: [AidokuStoredCookie],
        userAgent: String?,
        sourceID: String = "unknown",
        networkHandler: NetworkHandler? = nil,
        logHandler: LogHandler? = nil,
        defaultsWriter: @escaping @Sendable ([String: Data]) -> Void
    ) {
        self.defaults = defaults
        self.defaultsWriter = defaultsWriter
        self.cookies = cookies
        self.sourceID = Self.normalizedLogValue(sourceID, fallback: "unknown", maximumLength: 256)
        self.networkHandler = networkHandler
        self.logHandler = logHandler ?? { message in fputs("\(message)\n", stderr) }
        sourceUserAgent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? userAgent!
            : "Niratan AidokuRuntime/1"
        self.maximumParallelRequests = min(max(1, maximumParallelRequests), 5)
        permits = DispatchSemaphore(value: self.maximumParallelRequests)
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func resetCancellation() {
        lock.withLock {
            cancelled = false
            partialResults.removeAll(keepingCapacity: true)
            latestNetworkError = nil
            latestSourceDiagnostic = nil
        }
    }

    func sourceFailureMessage(for result: Int32) -> String {
        lock.withLock {
            switch result {
            case -1:
                if let latestSourceDiagnostic, !latestSourceDiagnostic.isEmpty {
                    return "Aidoku source failed: \(latestSourceDiagnostic)"
                }
                return "Aidoku source could not decode its input"
            case -2: return "This Aidoku source operation is not implemented"
            case -3:
                if let latestNetworkError, !latestNetworkError.isEmpty {
                    return "Aidoku source request failed: \(latestNetworkError)"
                }
                return "Aidoku source request failed"
            default: return "Aidoku source failed with code \(result)"
            }
        }
    }

    func clearWebsiteVerificationRequest() {
        lock.withLock { pendingWebsiteVerificationRequest = nil }
    }

    func takeWebsiteVerificationRequest() -> AidokuWebsiteVerificationRequest? {
        lock.withLock {
            let request = pendingWebsiteVerificationRequest
            pendingWebsiteVerificationRequest = nil
            return request
        }
    }

    func recordSourceDiagnostic(_ value: String) {
        let normalized = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Error:"
        guard normalized.hasPrefix(prefix) else { return }
        let diagnostic = normalized
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diagnostic.isEmpty else { return }
        lock.withLock {
            latestSourceDiagnostic = String(diagnostic.prefix(2_048))
        }
    }

    func logSourceMessage(_ value: String) {
        recordSourceDiagnostic(value)
        let lines = value.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            logHandler("[Aidoku][\(sourceID)] \(line)")
        }
    }

    func store(_ item: Item) -> Int32 {
        lock.withLock {
            guard nextDescriptor < Int32.max else { return -1 }
            let descriptor = nextDescriptor
            nextDescriptor += 1
            items[descriptor] = item
            return descriptor
        }
    }

    func store(bytes: Data) -> Int32 { store(.bytes(bytes)) }
    func storeImage(_ data: Data) -> Int32? {
        guard data.count <= AidokuLimits.maximumImageBytes,
              let image = decodedBitmapImage(data),
              let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= 16_384,
              bitmap.pixelsHigh <= 16_384,
              bitmap.pixelsWide <= AidokuLimits.maximumImageBytes / max(4, bitmap.pixelsHigh) else {
            return nil
        }
        return store(.image(image, data))
    }

    private func decodedBitmapImage(_ data: Data) -> NSImage? {
        guard let representation = NSBitmapImageRep(data: data) else { return nil }
        let image = NSImage(size: NSSize(width: representation.pixelsWide, height: representation.pixelsHigh))
        image.addRepresentation(representation)
        return image
    }

    func networkRequest(_ descriptor: Int32) -> AidokuImageRequest? {
        guard let request = withItem(descriptor, { item -> NetworkRequest? in
            guard case .request(let request) = item else { return nil }
            return request
        }) ?? nil, let originalURL = request.url else { return nil }
        let url = AidokuLegacyRequestCompatibility.normalizedURL(originalURL)
        return modifiedImageRequest(AidokuImageRequest(url: url, headers: request.headers))
    }

    func modifiedImageRequest(_ request: AidokuImageRequest) -> AidokuImageRequest {
        AidokuImageRequest(
            url: request.url,
            headers: modifiedHeaders(sourceHeaders: request.headers, for: request.url)
        )
    }

    func urlRequest(_ descriptor: Int32) -> URLRequest? {
        guard let request = withItem(descriptor, { item -> NetworkRequest? in
            guard case .request(let request) = item else { return nil }
            return request
        }) ?? nil, let originalURL = request.url else { return nil }
        let url = AidokuLegacyRequestCompatibility.normalizedURL(originalURL)
        var result = URLRequest(url: url)
        result.httpMethod = request.method
        result.httpBody = request.body
        result.timeoutInterval = min(max(1, request.timeout), 120)
        modifiedHeaders(sourceHeaders: request.headers, for: url).forEach {
            result.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        return result
    }
    func bytes(_ descriptor: Int32) -> Data? {
        lock.withLock {
            switch items[descriptor] {
            case .bytes(let data): data
            case .image(_, let data): data
            default: nil
            }
        }
    }

    func destroy(_ descriptor: Int32) {
        lock.withLock {
            items[descriptor] = nil
            if items.isEmpty { nextDescriptor = 1 }
        }
    }

    func withItem<T>(_ descriptor: Int32, _ body: (Item) throws -> T) rethrows -> T? {
        try lock.withLock {
            guard let item = items[descriptor] else { return nil }
            return try body(item)
        }
    }

    func updateItem<T>(_ descriptor: Int32, _ body: (inout Item) throws -> T) rethrows -> T? {
        try lock.withLock {
            guard var item = items.removeValue(forKey: descriptor) else { return nil }
            defer { items[descriptor] = item }
            return try body(&item)
        }
    }

    func defaultsValue(for key: String) -> Data? {
        lock.withLock { defaults[key] ?? registeredDefaults[key] }
    }
    func registerDefaults(_ values: [String: Data]) {
        lock.withLock {
            for (key, value) in values where registeredDefaults[key] == nil {
                registeredDefaults[key] = value
            }
        }
    }
    func setDefaultsValue(_ value: Data?, for key: String) {
        let snapshot = lock.withLock { () -> [String: Data] in
            defaults[key] = value
            return defaults
        }
        defaultsWriter(snapshot)
    }

    func appendPartialResult(pointer: Int32, memory: MemoryReader) {
        guard let data = try? memory.resultData(at: pointer) else { return }
        appendPartialResult(data)
    }

    func appendPartialResult(_ data: Data) {
        lock.withLock { partialResults.append(data) }
    }

    func takePartialResults() -> [Data] {
        lock.withLock {
            let results = partialResults
            partialResults.removeAll(keepingCapacity: true)
            return results
        }
    }

    func discardPartialResults() {
        lock.withLock { partialResults.removeAll(keepingCapacity: true) }
    }

    func sendRequests(_ descriptors: [Int32]) -> [Int32] {
        let work = AidokuNetworkWorkQueue(descriptors: descriptors)
        let group = DispatchGroup()
        for _ in 0..<min(maximumParallelRequests, descriptors.count) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                while let (index, descriptor) = work.next() {
                    work.set(sendRequest(descriptor, operation: "send_all"), at: index)
                }
                group.leave()
            }
        }
        while group.wait(timeout: .now() + 0.05) == .timedOut {
            // Each worker observes this flag in rate/permit/network waits. Keeping
            // the synchronous ABI here avoids blocking Swift's cooperative pool.
            if lock.withLock({ cancelled }) { continue }
        }
        return work.values
    }

    func setRateLimit(permits: Int32, period: Int32, unit: Int32) {
        let unitSeconds: Int64
        switch unit {
        case 1: unitSeconds = 60
        case 2: unitSeconds = 3_600
        default: unitSeconds = 1
        }
        lock.withLock {
            rateLimitPermits = Int(permits)
            rateLimitPeriod = Int64(period) * unitSeconds
        }
    }

    func sendRequest(_ descriptor: Int32, operation: String = "send") -> Int32 {
        guard !lock.withLock({ cancelled }) else { return -10 }
        guard var request = withItem(descriptor, { item -> NetworkRequest? in
            guard case .request(let request) = item else { return nil }
            return request
        }) ?? nil else { return -1 }
        guard let originalURL = request.url else { return -9 }
        let url = AidokuLegacyRequestCompatibility.normalizedURL(originalURL)
        guard
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else {
            return -4
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = min(max(1, request.timeout), 120)
        modifiedHeaders(sourceHeaders: request.headers, for: url).forEach {
            urlRequest.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let verificationRequest = AidokuWebsiteVerificationRequest(
            url: url,
            method: urlRequest.httpMethod ?? "GET",
            headers: urlRequest.allHTTPHeaderFields ?? [:],
            body: urlRequest.httpBody,
            userAgent: urlRequest.value(forHTTPHeaderField: "User-Agent") ?? sourceUserAgent
        )
        let finalRequest = urlRequest
        guard waitForRateLimitPermit() else { return -10 }
        guard waitForNetworkPermit(permits) else { return -10 }
        guard waitForNetworkPermit(Self.globalPermits) else {
            permits.signal()
            return -10
        }
        defer {
            Self.globalPermits.signal()
            permits.signal()
        }
        let startedAt = ContinuousClock.now
        let box = AidokuNetworkResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let networkHandler = networkHandler
        let task = Task.detached {
            do {
                let (data, response) = if let networkHandler {
                    try await networkHandler(finalRequest)
                } else {
                    try await AidokuHTTPClient.data(
                        for: finalRequest,
                        maximumBytes: AidokuLimits.maximumImageBytes,
                        responseObserver: { response in
                            guard let responseURL = response.url else { return }
                            let fields = response.allHeaderFields.reduce(into: [String: String]()) {
                                result, pair in
                                result[String(describing: pair.key)] = String(describing: pair.value)
                            }
                            self.storeResponseCookies(fields, for: responseURL)
                        }
                    )
                }
                box.set(data: data, response: response, error: nil)
            } catch {
                box.set(data: nil, response: nil, error: error)
            }
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if lock.withLock({ cancelled }) {
                task.cancel()
                logNetworkTrace(
                    operation: operation,
                    request: finalRequest,
                    response: nil,
                    startedAt: startedAt
                )
                return -10
            }
        }
        guard box.error == nil,
              let data = box.data,
              data.count <= AidokuLimits.maximumImageBytes,
              let response = box.response,
              let finalURL = response.url,
              finalURL.scheme?.lowercased() == "http" || finalURL.scheme?.lowercased() == "https" else {
            if let error = box.error {
                lock.withLock { latestNetworkError = error.localizedDescription }
            }
            logNetworkTrace(
                operation: operation,
                request: finalRequest,
                response: nil,
                startedAt: startedAt
            )
            return box.data?.count ?? 0 > AidokuLimits.maximumImageBytes ? -11 : -10
        }
        let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
        storeResponseCookies(responseHeaders, for: finalURL)
        recordWebsiteVerificationIfNeeded(
            response: response,
            data: data,
            request: verificationRequest
        )
        request.response = NetworkResponse(
            url: finalURL,
            statusCode: response.statusCode,
            headers: responseHeaders,
            data: data
        )
        _ = updateItem(descriptor) { $0 = .request(request) }
        logNetworkTrace(
            operation: operation,
            request: finalRequest,
            response: response,
            startedAt: startedAt
        )
        return 0
    }

    private func waitForRateLimitPermit() -> Bool {
        while true {
            let waitSeconds: Int64? = lock.withLock {
                guard !cancelled else { return -1 }
                guard rateLimitPermits > 0, rateLimitPeriod > 0 else { return nil }
                let now = Int64(Date().timeIntervalSince1970)
                let inPeriod = now - rateLimitPeriodStart < rateLimitPeriod
                if inPeriod, rateLimitRequestsInPeriod >= rateLimitPermits {
                    return max(0, rateLimitPeriodStart + rateLimitPeriod - now)
                }
                if !inPeriod {
                    rateLimitPeriodStart = now
                    rateLimitRequestsInPeriod = 0
                }
                rateLimitRequestsInPeriod += 1
                return nil
            }
            guard let waitSeconds else { return true }
            guard waitSeconds >= 0 else { return false }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(waitSeconds))
            while clock.now < deadline {
                if lock.withLock({ cancelled }) { return false }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func waitForNetworkPermit(_ semaphore: DispatchSemaphore) -> Bool {
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if lock.withLock({ cancelled }) { return false }
        }
        return true
    }

    private func modifiedHeaders(sourceHeaders: [String: String], for url: URL) -> [String: String] {
        var headers = sourceHeaders
        if headerKey("User-Agent", in: headers) == nil {
            headers["User-Agent"] = sourceUserAgent
        }
        if let storedCookie = cookieHeader(for: url) {
            if let originalKey = headerKey("Cookie", in: headers) {
                headers[originalKey] = storedCookie + "; " + (headers[originalKey] ?? "")
            } else {
                headers["Cookie"] = storedCookie
            }
        }
        return headers
    }

    private func headerKey(_ name: String, in headers: [String: String]) -> String? {
        headers.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func cookieHeader(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let now = Date()
        let validCookies = lock.withLock { cookies }.filter { cookie in
            let rawDomain = cookie.domain.lowercased()
            let domain = rawDomain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let domainMatches = rawDomain.hasPrefix(".")
                ? (host == domain || host.hasSuffix(".\(domain)"))
                : host == domain
            return (cookie.expiresAt.map { $0 > now } ?? true)
                && (!cookie.secure || url.scheme?.lowercased() == "https")
                && domainMatches
                && Self.cookiePath(cookie.path, matches: url.path)
        }.compactMap { cookie -> HTTPCookie? in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path.isEmpty ? "/" : cookie.path,
                .secure: cookie.secure ? "TRUE" : "FALSE",
            ]
            if let expiresAt = cookie.expiresAt { properties[.expires] = expiresAt }
            return HTTPCookie(properties: properties)
        }
        return validCookies.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: validCookies)["Cookie"]
    }

    private func storeResponseCookies(_ fields: [String: String], for url: URL) {
        let incoming = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map {
            AidokuStoredCookie(
                name: $0.name,
                value: $0.value,
                domain: $0.domain,
                path: $0.path,
                secure: $0.isSecure,
                expiresAt: $0.expiresDate
            )
        }
        guard !incoming.isEmpty else { return }
        let now = Date()
        lock.withLock {
            for cookie in incoming {
                let identity = Self.cookieIdentity(cookie)
                cookies.removeAll { Self.cookieIdentity($0) == identity }
                if cookie.expiresAt.map({ $0 > now }) ?? true {
                    cookies.append(cookie)
                }
            }
            if cookies.count > 256 {
                cookies.removeFirst(cookies.count - 256)
            }
        }
    }

    private func logNetworkTrace(
        operation: String,
        request: URLRequest,
        response: HTTPURLResponse?,
        startedAt: ContinuousClock.Instant
    ) {
        let duration = startedAt.duration(to: .now)
        let components = duration.components
        let milliseconds = max(
            0,
            components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        )
        let operation = Self.normalizedLogValue(operation, fallback: "send", maximumLength: 32)
        let method = Self.normalizedLogValue(request.httpMethod, fallback: "GET", maximumLength: 16)
        let host = Self.normalizedLogValue(request.url?.host?.lowercased(), fallback: "-", maximumLength: 255)
        let status = response.map { String($0.statusCode) } ?? "-"
        let contentType = Self.normalizedLogValue(
            response?.mimeType?.lowercased(),
            fallback: "-",
            maximumLength: 128
        )
        logHandler(
            "[Aidoku][\(sourceID)] network operation=\(operation) method=\(method) host=\(host) "
                + "status=\(status) duration_ms=\(milliseconds) content_type=\(contentType)"
        )
    }

    private static func cookieIdentity(_ cookie: AidokuStoredCookie) -> String {
        let domain = cookie.domain
            .lowercased()
        return "\(cookie.name)\u{0}\(domain)\u{0}\(cookie.path.isEmpty ? "/" : cookie.path)"
    }

    private static func cookiePath(_ value: String, matches requestPath: String) -> Bool {
        let cookiePath = value.isEmpty ? "/" : value
        let requestPath = requestPath.isEmpty ? "/" : requestPath
        guard requestPath.hasPrefix(cookiePath) else { return false }
        if requestPath.count == cookiePath.count || cookiePath.hasSuffix("/") { return true }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return requestPath[boundary] == "/"
    }

    private static func normalizedLogValue(
        _ value: String?,
        fallback: String,
        maximumLength: Int
    ) -> String {
        guard let value else { return fallback }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return normalized.isEmpty ? fallback : String(normalized.prefix(maximumLength))
    }

    func recordWebsiteVerificationIfNeeded(
        response: HTTPURLResponse,
        data: Data,
        request: AidokuWebsiteVerificationRequest
    ) {
        guard AidokuCloudflareChallengeDetector.shouldHandle(response: response, data: data) else {
            return
        }
        lock.withLock {
            if pendingWebsiteVerificationRequest == nil {
                pendingWebsiteVerificationRequest = request
            }
        }
    }
}

enum AidokuCloudflareChallengeDetector {
    private static let blockedStatusCodes: Set<Int> = [403, 503]
    private static let serverNames: Set<String> = ["cloudflare", "cloudflare-nginx"]

    static func shouldHandle(response: HTTPURLResponse, data: Data) -> Bool {
        guard data.count <= AidokuLimits.maximumJSONBytes,
              blockedStatusCodes.contains(response.statusCode),
              let server = response.value(forHTTPHeaderField: "Server")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              serverNames.contains(server),
              let html = String(data: data, encoding: .utf8),
              let document = try? SwiftSoup.parse(html) else {
            return false
        }
        return (try? document.getElementById("challenge-error-title")) != nil
            || (try? document.getElementById("challenge-error-text")) != nil
    }
}

struct MemoryReader: @unchecked Sendable {
    let memory: Memory

    func string(pointer: Int32, length: Int32) throws -> String {
        guard pointer >= 0, length >= 0,
              length <= AidokuLimits.maximumJSONBytes else {
            throw AidokuRuntimeError.runtimeFailure("Invalid source memory access")
        }
        return try memory.readString(offset: UInt32(pointer), length: UInt32(length))
    }

    func data(pointer: Int32, length: Int32, maximum: Int = AidokuLimits.maximumImageBytes) throws -> Data {
        guard pointer >= 0, length >= 0, length <= maximum else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return try memory.readData(offset: UInt32(pointer), length: UInt32(length))
    }

    func write(_ data: Data, pointer: Int32) throws {
        guard pointer >= 0 else { throw AidokuRuntimeError.runtimeFailure("Invalid source memory access") }
        try memory.write(data: data, offset: UInt32(pointer))
    }

    func resultData(at pointer: Int32) throws -> Data {
        guard pointer > 0 else { throw AidokuRuntimeError.runtimeFailure("Invalid source result pointer") }
        let header = try memory.readData(offset: UInt32(pointer), length: 12)
        let first = Int32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        if first == -1 {
            let total = Int32(littleEndian: header.dropFirst(8).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
            guard total >= 12, total <= AidokuLimits.maximumJSONBytes else {
                throw AidokuRuntimeError.runtimeFailure("Aidoku source failed")
            }
            let message = try memory.readString(
                offset: UInt32(pointer + 12),
                length: UInt32(total - 12)
            )
            throw AidokuRuntimeError.runtimeFailure(message)
        }
        guard first >= 8, first <= AidokuLimits.maximumImageBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return try memory.readData(offset: UInt32(pointer + 8), length: UInt32(first - 8))
    }
}

private final class AidokuNetworkResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (Data?, HTTPURLResponse?, Error?) = (nil, nil, nil)
    var data: Data? { lock.withLock { storage.0 } }
    var response: HTTPURLResponse? { lock.withLock { storage.1 } }
    var error: Error? { lock.withLock { storage.2 } }
    func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        lock.withLock { storage = (data, response, error) }
    }
}

private final class AidokuNetworkWorkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let descriptors: [Int32]
    private var nextIndex = 0
    private var storage: [Int32]

    init(descriptors: [Int32]) {
        self.descriptors = descriptors
        storage = Array(repeating: -10, count: descriptors.count)
    }

    var values: [Int32] { lock.withLock { storage } }

    func next() -> (Int, Int32)? {
        lock.withLock {
            guard nextIndex < descriptors.count else { return nil }
            let index = nextIndex
            nextIndex += 1
            return (index, descriptors[index])
        }
    }

    func set(_ value: Int32, at index: Int) {
        lock.withLock { storage[index] = value }
    }
}

private extension NSLocking {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
