#if HOSHI_VIDEO
import Foundation

nonisolated enum YouTubeInitialPlayerResponseParserError: Error, Equatable, Sendable {
    case invalidJSON
}

nonisolated enum YouTubeInitialPlayerResponseParser {
    static func parse(html: String) throws -> YouTubeResolvedPageMetadata {
        guard let json = extractPlayerResponseJSON(from: html) else {
            return .empty
        }
        return try parse(playerResponseData: Data(json.utf8))
    }

    static func parse(
        playerResponseData: Data
    ) throws -> YouTubeResolvedPageMetadata {
        let response: PlayerResponse
        do {
            response = try JSONDecoder().decode(
                PlayerResponse.self,
                from: playerResponseData
            )
        } catch {
            throw YouTubeInitialPlayerResponseParserError.invalidJSON
        }

        let tracks = response.captions?
            .playerCaptionsTracklistRenderer?
            .captionTracks ?? []
        let options = tracks.enumerated().compactMap { index, track in
            subtitleOption(from: track, index: index)
        }
        return YouTubeResolvedPageMetadata(
            duration: response.videoDetails?
                .lengthSeconds
                .flatMap(TimeInterval.init),
            subtitleOptions: options
        )
    }

    private static func extractPlayerResponseJSON(from html: String) -> String? {
        let markers = [
            "var ytInitialPlayerResponse =",
            "ytInitialPlayerResponse =",
            "\"ytInitialPlayerResponse\":",
        ]
        for marker in markers {
            guard let markerRange = html.range(of: marker) else { continue }
            let suffix = html[markerRange.upperBound...]
            guard let openBrace = suffix.firstIndex(of: "{") else { continue }
            if let object = balancedJSONObject(in: html, startingAt: openBrace) {
                return object
            }
        }
        return nil
    }

    private static func balancedJSONObject(
        in text: String,
        startingAt start: String.Index
    ) -> String? {
        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func subtitleOption(
        from track: CaptionTrack,
        index: Int
    ) -> RemoteVideoSubtitleOption? {
        guard let url = webVTTURL(from: track.baseURL) else {
            return nil
        }
        let isAutomatic = track.kind?.lowercased() == "asr"
        let name = track.name.simpleText
            ?? track.name.runs?.map(\.text).joined()
            ?? track.languageCode
        return RemoteVideoSubtitleOption(
            id: track.vssID ?? "\(track.languageCode)-\(index)",
            language: track.languageCode,
            name: name,
            url: url,
            format: .webVTT,
            isAutomatic: isAutomatic,
            httpHeaders: [:]
        )
    }

    private static func webVTTURL(from rawURL: String) -> URL? {
        guard let url = URL(string: rawURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "fmt" }
        queryItems.append(URLQueryItem(name: "fmt", value: "vtt"))
        components.queryItems = queryItems
        return components.url
    }

    private struct PlayerResponse: Decodable {
        let videoDetails: VideoDetails?
        let captions: Captions?
    }

    private struct VideoDetails: Decodable {
        let lengthSeconds: String?
    }

    private struct Captions: Decodable {
        let playerCaptionsTracklistRenderer: TracklistRenderer?
    }

    private struct TracklistRenderer: Decodable {
        let captionTracks: [CaptionTrack]?
    }

    private struct CaptionTrack: Decodable {
        let baseURL: String
        let name: CaptionName
        let vssID: String?
        let languageCode: String
        let kind: String?

        private enum CodingKeys: String, CodingKey {
            case baseURL = "baseUrl"
            case name
            case vssID = "vssId"
            case languageCode
            case kind
        }
    }

    private struct CaptionName: Decodable {
        let simpleText: String?
        let runs: [TextRun]?
    }

    private struct TextRun: Decodable {
        let text: String
    }
}
#endif
