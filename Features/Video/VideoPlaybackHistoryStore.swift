#if HOSHI_VIDEO
import Foundation

nonisolated struct VideoSubtitleTrackIdentity: Codable, Equatable, Hashable, Sendable {
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

nonisolated enum VideoSubtitleSelection: Codable, Equatable, Hashable, Sendable {
    case off
    case embedded(VideoSubtitleTrackIdentity)
    case external(path: String)
    case remote(language: String)

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        guard case .embedded(let identity) = self else { return nil }
        return identity.matchingTrackID(in: tracks)
    }
}

nonisolated struct VideoAudioTrackIdentity: Codable, Equatable, Hashable, Sendable {
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
        let audioTracks = tracks.filter { $0.type == .audio }
        if let ffIndex {
            if let match = audioTracks.first(where: { $0.ffIndex == ffIndex }) {
                return match.id
            }
        } else if let match = audioTracks.first(where: { $0.id == trackID }) {
            return match.id
        }
        let metadataMatches = audioTracks.filter {
            $0.title == title
                && $0.language == language
                && $0.codec == codec
        }
        return metadataMatches.count == 1 ? metadataMatches[0].id : nil
    }
}

nonisolated enum VideoAudioSelection: Codable, Equatable, Hashable, Sendable {
    case off
    case embedded(VideoAudioTrackIdentity)

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        guard case .embedded(let identity) = self else { return nil }
        return identity.matchingTrackID(in: tracks)
    }
}

nonisolated struct VideoPlaybackResumeOptions: Codable, Equatable, Sendable {
    static let empty = VideoPlaybackResumeOptions()

    let speed: Double?
    let subtitleDelay: TimeInterval?
    let audioDelay: TimeInterval?
    let audioSelection: VideoAudioSelection?

    var isEmpty: Bool {
        speed == nil
            && subtitleDelay == nil
            && audioDelay == nil
            && audioSelection == nil
    }

    init(
        speed: Double? = nil,
        subtitleDelay: TimeInterval? = nil,
        audioDelay: TimeInterval? = nil,
        audioSelection: VideoAudioSelection? = nil
    ) {
        self.speed = speed.map(Self.normalizedSpeed)
        self.subtitleDelay = subtitleDelay.map(Self.normalizedSubtitleDelay)
        self.audioDelay = audioDelay.map(Self.normalizedAudioDelay)
        self.audioSelection = audioSelection
    }

    init(snapshot: VideoPlaybackSnapshot) {
        let normalizedSpeed = Self.normalizedSpeed(snapshot.speed)
        speed = abs(normalizedSpeed - Self.normalSpeed) >= 0.001
            ? normalizedSpeed
            : nil

        let normalizedSubtitleDelay = Self.normalizedSubtitleDelay(snapshot.subtitleDelay)
        subtitleDelay = abs(normalizedSubtitleDelay) >= 0.005
            ? normalizedSubtitleDelay
            : nil

        let normalizedAudioDelay = Self.normalizedAudioDelay(snapshot.audioDelay)
        audioDelay = abs(normalizedAudioDelay) >= 0.005
            ? normalizedAudioDelay
            : nil

        audioSelection = Self.audioSelection(from: snapshot.tracks)
    }

    private static func audioSelection(from tracks: [VideoTrack]) -> VideoAudioSelection? {
        let audioTracks = tracks.filter { $0.type == .audio }
        guard !audioTracks.isEmpty else { return nil }
        guard let selectedTrack = audioTracks.first(where: \.isSelected) else {
            return .off
        }
        return .embedded(VideoAudioTrackIdentity(track: selectedTrack))
    }

    private static func normalizedSubtitleDelay(_ delay: TimeInterval) -> TimeInterval {
        VideoSubtitleTiming.clampedDelay(delay)
    }

    private static func normalizedAudioDelay(_ delay: TimeInterval) -> TimeInterval {
        min(max(delay, -30), 30)
    }

    private static let minimumSpeed = 0.25
    private static let maximumSpeed = 5.0
    private static let normalSpeed = 1.0
    private static let customInputLowerBound = 0.3
    private static let customStep = 0.1

    private static func normalizedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return normalSpeed }
        guard speed > minimumSpeed else { return minimumSpeed }
        let rounded = (speed / customStep).rounded() * customStep
        return min(max(rounded, customInputLowerBound), maximumSpeed)
    }
}

nonisolated enum VideoSubtitleRestoreResolution: Equatable, Sendable {
    case off
    case external(URL)
    case embeddedTrack(Int)
    case remoteLanguage(String)
    case waitingForTracks
    case unavailable
}

nonisolated enum VideoSubtitleRestoreResolver {
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
        case .remote(let language):
            return .remoteLanguage(language)
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

nonisolated struct VideoPlaybackState: Codable, Equatable, Sendable {
    let position: TimeInterval
    let duration: TimeInterval?
    let updatedAt: Date
    let isFinished: Bool
    let resumeOptions: VideoPlaybackResumeOptions

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
        isFinished: Bool = false,
        resumeOptions: VideoPlaybackResumeOptions = .empty
    ) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.isFinished = isFinished
        self.resumeOptions = resumeOptions
    }

    private enum CodingKeys: String, CodingKey {
        case position
        case duration
        case updatedAt
        case isFinished
        case resumeOptions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(TimeInterval.self, forKey: .position)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        resumeOptions = try container.decodeIfPresent(
            VideoPlaybackResumeOptions.self,
            forKey: .resumeOptions
        ) ?? .empty
    }
}

