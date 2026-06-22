#if HOSHI_VIDEO
import Foundation

struct VideoSubtitleTrackIdentity: Codable, Equatable, Hashable {
    let trackID: Int
    let ffIndex: Int?
    let title: String
    let language: String?
    let codec: String?

    init(track: VideoTrack) {
        trackID = track.id
        ffIndex = track.ffIndex
        title = track.title
        language = track.language
        codec = track.codec
    }

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        let subtitleTracks = tracks.filter { $0.type == .subtitle }
        if let ffIndex {
            if let match = subtitleTracks.first(where: { $0.ffIndex == ffIndex }) {
                return match.id
            }
        } else if let match = subtitleTracks.first(where: { $0.id == trackID }) {
            return match.id
        }
        let metadataMatches = subtitleTracks.filter {
            $0.title == title
                && $0.language == language
                && $0.codec == codec
        }
        return metadataMatches.count == 1 ? metadataMatches[0].id : nil
    }
}

enum VideoSubtitleSelection: Codable, Equatable, Hashable {
    case off
    case embedded(VideoSubtitleTrackIdentity)
    case external(path: String)

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        guard case .embedded(let identity) = self else { return nil }
        return identity.matchingTrackID(in: tracks)
    }
}

enum VideoSubtitleRestoreResolution: Equatable {
    case off
    case external(URL)
    case embeddedTrack(Int)
    case waitingForTracks
    case unavailable
}

enum VideoSubtitleRestoreResolver {
    static func resolve(
        selection: VideoSubtitleSelection,
        tracks: [VideoTrack],
        isLoaded: Bool,
        fileManager: FileManager = .default
    ) -> VideoSubtitleRestoreResolution {
        switch selection {
        case .off:
            return .off
        case .external(let path):
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return fileManager.fileExists(atPath: url.path)
                ? .external(url)
                : .unavailable
        case .embedded:
            guard isLoaded else { return .waitingForTracks }
            if let trackID = selection.matchingTrackID(in: tracks) {
                return .embeddedTrack(trackID)
            }
            return isLoaded && !tracks.isEmpty
                ? .unavailable
                : .waitingForTracks
        }
    }
}

final class VideoPlaybackHistoryStore {
    private let defaults: UserDefaults
    private let positionKey = "videoPlaybackPositions"
    private let subtitleSelectionKey = "videoSubtitleSelections"

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
        defaults.set(values, forKey: positionKey)
    }

    func subtitleSelection(for url: URL) -> VideoSubtitleSelection? {
        guard let data = subtitleSelections[url.standardizedFileURL.path] else {
            return nil
        }
        return try? JSONDecoder().decode(VideoSubtitleSelection.self, from: data)
    }

    func save(subtitleSelection: VideoSubtitleSelection, for url: URL) {
        guard let data = try? JSONEncoder().encode(subtitleSelection) else { return }
        var values = subtitleSelections
        values[url.standardizedFileURL.path] = data
        defaults.set(values, forKey: subtitleSelectionKey)
    }

    private var positions: [String: TimeInterval] {
        defaults.dictionary(forKey: positionKey)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
    }

    private var subtitleSelections: [String: Data] {
        defaults.dictionary(forKey: subtitleSelectionKey)?.compactMapValues {
            $0 as? Data
        } ?? [:]
    }
}
#endif
