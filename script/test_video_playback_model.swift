import Foundation

@MainActor
private final class FakePlaybackEngine: PlaybackEngine {
    var snapshot = VideoPlaybackSnapshot()
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)?
    var loadedURL: URL?
    var seekTarget: TimeInterval?
    var speedTarget: Double?
    var volumeTarget: Double?
    var mutedTarget: Bool?
    var subtitleDelayTarget: TimeInterval?
    var externalSubtitleURL: URL?
    var selectedTrack: (VideoTrackType, Int?)?
    var shutdownCount = 0
    var onPlaybackEnded: (() -> Void)?

    func load(url: URL) throws {
        loadedURL = url
        snapshot = VideoPlaybackSnapshot(duration: 120, isLoaded: true)
        onSnapshotChanged?(snapshot)
    }

    func play() {
        snapshot.isPlaying = true
        onSnapshotChanged?(snapshot)
    }

    func pause() {
        snapshot.isPlaying = false
        onSnapshotChanged?(snapshot)
    }

    func seek(to time: TimeInterval) {
        seekTarget = time
        snapshot.currentTime = time
        onSnapshotChanged?(snapshot)
    }

    func setSpeed(_ speed: Double) {
        speedTarget = speed
    }

    func setVolume(_ volume: Double) {
        volumeTarget = volume
    }

    func setMuted(_ muted: Bool) {
        mutedTarget = muted
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        subtitleDelayTarget = delay
    }

    func loadExternalSubtitle(url: URL) {
        externalSubtitleURL = url
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        selectedTrack = (type, id)
    }

    func shutdown() {
        shutdownCount += 1
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
private func waitForPlaylistNextURL(
    _ model: VideoPlayerViewModel,
    timeout: TimeInterval = 2
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while model.playlist.nextURL == nil, Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@main
private enum VideoPlaybackModelTests {
    @MainActor
    static func main() async throws {
        let engine = FakePlaybackEngine()
        let suiteName = "de.manhhao.hoshi.tests.video-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let historyStore = VideoPlaybackHistoryStore(defaults: defaults)
        let model = VideoPlayerViewModel(
            engine: engine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: false
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("Episode 1.mkv")
        let nextURL = directory.appendingPathComponent("Episode 2.mkv")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        FileManager.default.createFile(atPath: nextURL.path, contents: Data())

        historyStore.save(position: 42, duration: 120, for: url)

        model.open(url)
        expect(engine.loadedURL == url, "opening a video should load it in the engine")
        expect(model.snapshot.duration == 120, "engine snapshots should update the model")
        expect(engine.seekTarget == nil, "disabled history should not restore a saved position")

        engine.onPlaybackEnded?()
        expect(
            engine.loadedURL == url,
            "disabled auto-play should not advance after playback ends"
        )
        await waitForPlaylistNextURL(model)
        model.autoPlayNext = true
        engine.onPlaybackEnded?()
        expect(
            engine.loadedURL?.lastPathComponent == nextURL.lastPathComponent,
            "enabled auto-play should advance after playback ends"
        )

        model.togglePlayback()
        expect(engine.snapshot.isPlaying, "toggle should start paused playback")
        model.togglePlayback()
        expect(!engine.snapshot.isPlaying, "toggle should pause active playback")

        model.seek(to: 500)
        expect(engine.seekTarget == 120, "seek should clamp to duration")
        model.seek(to: -5)
        expect(engine.seekTarget == 0, "seek should clamp to zero")

        model.setSpeed(9)
        expect(engine.speedTarget == 3, "speed should clamp to 3x")
        model.adjustSpeed(by: -10)
        expect(engine.speedTarget == 0.25, "speed adjustment should clamp to 0.25x")

        model.setVolume(120)
        expect(engine.volumeTarget == 100, "volume should clamp to 100")
        model.toggleMuted()
        expect(engine.mutedTarget == true, "mute toggle should invert snapshot state")

        model.setSubtitleDelay(99)
        expect(engine.subtitleDelayTarget == 30, "subtitle delay should clamp to 30 seconds")
        model.adjustSubtitleDelay(by: -40)
        expect(engine.subtitleDelayTarget == -30, "subtitle delay adjustment should clamp")

        let subtitleURL = directory.appendingPathComponent("Episode 1.srt")
        FileManager.default.createFile(atPath: subtitleURL.path, contents: Data())
        model.loadExternalSubtitle(subtitleURL)
        expect(
            engine.externalSubtitleURL == subtitleURL,
            "external subtitle imports should be loaded into mpv instead of only parsed by Hoshi"
        )

        model.selectTrack(type: .audio, id: 3)
        expect(
            engine.selectedTrack?.0 == .audio && engine.selectedTrack?.1 == 3,
            "track selection should reach the engine"
        )

        expect(VideoTimeFormatter.string(from: 65) == "1:05", "short times should use m:ss")
        expect(VideoTimeFormatter.string(from: 3661) == "1:01:01", "long times should use h:mm:ss")

        model.shutdown()
        expect(engine.shutdownCount == 1, "shutdown should release the engine")
        expect(
            historyStore.position(for: nextURL) == nil,
            "disabled history should not persist playback position"
        )
        print("Video playback model tests passed")
    }
}
