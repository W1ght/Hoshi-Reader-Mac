import Foundation

/// Narrow compatibility rewrites for source requests whose upstream endpoint
/// moved while the installed `.aix` still emits the previous canonical URL.
///
/// Rules live at the bounded HTTP-request edge so installed packages remain
/// immutable and every redirect is still validated by `AidokuHTTPClient`.
enum AidokuLegacyRequestCompatibility {
    static func normalizedURL(_ url: URL) -> URL {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
           components.host?.lowercased() == "appcn.baozimh.com",
           components.port == nil || components.port == 443,
           components.query == nil,
           components.fragment == nil else {
            return url
        }

        let path = url.pathComponents
        guard path.count == 6,
              path[1] == "baozimhapp",
              path[2] == "comic",
              path[3] == "chapter",
              !path[4].isEmpty,
              path[5].hasSuffix(".html") else {
            return url
        }

        let slotPair = path[5].dropLast(".html".count).split(
            separator: "_",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard slotPair.count == 2,
              slotPair.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return url
        }

        var current = URLComponents()
        current.scheme = "https"
        current.host = "www.baozimh.com"
        current.path = "/user/page_direct"
        current.queryItems = [
            URLQueryItem(name: "comic_id", value: path[4]),
            URLQueryItem(name: "section_slot", value: String(slotPair[0])),
            URLQueryItem(name: "chapter_slot", value: String(slotPair[1])),
        ]
        return current.url ?? url
    }
}
