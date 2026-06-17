#if HOSHI_VIDEO
import Foundation
import Observation

@Observable
@MainActor
final class VideoPlayerViewModel {
    let engine: any PlaybackEngine
    var snapshot = VideoPlaybackSnapshot()
    var currentURL: URL?
    var errorMessage: String?
    var playlist = VideoPlaylist(urls: [], currentURL: nil)
    var autoPlayNext: Bool
    var rememberPlaybackPosition: Bool
    private(set) var pendingABLoopStart: TimeInterval?

    private var isAccessingSecurityScopedURL = false
    private let historyStore: VideoPlaybackHistoryStore
    @ObservationIgnored private var playlistScanTask: Task<Void, Never>?
    private var pendingRestorePosition: TimeInterval?
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
        saveCurrentPosition()
        stopAccessingCurrentURL()
        currentURL = url
        playlist.select(url)
        pendingRestorePosition = rememberPlaybackPosition
            ? historyStore.position(for: url)
            : nil
        lastSavedSecond = -1
        requestedRotation = 0
        isAccessingSecurityScopedURL = url.startAccessingSecurityScopedResource()
        do {
            try engine.load(url: url)
            snapshot = engine.snapshot
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            stopAccessingCurrentURL()
        }
    }

    func togglePlayback() {
        snapshot.isPlaying ? engine.pause() : engine.play()
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: min(max(time, 0), snapshot.duration))
    }

    func skip(by interval: TimeInterval) {
        seek(to: snapshot.currentTime + interval)
    }

    func setSpeed(_ speed: Double) {
        engine.setSpeed(min(max(speed, 0.25), 3))
    }

    func adjustSpeed(by delta: Double) {
        setSpeed(snapshot.speed + delta)
    }

    func setVolume(_ volume: Double) {
        engine.setVolume(min(max(volume, 0), 100))
    }

    func toggleMuted() {
        engine.setMuted(!snapshot.isMuted)
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        engine.setSubtitleDelay(min(max(delay, -30), 30))
    }

    func adjustSubtitleDelay(by delta: TimeInterval) {
        setSubtitleDelay(snapshot.subtitleDelay + delta)
    }

    func setAudioDelay(_ delay: TimeInterval) {
        engine.setAudioDelay(min(max(delay, -30), 30))
    }

    func adjustAudioDelay(by delta: TimeInterval) {
        setAudioDelay(snapshot.audioDelay + delta)
    }

    func setLoopMode(_ mode: VideoLoopMode) {
        engine.setLoopMode(mode)
    }

    func setABLoopStart() {
        pendingABLoopStart = snapshot.currentTime
    }

    func setABLoopEnd() {
        guard let start = pendingABLoopStart,
              snapshot.currentTime > start else {
            return
        }
        engine.setABLoop(VideoABLoop(start: start, end: snapshot.currentTime))
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

    func seekToChapter(_ index: Int) {
        engine.seekToChapter(index)
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        engine.selectTrack(type: type, id: id)
    }

    func loadExternalSubtitle(_ url: URL) {
        engine.loadExternalSubtitle(url: url)
    }

    func shutdown() {
        saveCurrentPosition()
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
        requestedRotation = snapshot.rotation
        if snapshot.isLoaded, let position = pendingRestorePosition {
            pendingRestorePosition = nil
            engine.seek(to: min(position, snapshot.duration))
        }
        let second = Int(snapshot.currentTime)
        if second != lastSavedSecond, second.isMultiple(of: 5) {
            lastSavedSecond = second
            saveCurrentPosition()
        }
    }

    private func saveCurrentPosition() {
        guard rememberPlaybackPosition, let currentURL else { return }
        historyStore.save(
            position: snapshot.currentTime,
            duration: snapshot.duration,
            for: currentURL
        )
    }
}
#endif
