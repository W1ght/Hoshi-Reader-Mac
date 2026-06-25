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

struct VideoPlaybackState: Codable, Equatable {
    let position: TimeInterval
    let duration: TimeInterval?
    let updatedAt: Date
    let isFinished: Bool

    var progress: Double? {
        if isFinished {
            return 1
        }
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    var isResumable: Bool {
        guard !isFinished, position >= 2 else { return false }
        return progress.map { $0 < 0.98 } ?? true
    }

    var remainingTime: TimeInterval? {
        guard !isFinished, let duration, duration > position else { return nil }
        return duration - position
    }

    init(
        position: TimeInterval,
        duration: TimeInterval?,
        updatedAt: Date,
        isFinished: Bool = false
    ) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.isFinished = isFinished
    }

    private enum CodingKeys: String, CodingKey {
        case position
        case duration
        case updatedAt
        case isFinished
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(TimeInterval.self, forKey: .position)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
    }
}

final class VideoPlaybackHistoryStore {
    private let defaults: UserDefaults
    private let positionKey = "videoPlaybackPositions"
    private let playbackStateKey = "videoPlaybackStates"
    private let subtitleSelectionKey = "videoSubtitleSelections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for url: URL) -> TimeInterval? {
        if let state = playbackState(for: url) {
            return state.isResumable ? state.position : nil
        }
        return positions[url.standardizedFileURL.path]
    }

    func save(position: TimeInterval, duration: TimeInterval, for url: URL) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: Date(),
            for: url
        )
    }

    func playbackState(for url: URL) -> VideoPlaybackState? {
        let path = url.standardizedFileURL.path
        if let data = playbackStates[path],
           let state = try? JSONDecoder().decode(VideoPlaybackState.self, from: data) {
            return state
        }
        guard let position = positions[path] else { return nil }
        return VideoPlaybackState(
            position: position,
            duration: nil,
            updatedAt: .distantPast
        )
    }

    func playbackStates(for urls: [URL]) -> [String: VideoPlaybackState] {
        let storedStates = playbackStates
        let legacyPositions = positions
        let decoder = JSONDecoder()
        var result: [String: VideoPlaybackState] = [:]
        result.reserveCapacity(urls.count)

        for url in urls {
            let path = url.standardizedFileURL.path
            if let data = storedStates[path],
               let state = try? decoder.decode(VideoPlaybackState.self, from: data) {
                result[path] = state
            } else if let position = legacyPositions[path] {
                result[path] = VideoPlaybackState(
                    position: position,
                    duration: nil,
                    updatedAt: .distantPast
                )
            }
        }

        return result
    }

    func savePlaybackState(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        for url: URL
    ) {
        var values = positions
        var states = playbackStates
        let path = url.standardizedFileURL.path
        if duration <= 0 || position < 2 {
            values.removeValue(forKey: path)
            states.removeValue(forKey: path)
        } else if position >= duration - 5 {
            values.removeValue(forKey: path)
            states[path] = encodedState(
                VideoPlaybackState(
                    position: duration,
                    duration: duration,
                    updatedAt: updatedAt,
                    isFinished: true
                )
            )
        } else {
            values[path] = position
            let state = VideoPlaybackState(
                position: position,
                duration: duration,
                updatedAt: updatedAt
            )
            states[path] = encodedState(state)
        }
        defaults.set(values, forKey: positionKey)
        defaults.set(states, forKey: playbackStateKey)
    }

    func markWatched(
        duration: TimeInterval?,
        updatedAt: Date = Date(),
        for url: URL
    ) {
        let path = url.standardizedFileURL.path
        var values = positions
        var states = playbackStates
        values.removeValue(forKey: path)
        states[path] = encodedState(
            VideoPlaybackState(
                position: max(duration ?? 0, 0),
                duration: duration,
                updatedAt: updatedAt,
                isFinished: true
            )
        )
        defaults.set(values, forKey: positionKey)
        defaults.set(states, forKey: playbackStateKey)
    }

    func clearProgress(for url: URL) {
        let path = url.standardizedFileURL.path
        var values = positions
        var states = playbackStates
        values.removeValue(forKey: path)
        states.removeValue(forKey: path)
        defaults.set(values, forKey: positionKey)
        defaults.set(states, forKey: playbackStateKey)
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

    private var playbackStates: [String: Data] {
        defaults.dictionary(forKey: playbackStateKey)?.compactMapValues {
            $0 as? Data
        } ?? [:]
    }

    private var subtitleSelections: [String: Data] {
        defaults.dictionary(forKey: subtitleSelectionKey)?.compactMapValues {
            $0 as? Data
        } ?? [:]
    }

    private func encodedState(_ state: VideoPlaybackState) -> Data? {
        try? JSONEncoder().encode(state)
    }
}
#endif
