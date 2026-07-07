#if HOSHI_VIDEO
import Foundation
import Observation

@Observable
@MainActor
final class VideoPlayerViewModel {
    private static let subtitleDelayRange: ClosedRange<TimeInterval> = -10...10
    private static let audioDelayRange: ClosedRange<TimeInterval> = -30...30
    private static let defaultSubtitleGapFastForwardSpeed = 2.7
    private static let subtitleGapFastForwardEdgeGuard: TimeInterval = 0.6

    let engine: any PlaybackEngine
    var snapshot = VideoPlaybackSnapshot()
    var inspectorState = VideoInspectorState()
    var currentURL: URL?
    var errorMessage: String?
    var playlist = VideoPlaylist(urls: [], currentURL: nil)
    var autoPlayNext: Bool
    var rememberPlaybackPosition: Bool {
        didSet {
            if !rememberPlaybackPosition {
                pendingRestorePosition = nil
                pendingPlaybackState = nil
                pendingSubtitleSelection = nil
            }
        }
    }
    private(set) var loadGeneration = 0
    private(set) var pendingABLoopStart: TimeInterval?
    private(set) var pendingSubtitleSelection: VideoSubtitleSelection?

    private var isAccessingSecurityScopedURL = false
    private let historyStore: VideoPlaybackHistoryStore
    @ObservationIgnored private var playlistScanTask: Task<Void, Never>?
    private var pendingPlaybackState: VideoPlaybackState?
    private var pendingRestorePosition: TimeInterval?
    private var subtitleGapFastForwardSpeed = defaultSubtitleGapFastForwardSpeed
    private var subtitleGapFastForwardBaseSpeed: Double?
    private(set) var isSubtitleGapFastForwardEnabled = false
    private var lastSavedSecond = -1
    private var requestedRotation = 0