nonisolated final class VideoPlaybackHistoryStore: @unchecked Sendable {
    private static let persistenceQueue = DispatchQueue(
        label: "moe.shishamo.hoshi.video.playback-history",
        qos: .utility
    )

    private let defaults: UserDefaults
    private let positionKey = "videoPlaybackPositions"
    private let playbackStateKey = "videoPlaybackStates"
    private let subtitleSelectionKey = "videoSubtitleSelections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func position(for url: URL) -> TimeInterval? {
        position(for: Self.localIdentity(for: url))
    }

    func position(for identity: VideoMediaIdentity) -> TimeInterval? {
        if let state = playbackState(for: identity) {
            return state.isResumable ? state.position : nil
        }
        return positions[identity.persistenceKey]
    }

    func save(
        position: TimeInterval,
        duration: TimeInterval,
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: Date(),
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func save(
        position: TimeInterval,
        duration: TimeInterval,
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: Date(),
            resumeOptions: resumeOptions,
            for: identity
        )
    }

    func playbackState(for url: URL) -> VideoPlaybackState? {
        playbackState(for: Self.localIdentity(for: url))
    }

    func playbackState(for identity: VideoMediaIdentity) -> VideoPlaybackState? {
        let key = identity.persistenceKey
        if let data = playbackStates[key],
           let state = try? JSONDecoder().decode(VideoPlaybackState.self, from: data) {
            return state
        }
        guard let position = positions[key] else { return nil }
        return VideoPlaybackState(
            position: position,
            duration: nil,
            updatedAt: .distantPast
        )
    }

    func playbackStates(for urls: [URL]) -> [String: VideoPlaybackState] {
        playbackStates(for: urls.map(Self.localIdentity(for:)))
    }

    func playbackStates(
        for identities: [VideoMediaIdentity]
    ) -> [String: VideoPlaybackState] {
        let storedStates = playbackStates
        let legacyPositions = positions
        let decoder = JSONDecoder()
        var result: [String: VideoPlaybackState] = [:]
        result.reserveCapacity(identities.count)

        for identity in identities {
            let key = identity.persistenceKey
            if let data = storedStates[key],
               let state = try? decoder.decode(VideoPlaybackState.self, from: data) {
                result[key] = state
            } else if let position = legacyPositions[key] {
                result[key] = VideoPlaybackState(
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
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func savePlaybackState(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        var values = positions
        var states = playbackStates
        let key = identity.persistenceKey
        if duration <= 0 || position < 2 {
            values.removeValue(forKey: key)
            states.removeValue(forKey: key)
        } else if position >= duration - 5 {
            values.removeValue(forKey: key)
            states[key] = encodedState(
                VideoPlaybackState(
                    position: duration,
                    duration: duration,
                    updatedAt: updatedAt,
                    isFinished: true
                )
            )
        } else {
            values[key] = position
            let state = VideoPlaybackState(
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                resumeOptions: resumeOptions
            )
            states[key] = encodedState(state)
        }
        defaults.set(values, forKey: positionKey)
        defaults.set(states, forKey: playbackStateKey)
    }

    func savePlaybackStateDeferred(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackStateDeferred(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func savePlaybackStateDeferred(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        Self.persistenceQueue.async { [self] in
            savePlaybackState(
                position: position,
                duration: duration,
                updatedAt: updatedAt,
                resumeOptions: resumeOptions,
                for: identity
            )
        }
    }

    func markWatched(
        duration: TimeInterval?,
        updatedAt: Date = Date(),
        for url: URL
    ) {
        markWatched(
            duration: duration,
            updatedAt: updatedAt,
            for: Self.localIdentity(for: url)
        )
    }

    func markWatched(
        duration: TimeInterval?,
        updatedAt: Date = Date(),
        for identity: VideoMediaIdentity
    ) {
        let key = identity.persistenceKey
        var values = positions
        var states = playbackStates
        values.removeValue(forKey: key)
        states[key] = encodedState(
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
        clearProgress(for: Self.localIdentity(for: url))
    }

    func clearProgress(for identity: VideoMediaIdentity) {
        let key = identity.persistenceKey
        var values = positions
        var states = playbackStates
        values.removeValue(forKey: key)
        states.removeValue(forKey: key)
        defaults.set(values, forKey: positionKey)
        defaults.set(states, forKey: playbackStateKey)
    }

    func subtitleSelection(for url: URL) -> VideoSubtitleSelection? {
        subtitleSelection(for: Self.localIdentity(for: url))
    }

    func subtitleSelection(for identity: VideoMediaIdentity) -> VideoSubtitleSelection? {
        guard let data = subtitleSelections[identity.persistenceKey] else {
            return nil
        }
        return try? JSONDecoder().decode(VideoSubtitleSelection.self, from: data)
    }

    func save(subtitleSelection: VideoSubtitleSelection, for url: URL) {
        save(
            subtitleSelection: subtitleSelection,
            for: Self.localIdentity(for: url)
        )
    }

    func save(
        subtitleSelection: VideoSubtitleSelection,
        for identity: VideoMediaIdentity
    ) {
        guard let data = try? JSONEncoder().encode(subtitleSelection) else { return }
        var values = subtitleSelections
        values[identity.persistenceKey] = data
        defaults.set(values, forKey: subtitleSelectionKey)
    }

    private static func localIdentity(for url: URL) -> VideoMediaIdentity {
        .localFile(path: url.standardizedFileURL.path)
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
