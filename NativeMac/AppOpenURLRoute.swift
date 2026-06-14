import Foundation

enum AppOpenURLRoute: Equatable {
    case localFile(URL)
    case dictionarySearch(String)
    case remoteBook(URL)

    init?(url: URL) {
        if url.isFileURL {
            self = .localFile(url)
            return
        }

        guard url.scheme?.lowercased() == "hoshi" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host?.lowercased() {
        case "search":
            let query = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            self = .dictionarySearch(query)
        case "open":
            guard let value = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let remoteURL = URL(string: value),
                  let scheme = remoteURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            self = .remoteBook(remoteURL)
        default:
            return nil
        }
    }
}

struct NativeDictionaryOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let query: String
}