    init(
        engine: any PlaybackEngine,
        historyStore: VideoPlaybackHistoryStore = VideoPlaybackHistoryStore(),
        autoPlayNext: Bool = true,
        rememberPlaybackPosition: Bool = true
    ) {
        self.engine = engine
        self.historyStore = historyStore
        self.autoPlayNext = autoPlayNext
        self.rememberPlaybackPosition = rememberPlaybackPosition
        engine.onSnapshotChanged = { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        engine.onPlaybackEnded = { [weak self] in
            guard self?.autoPlayNext == true else { return }
            self?.playNext()
        }
    }

    isolated deinit {
        playlistScanTask?.cancel()
        if isAccessingSecurityScopedURL {
            currentURL?.stopAccessingSecurityScopedResource()
        }
    }

    func open(_ url: URL) {
        playlistScanTask?.cancel()
        playlist = VideoPlaylist(urls: [url], currentURL: url)
        openPlaylistItem(url)
        configurePlaylistInBackground(around: url)
    }

    func playPrevious() {
        guard let url = playlist.previousURL else { return }
        openPlaylistItem(url)
    }

    func playNext() {
        guard let url = playlist.nextURL else { return }
        openPlaylistItem(url)
    }

    func selectPlaylistItem(_ url: URL) {
        guard playlist.items.contains(where: {
            $0.standardizedFileURL == url.standardizedFileURL
        }) else {
            return
        }
        openPlaylistItem(url)
    }

    private func openPlaylistItem(_ url: URL) {
        saveCurrentPosition(deferred: false)
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        stopAccessingCurrentURL()
        currentURL = url
        playlist.select(url)
        let playbackState = rememberPlaybackPosition
            ? historyStore.playbackState(for: url)
            : nil
        pendingPlaybackState = playbackState?.isFinished == false
            ? playbackState
            : nil
        pendingRestorePosition = playbackState?.isResumable == true
            ? playbackState?.position
            : nil
        pendingSubtitleSelection = rememberPlaybackPosition
            ? historyStore.subtitleSelection(for: url)
            : nil
        lastSavedSecond = -1
        requestedRotation = 0
        isAccessingSecurityScopedURL = url.startAccessingSecurityScopedResource()
        do {
            try engine.load(url: url)
            loadGeneration &+= 1
            snapshot = engine.snapshot
            inspectorState = VideoInspectorState(snapshot: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingPlaybackState = nil
            pendingRestorePosition = nil
            pendingSubtitleSelection = nil
            stopAccessingCurrentURL()
        }
    }

    func togglePlayback() {
        snapshot.isPlaying ? engine.pause() : engine.play()
    }

    func seek(to time: TimeInterval) {
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        engine.seek(to: min(max(time, 0), snapshot.duration))
    }

    func skip(by interval: TimeInterval) {
        seek(to: snapshot.currentTime + interval)
    }

    func setSpeed(_ speed: Double) {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(speed)
        if subtitleGapFastForwardBaseSpeed != nil {
            subtitleGapFastForwardBaseSpeed = normalizedSpeed
            return
        }
        engine.setSpeed(normalizedSpeed)
    }

    func adjustSpeed(by delta: Double) {
        setSpeed(currentUserSpeed + delta)
    }

    func setSubtitleGapFastForwardEnabled(_ enabled: Bool) {
        guard isSubtitleGapFastForwardEnabled != enabled else { return }
        isSubtitleGapFastForwardEnabled = enabled
        if !enabled {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
        }
    }

    func setSubtitleGapFastForwardSpeed(_ speed: Double) {
        subtitleGapFastForwardSpeed = Self.normalizedSubtitleGapFastForwardSpeed(speed)
        if subtitleGapFastForwardBaseSpeed != nil
            && abs(snapshot.speed - subtitleGapFastForwardSpeed) >= 0.001 {
            engine.setSpeed(subtitleGapFastForwardSpeed)
        }
    }

    func updateSubtitleGapPlayback(
        slice: SubtitleCueSlice,
        playbackTime: TimeInterval,
        isPlaybackPaused: Bool
    ) {
        guard isSubtitleGapFastForwardEnabled, !isPlaybackPaused else {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
            return
        }
        guard shouldFastForwardSubtitleGap(slice: slice, playbackTime: playbackTime) else {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
            return
        }
        if subtitleGapFastForwardBaseSpeed == nil {
            subtitleGapFastForwardBaseSpeed = snapshot.speed
        }
        if abs(snapshot.speed - subtitleGapFastForwardSpeed) >= 0.001 {
            engine.setSpeed(subtitleGapFastForwardSpeed)
        }
    }

    func setVolume(_ volume: Double) {
        engine.setVolume(min(max(volume, 0), 100))
    }

    func toggleMuted() {
        engine.setMuted(!snapshot.isMuted)
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        engine.setSubtitleDelay(
            min(max(delay, Self.subtitleDelayRange.lowerBound), Self.subtitleDelayRange.upperBound)
        )
    }

    func adjustSubtitleDelay(by delta: TimeInterval) {
        setSubtitleDelay(snapshot.subtitleDelay + delta)
    }

    func setAudioDelay(_ delay: TimeInterval) {
        engine.setAudioDelay(
            min(max(delay, Self.audioDelayRange.lowerBound), Self.audioDelayRange.upperBound)
        )
    }

    func adjustAudioDelay(by delta: TimeInterval) {
        setAudioDelay(snapshot.audioDelay + delta)
    }

    func setLoopMode(_ mode: VideoLoopMode) {
        engine.setLoopMode(mode)
    }

    func setABLoopStart() {
        setABLoopStart(at: snapshot.currentTime)
    }

    func setABLoopStart(at time: TimeInterval) {
        pendingABLoopStart = clampedPlaybackTime(time)
        if snapshot.abLoop != nil {
            engine.setABLoop(nil)
        }
    }

    func setABLoopEnd() {
        setABLoopEnd(at: snapshot.currentTime)
    }

    func setABLoopEnd(at time: TimeInterval) {
        guard let start = pendingABLoopStart ?? snapshot.abLoop?.start else {
            return
        }
        let end = clampedPlaybackTime(time)
        guard end > start else { return }
        engine.setABLoop(VideoABLoop(start: start, end: end))
        pendingABLoopStart = nil
    }

    func clearABLoop() {
        pendingABLoopStart = nil
        engine.setABLoop(nil)
    }

    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {
        engine.setAspectRatio(aspectRatio)
    }

    func rotateClockwise() {
        requestedRotation = (requestedRotation + 90) % 360
        engine.setRotation(requestedRotation)
    }

    func setHardwareDecodingEnabled(_ enabled: Bool) {
        engine.setHardwareDecodingEnabled(enabled)
    }

    func setDeinterlacingEnabled(_ enabled: Bool) {
        engine.setDeinterlacingEnabled(enabled)
    }

    func setHDREnhancementEnabled(_ enabled: Bool) {
        engine.setHDREnhancementEnabled(enabled)
    }

    func setVideoEqualizer(_ adjustment: VideoEqualizerAdjustment, value: Double) {
        engine.setVideoEqualizer(
            adjustment,
            value: VideoEqualizerAdjustment.normalized(value)
        )
    }

    private func clampedPlaybackTime(_ time: TimeInterval) -> TimeInterval {
        guard snapshot.duration > 0 else {
            return max(time, 0)
        }
        return min(max(time, 0), snapshot.duration)
    }

    func seekToChapter(_ index: Int) {
        engine.seekToChapter(index)
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        engine.selectTrack(type: type, id: id)
    }

    func loadExternalSubtitle(_ url: URL) {
        engine.loadExternalSubtitle(url: url)
    }

    func rememberSubtitleSelection(_ selection: VideoSubtitleSelection) {
        guard rememberPlaybackPosition, let currentURL else { return }
        historyStore.save(subtitleSelection: selection, for: currentURL)
    }

    func consumePendingSubtitleSelection() -> VideoSubtitleSelection? {
        defer { pendingSubtitleSelection = nil }
        return pendingSubtitleSelection
    }

    func shutdown() {
        saveCurrentPosition(deferred: false)
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        engine.shutdown()
        stopAccessingCurrentURL()
    }

    private func stopAccessingCurrentURL() {
        if isAccessingSecurityScopedURL {
            currentURL?.stopAccessingSecurityScopedResource()
        }
        isAccessingSecurityScopedURL = false
    }

    private func configurePlaylistInBackground(around url: URL) {
        let requestedURL = url.standardizedFileURL
        playlistScanTask = Task { [weak self] in
            let urls = await Self.playlistURLs(around: url)
            guard !Task.isCancelled,
                  let self,
                  self.currentURL?.standardizedFileURL == requestedURL else {
                return
            }
            playlist = VideoPlaylist(urls: urls, currentURL: url)
        }
    }

    private nonisolated static func playlistURLs(around url: URL) async -> [URL] {
        await Task.detached(priority: .utility) {
            let directory = url.deletingLastPathComponent()
            return (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? [url]
        }.value
    }

    private func handleSnapshot(_ snapshot: VideoPlaybackSnapshot) {
        self.snapshot = snapshot
        let nextInspectorState = VideoInspectorState(snapshot: snapshot)
        if nextInspectorState != inspectorState {
            inspectorState = nextInspectorState
        }
        requestedRotation = snapshot.rotation
        if pendingPlaybackState != nil || pendingRestorePosition != nil {
            guard snapshot.isLoaded, snapshot.duration > 0 else { return }
            let playbackState = pendingPlaybackState
            let position = pendingRestorePosition
            pendingPlaybackState = nil
            pendingRestorePosition = nil
            lastSavedSecond = 0
            if let playbackState {
                restoreResumeOptions(playbackState.resumeOptions, tracks: snapshot.tracks)
            }
            if let position {
                engine.seek(to: min(position, snapshot.duration))
            }
            return
        }
        let second = Int(snapshot.currentTime)
        if second != lastSavedSecond, second.isMultiple(of: 5) {
            lastSavedSecond = second
            saveCurrentPosition(deferred: true)
        }
    }

    private func restoreResumeOptions(
        _ options: VideoPlaybackResumeOptions,
        tracks: [VideoTrack]
    ) {
        if let speed = options.speed {
            engine.setSpeed(VideoPlaybackSpeed.normalized(speed))
        }
        if let subtitleDelay = options.subtitleDelay {
            engine.setSubtitleDelay(
                min(
                    max(subtitleDelay, Self.subtitleDelayRange.lowerBound),
                    Self.subtitleDelayRange.upperBound
                )
            )
        }
        if let audioDelay = options.audioDelay {
            engine.setAudioDelay(
                min(
                    max(audioDelay, Self.audioDelayRange.lowerBound),
                    Self.audioDelayRange.upperBound
                )
            )
        }
        if let audioSelection = options.audioSelection {
            switch audioSelection {
            case .off:
                engine.selectTrack(type: .audio, id: nil)
            case .embedded:
                if let trackID = audioSelection.matchingTrackID(in: tracks) {
                    engine.selectTrack(type: .audio, id: trackID)
                }
            }
        }
    }

    private func saveCurrentPosition(deferred: Bool) {
        guard rememberPlaybackPosition, let currentURL else { return }
        let resumeOptions = VideoPlaybackResumeOptions(snapshot: snapshotForPersistence)
        if deferred {
            historyStore.savePlaybackStateDeferred(
                position: snapshot.currentTime,
                duration: snapshot.duration,
                resumeOptions: resumeOptions,
                for: currentURL
            )
            return
        }
        historyStore.save(
            position: snapshot.currentTime,
            duration: snapshot.duration,
            resumeOptions: resumeOptions,
            for: currentURL
        )
    }

    private var currentUserSpeed: Double {
        subtitleGapFastForwardBaseSpeed ?? snapshot.speed
    }

    private static func normalizedSubtitleGapFastForwardSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else {
            return VideoPlaybackSpeed.normalized(defaultSubtitleGapFastForwardSpeed)
        }
        return VideoPlaybackSpeed.normalized(min(max(speed, 1.1), 5.0))
    }

    private var snapshotForPersistence: VideoPlaybackSnapshot {
        guard let baseSpeed = subtitleGapFastForwardBaseSpeed else {
            return snapshot
        }
        var persistentSnapshot = snapshot
        persistentSnapshot.speed = baseSpeed
        return persistentSnapshot
    }

    private func shouldFastForwardSubtitleGap(
        slice: SubtitleCueSlice,
        playbackTime: TimeInterval
    ) -> Bool {
        guard slice.showing.isEmpty,
              let previousEnd = slice.lastShown.map(\.endTime).max(),
              let nextStart = slice.nextToShow.map(\.startTime).min() else {
            return false
        }
        return playbackTime - previousEnd > Self.subtitleGapFastForwardEdgeGuard
            && nextStart - playbackTime > Self.subtitleGapFastForwardEdgeGuard
    }

    private func restoreSubtitleGapFastForwardSpeedIfNeeded() {
        guard let baseSpeed = subtitleGapFastForwardBaseSpeed else { return }
        subtitleGapFastForwardBaseSpeed = nil
        let normalizedBaseSpeed = VideoPlaybackSpeed.normalized(baseSpeed)
        if abs(snapshot.speed - normalizedBaseSpeed) >= 0.001 {
            engine.setSpeed(normalizedBaseSpeed)
        }
    }
}
#endif
