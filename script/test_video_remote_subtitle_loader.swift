import Foundation

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
        let delay: TimeInterval
    }

    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var capturedRequests: [URLRequest] = []

    private let stateLock = NSLock()
    private var stopped = false

    static func reset(responses: [String: Response]) {
        lock.lock()
        self.responses = responses
        capturedRequests = []
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let response = request.url.flatMap { Self.responses[$0.path] }
        Self.lock.unlock()

        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self, !isStopped else { return }
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/vtt"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func option(
    path: String,
    format: SubtitleFormat = .webVTT,
    headers: [String: String] = [:]
) -> RemoteVideoSubtitleOption {
    RemoteVideoSubtitleOption(
        id: path,
        language: "ja",
        name: "Japanese",
        url: URL(string: "https://subtitle.example\(path)")!,
        format: format,
        isAutomatic: false,
        httpHeaders: headers
    )
}

@main
private enum VideoRemoteSubtitleLoaderTests {
    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-remote-subtitle-tests-\(UUID().uuidString)", isDirectory: true)
        let loader = RemoteSubtitleLoader(session: session, temporaryDirectory: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        StubURLProtocol.reset(responses: [
            "/first": .init(statusCode: 200, data: Data("WEBVTT\n\n".utf8), delay: 0),
            "/second": .init(statusCode: 200, data: Data("1\n00:00:00,000 --> 00:00:01,000\n星\n".utf8), delay: 0),
        ])
        let first = try await loader.load(
            option: option(path: "/first", headers: ["Referer": "https://video.example/"]),
            headers: ["User-Agent": "HoshiTests"],
            generation: 1
        )
        expect(first?.pathExtension == "vtt", "WebVTT should use a .vtt temporary file")
        expect(first.map { FileManager.default.fileExists(atPath: $0.path) } == true, "loaded subtitle should exist")
        let request = StubURLProtocol.requests().first
        expect(request?.value(forHTTPHeaderField: "Referer") == "https://video.example/", "option headers should be sent")
        expect(request?.value(forHTTPHeaderField: "User-Agent") == "HoshiTests", "additional headers should be sent")

        let second = try await loader.load(
            option: option(path: "/second", format: .srt),
            headers: [:],
            generation: 2
        )
        expect(second?.pathExtension == "srt", "explicit SRT should use a .srt temporary file")
        expect(first.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "replacement should delete the previous temporary file")

        StubURLProtocol.reset(responses: [
            "/forbidden": .init(statusCode: 403, data: Data(), delay: 0),
        ])
        do {
            _ = try await loader.load(
                option: option(path: "/forbidden"),
                headers: [:],
                generation: 3
            )
            expect(false, "HTTP 403 should be rejected")
        } catch RemoteSubtitleLoaderError.httpStatus(403) {
        }

        StubURLProtocol.reset(responses: [
            "/slow": .init(statusCode: 200, data: Data("WEBVTT\n\nslow".utf8), delay: 0.3),
            "/new": .init(statusCode: 200, data: Data("WEBVTT\n\nnew".utf8), delay: 0),
        ])
        let staleTask = Task {
            try await loader.load(
                option: option(path: "/slow"),
                headers: [:],
                generation: 4
            )
        }
        try await Task.sleep(for: .milliseconds(30))
        let newest = try await loader.load(
            option: option(path: "/new"),
            headers: [:],
            generation: 5
        )
        let stale = try? await staleTask.value
        expect(stale == nil, "a cancelled stale generation must not install its subtitle")
        expect(newest.map { FileManager.default.fileExists(atPath: $0.path) } == true, "newest subtitle should remain installed")

        loader.cancelAndCleanup()
        expect(second.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "cleanup should remove replaced subtitle files")
        expect(newest.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "cleanup should remove the active subtitle file")
        print("Video remote subtitle loader tests passed")
    }
}
