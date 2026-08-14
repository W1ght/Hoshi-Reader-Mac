import AppKit
import Foundation
import JavaScriptCore
import SwiftSoup
import Wasm3
import WebKit

final class AidokuHostStore: @unchecked Sendable {
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
    private let cookies: [AidokuStoredCookie]
    private let sourceUserAgent: String?
    private static let globalPermits = DispatchSemaphore(value: 12)
    private(set) var cancelled = false
    private(set) var partialResults: [Data] = []
    private var latestNetworkError: String?
    private var latestSourceDiagnostic: String?

    init(
        defaults: [String: Data],
        maximumParallelRequests: Int,
        cookies: [AidokuStoredCookie],
        userAgent: String?,
        defaultsWriter: @escaping @Sendable ([String: Data]) -> Void
    ) {
        self.defaults = defaults
        self.defaultsWriter = defaultsWriter
        self.cookies = cookies
        sourceUserAgent = userAgent
        permits = DispatchSemaphore(value: min(max(1, maximumParallelRequests), 5))
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
        var headers = request.headers
        if headers.keys.first(where: {
            $0.caseInsensitiveCompare("User-Agent") == .orderedSame
        }) == nil {
            headers["User-Agent"] = sourceUserAgent ?? "Niratan AidokuRuntime/1"
        }
        if headers.keys.first(where: {
            $0.caseInsensitiveCompare("Cookie") == .orderedSame
        }) == nil, let cookie = cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        return AidokuImageRequest(url: url, headers: headers)
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
        result.setValue(sourceUserAgent ?? "Niratan AidokuRuntime/1", forHTTPHeaderField: "User-Agent")
        if let cookie = cookieHeader(for: url) { result.setValue(cookie, forHTTPHeaderField: "Cookie") }
        request.headers.forEach { result.setValue($0.value, forHTTPHeaderField: $0.key) }
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
        lock.withLock { partialResults.append(data) }
    }

    func sendRequest(_ descriptor: Int32) -> Int32 {
        guard !lock.withLock({ cancelled }) else { return -10 }
        guard var request = withItem(descriptor, { item -> NetworkRequest? in
            guard case .request(let request) = item else { return nil }
            return request
        }) ?? nil, let originalURL = request.url else {
            return -4
        }
        let url = AidokuLegacyRequestCompatibility.normalizedURL(originalURL)
        guard
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else {
            return -4
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = min(max(1, request.timeout), 120)
        urlRequest.setValue(sourceUserAgent ?? "Niratan AidokuRuntime/1", forHTTPHeaderField: "User-Agent")
        if let cookie = cookieHeader(for: url) { urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie") }
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        permits.wait()
        Self.globalPermits.wait()
        defer {
            Self.globalPermits.signal()
            permits.signal()
        }
        let box = AidokuNetworkResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = Task.detached {
            do {
                let (data, response) = try await AidokuHTTPClient.data(
                    for: urlRequest,
                    maximumBytes: AidokuLimits.maximumImageBytes
                )
                box.set(data: data, response: response, error: nil)
            } catch {
                box.set(data: nil, response: nil, error: error)
            }
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if lock.withLock({ cancelled }) {
                task.cancel()
                return -10
            }
        }
        guard box.error == nil,
              let data = box.data,
              data.count <= AidokuLimits.maximumImageBytes,
              let response = box.response as? HTTPURLResponse,
              let finalURL = response.url,
              finalURL.scheme?.lowercased() == "http" || finalURL.scheme?.lowercased() == "https" else {
            if let error = box.error {
                lock.withLock { latestNetworkError = error.localizedDescription }
            }
            return box.data?.count ?? 0 > AidokuLimits.maximumImageBytes ? -11 : -10
        }
        request.response = NetworkResponse(
            url: finalURL,
            statusCode: response.statusCode,
            headers: response.allHeaderFields.reduce(into: [:]) { result, pair in
                result[String(describing: pair.key)] = String(describing: pair.value)
            },
            data: data
        )
        _ = updateItem(descriptor) { $0 = .request(request) }
        return 0
    }

    private func cookieHeader(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let now = Date()
        let validCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (cookie.expiresAt.map { $0 > now } ?? true)
                && (!cookie.secure || url.scheme?.lowercased() == "https")
                && (host == domain || host.hasSuffix(".\(domain)"))
                && url.path.hasPrefix(cookie.path.isEmpty ? "/" : cookie.path)
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
    private var storage: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    var data: Data? { lock.withLock { storage.0 } }
    var response: URLResponse? { lock.withLock { storage.1 } }
    var error: Error? { lock.withLock { storage.2 } }
    func set(data: Data?, response: URLResponse?, error: Error?) {
        lock.withLock { storage = (data, response, error) }
    }
}

private extension NSLocking {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
