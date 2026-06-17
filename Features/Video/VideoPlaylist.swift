#if HOSHI_VIDEO
import Foundation

struct VideoPlaylist: Equatable {
    static let supportedExtensions: Set<String> = [
        "3gp", "aac", "avi", "flac", "flv", "m4a", "m4b", "m4v",
        "mkv", "mov", "mp3", "mp4", "mpeg", "mpg", "ogg", "ogv",
        "opus", "wav", "webm", "wmv"
    ]

    private(set) var items: [URL]
    private(set) var currentIndex: Int?

    init(urls: [URL], currentURL: URL?) {
        items = urls
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        currentIndex = currentURL.flatMap { current in
            items.firstIndex { $0.standardizedFileURL == current.standardizedFileURL }
        }
    }

    var currentURL: URL? {
        currentIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
    }

    var previousURL: URL? {
        guard let currentIndex, currentIndex > 0 else { return nil }
        return items[currentIndex - 1]
    }

    var nextURL: URL? {
        guard let currentIndex, items.indices.contains(currentIndex + 1) else { return nil }
        return items[currentIndex + 1]
    }

    mutating func select(_ url: URL) {
        currentIndex = items.firstIndex {
            $0.standardizedFileURL == url.standardizedFileURL
        }
    }
}
#endif
