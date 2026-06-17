#if HOSHI_VIDEO
import Foundation

final class VideoPlaybackHistoryStore {
    private let defaults: UserDefaults
    private let key = "videoPlaybackPositions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for url: URL) -> TimeInterval? {
        positions[url.standardizedFileURL.path]
    }

    func save(position: TimeInterval, duration: TimeInterval, for url: URL) {
        var values = positions
        let path = url.standardizedFileURL.path
        if duration <= 0 || position < 2 || position >= duration - 5 {
            values.removeValue(forKey: path)
        } else {
            values[path] = position
        }
        defaults.set(values, forKey: key)
    }

    private var positions: [String: TimeInterval] {
        defaults.dictionary(forKey: key)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
    }
}
#endif
