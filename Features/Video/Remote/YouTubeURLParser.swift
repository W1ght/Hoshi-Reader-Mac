#if HOSHI_VIDEO
import Foundation

nonisolated enum YouTubeURLParser {
    static func isYouTubeURL(_ url: URL) -> Bool {
        videoID(from: url) != nil
    }

    static func videoID(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else {
            return nil
        }

        let candidate: String?
        if isHost(host, domain: "youtu.be") {
            candidate = url.pathComponents.dropFirst().first
        } else if isHost(host, domain: "youtube.com")
                    || isHost(host, domain: "youtube-nocookie.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.path == "/watch" || url.path == "/watch/" {
                candidate = components?.queryItems?.first(where: { $0.name == "v" })?.value
            } else {
                let path = url.pathComponents.filter { $0 != "/" }
                if path.count >= 2, path[0] == "shorts" || path[0] == "embed" {
                    candidate = path[1]
                } else {
                    candidate = nil
                }
            }
        } else {
            candidate = nil
        }

        guard let candidate, isValidVideoID(candidate) else { return nil }
        return candidate
    }

    static func canonicalURL(for videoID: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url!
    }

    private static func isHost(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        guard value.count == 11 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
#endif
