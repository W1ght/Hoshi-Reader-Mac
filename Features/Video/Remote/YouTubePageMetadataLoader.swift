#if HOSHI_VIDEO
import Foundation

struct YouTubePageMetadataLoader: Sendable {
    private static let androidVRClientName = "ANDROID_VR"
    private static let androidVRClientID = "28"
    private static let androidVRClientVersion = "1.65.10"
    private static let androidVRUserAgent = "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 20
    ) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    func load(videoID: String) async throws -> YouTubeResolvedPageMetadata {
        guard var components = URLComponents(
            url: YouTubeURLParser.canonicalURL(for: videoID),
            resolvingAgainstBaseURL: false
        ) else {
            throw RemoteVideoResolverError.invalidResponse
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "hl", value: "en"))
        components.queryItems = queryItems
        guard let url = components.url else {
            throw RemoteVideoResolverError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.httpShouldHandleCookies = false

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw RemoteVideoResolverError.invalidResponse
        }
        let watchMetadata = try YouTubeInitialPlayerResponseParser.parse(html: html)
        guard let visitorData = visitorData(from: html) else {
            return YouTubeResolvedPageMetadata(
                duration: watchMetadata.duration,
                subtitleOptions: []
            )
        }

        do {
            let playerData = try await loadAndroidVRPlayerResponse(
                videoID: videoID,
                visitorData: visitorData
            )
            let playerMetadata = try YouTubeAndroidVRPlayerResponseParser.parse(
                data: playerData
            )
            return YouTubeResolvedPageMetadata(
                duration: playerMetadata.duration ?? watchMetadata.duration,
                subtitleOptions: playerMetadata.subtitleOptions
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            return YouTubeResolvedPageMetadata(
                duration: watchMetadata.duration,
                subtitleOptions: []
            )
        }
    }

    private func loadAndroidVRPlayerResponse(
        videoID: String,
        visitorData: String
    ) async throws -> Data {
        guard let url = URL(
            string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
        ) else {
            throw RemoteVideoResolverError.invalidResponse
        }
        let body = AndroidVRPlayerRequest(
            context: .init(
                client: .init(
                    clientName: Self.androidVRClientName,
                    clientVersion: Self.androidVRClientVersion,
                    deviceMake: "Oculus",
                    deviceModel: "Quest 3",
                    androidSdkVersion: 32,
                    userAgent: Self.androidVRUserAgent,
                    osName: "Android",
                    osVersion: "12L",
                    hl: "en",
                    timeZone: "UTC",
                    utcOffsetMinutes: 0,
                    visitorData: visitorData
                )
            ),
            videoId: videoID,
            playbackContext: .init(
                contentPlaybackContext: .init(
                    html5Preference: "HTML5_PREF_WANTS"
                )
            ),
            contentCheckOk: true,
            racyCheckOk: true
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.androidVRUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue(
            Self.androidVRClientID,
            forHTTPHeaderField: "X-Youtube-Client-Name"
        )
        request.setValue(
            Self.androidVRClientVersion,
            forHTTPHeaderField: "X-Youtube-Client-Version"
        )
        request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        request.httpShouldHandleCookies = false

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw RemoteVideoResolverError.invalidResponse
        }
        return data
    }

    private func visitorData(from html: String) -> String? {
        let marker = "\"VISITOR_DATA\""
        guard let markerRange = html.range(of: marker) else { return nil }
        let suffix = html[markerRange.upperBound...]
        guard let colon = suffix.firstIndex(of: ":") else { return nil }
        let valueSuffix = suffix[suffix.index(after: colon)...]
            .drop(while: { $0.isWhitespace })
        guard valueSuffix.first == "\"" else { return nil }

        var index = valueSuffix.index(after: valueSuffix.startIndex)
        var isEscaped = false
        while index < valueSuffix.endIndex {
            let character = valueSuffix[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                let literal = valueSuffix[valueSuffix.startIndex...index]
                return try? JSONDecoder().decode(
                    String.self,
                    from: Data(literal.utf8)
                )
            }
            index = valueSuffix.index(after: index)
        }
        return nil
    }

    private struct AndroidVRPlayerRequest: Encodable {
        let context: Context
        let videoId: String
        let playbackContext: PlaybackContext
        let contentCheckOk: Bool
        let racyCheckOk: Bool

        struct Context: Encodable {
            let client: Client

            struct Client: Encodable {
                let clientName: String
                let clientVersion: String
                let deviceMake: String
                let deviceModel: String
                let androidSdkVersion: Int
                let userAgent: String
                let osName: String
                let osVersion: String
                let hl: String
                let timeZone: String
                let utcOffsetMinutes: Int
                let visitorData: String
            }
        }

        struct PlaybackContext: Encodable {
            let contentPlaybackContext: ContentPlaybackContext

            struct ContentPlaybackContext: Encodable {
                let html5Preference: String
            }
        }
    }
}
#endif
