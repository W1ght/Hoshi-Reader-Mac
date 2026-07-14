import Foundation

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var requestBodies: [Data?] = []

    static func reset() {
        lock.lock()
        requests = []
        requestBodies = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func capturedRequestBodies() -> [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodies
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.lock.lock()
        Self.requests.append(request)
        Self.requestBodies.append(body)
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let data: Data
        if request.httpMethod == "POST" {
            data = Data(#"""
            {
              "videoDetails": {"lengthSeconds": "1111"},
              "captions": {
                "playerCaptionsTracklistRenderer": {
                  "captionTracks": [
                    {
                      "baseUrl": "https://www.youtube.com/api/timedtext?v=ref&lang=ja&fmt=srv3",
                      "name": {"simpleText": "Japanese"},
                      "vssId": ".ja",
                      "languageCode": "ja"
                    },
                    {
                      "baseUrl": "https://www.youtube.com/api/timedtext?v=ref&kind=asr&lang=ja&fmt=srv3",
                      "name": {"simpleText": "Japanese (auto-generated)"},
                      "vssId": "a.ja",
                      "languageCode": "ja",
                      "kind": "asr"
                    }
                  ]
                }
              }
            }
            """#.utf8)
        } else {
            data = Data(#"""
            <script>
            ytcfg.set({"VISITOR_DATA":"visitor%3D%3D"});
            var ytInitialPlayerResponse = {
              "videoDetails": {"lengthSeconds": "1110"},
              "captions": {
                "playerCaptionsTracklistRenderer": {
                  "captionTracks": [{
                    "baseUrl": "https://www.youtube.com/api/timedtext?v=ref&lang=ja&exp=xpe",
                    "name": {"simpleText": "Japanese"},
                    "vssId": ".ja",
                    "languageCode": "ja"
                  }]
                }
              }
            };
            </script>
            """#.utf8)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoYouTubePageMetadataLoaderTests {
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            try await runLiveReferenceCheck()
            return
        }

        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let loader = YouTubePageMetadataLoader(
            session: URLSession(configuration: configuration)
        )

        let metadata = try await loader.load(videoID: "yrL6Qny0E5M")
        expect(metadata.duration == 1_111, "Android VR duration should replace the watch-page fallback")
        expect(metadata.subtitleOptions.map(\.id) == [".ja"], "only publisher captions should survive")
        expect(
            metadata.subtitleOptions.first?.url.absoluteString.contains("exp=xpe") == false,
            "watch-page caption URLs must not leak into the result"
        )
        expect(
            URLComponents(
                url: metadata.subtitleOptions[0].url,
                resolvingAgainstBaseURL: false
            )?.queryItems?.filter { $0.name == "fmt" }.map(\.value) == ["vtt"],
            "Android VR captions should request WebVTT"
        )

        let requests = StubURLProtocol.capturedRequests()
        let requestBodies = StubURLProtocol.capturedRequestBodies()
        expect(requests.count == 2, "metadata loading should issue one watch request and one player request")
        guard let playerRequestIndex = requests.firstIndex(where: { $0.httpMethod == "POST" }),
              let body = requestBodies[playerRequestIndex],
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let context = json["context"] as? [String: Any],
              let client = context["client"] as? [String: Any] else {
            fputs("FAIL: Android VR player request should be inspectable\n", stderr)
            exit(1)
        }
        let playerRequest = requests[playerRequestIndex]
        expect(client["clientName"] as? String == "ANDROID_VR", "player request should use Android VR")
        expect(client["visitorData"] as? String == "visitor%3D%3D", "watch visitor data should propagate")
        expect(json["videoId"] as? String == "yrL6Qny0E5M", "player request should retain the video ID")
        expect(
            playerRequest.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == "visitor%3D%3D",
            "visitor data should also be sent as a player request header"
        )

        print("Video YouTube page metadata loader tests passed")
    }

    private static func runLiveReferenceCheck() async throws {
        let loader = YouTubePageMetadataLoader()
        let metadata = try await loader.load(videoID: "yrL6Qny0E5M")
        expect(metadata.subtitleOptions.map(\.language).contains("ja"), "live metadata should include Japanese")
        expect(
            metadata.subtitleOptions.allSatisfy { !$0.isAutomatic },
            "live metadata must exclude automatic captions"
        )
        guard let japanese = metadata.subtitleOptions.first(where: { $0.language == "ja" }) else {
            fputs("FAIL: live Japanese publisher subtitle should exist\n", stderr)
            exit(1)
        }
        var downloadedByteCounts: [String: Int] = [:]
        for option in metadata.subtitleOptions {
            var request = URLRequest(url: option.url)
            for (name, value) in option.httpHeaders {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            expect(
                (response as? HTTPURLResponse)?.statusCode == 200,
                "live \(option.language) publisher subtitle should download"
            )
            expect(
                data.count > 1_000,
                "live \(option.language) publisher subtitle should not be empty"
            )
            expect(
                String(decoding: data.prefix(6), as: UTF8.self) == "WEBVTT",
                "live \(option.language) publisher subtitle should be WebVTT"
            )
            downloadedByteCounts[option.id] = data.count
        }
        print(
            "Video YouTube live subtitle check passed: \(metadata.subtitleOptions.count) publisher languages, \(downloadedByteCounts[japanese.id] ?? 0) Japanese VTT bytes"
        )
    }
}
