import AppKit
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

enum VideoThumbnailSuspendReason: Hashable, Sendable {
    case mining
}

actor VideoThumbnailScheduler {
    static let shared = VideoThumbnailScheduler()

    private var suspensionCount = 0
    private var events: [String] = []

    func suspend(reason: VideoThumbnailSuspendReason) {
        suspensionCount += 1
        events.append("suspend")
    }

    func resume(reason: VideoThumbnailSuspendReason) {
        suspensionCount = max(0, suspensionCount - 1)
        events.append("resume")
    }

    func isSuspended() -> Bool {
        suspensionCount > 0
    }

    func eventLog() -> [String] {
        events
    }
}

@MainActor
private final class DelayedMediaEngine: PlaybackEngine {
    var snapshot = VideoPlaybackSnapshot(duration: 30)
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onEmbeddedSubtitleCuesChanged: (([VideoEmbeddedSubtitleCue]) -> Void)?

    private let delay: Duration

    init(delay: Duration = .milliseconds(250)) {
        self.delay = delay
    }

    func load(url: URL) throws {}
    func play() {}
    func pause() {}
    func seek(to time: TimeInterval) {}
    func setSpeed(_ speed: Double) {}
    func setVolume(_ volume: Double) {}
    func setMuted(_ muted: Bool) {}
    func setSubtitleDelay(_ delay: TimeInterval) {}
    func setAudioDelay(_ delay: TimeInterval) {}
    func setLoopMode(_ mode: VideoLoopMode) {}
    func setABLoop(_ loop: VideoABLoop?) {}
    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {}
    func setRotation(_ degrees: Int) {}
    func setHardwareDecodingEnabled(_ enabled: Bool) {}
    func setDeinterlacingEnabled(_ enabled: Bool) {}
    func setHDREnhancementEnabled(_ enabled: Bool) {}
    func setVideoEqualizer(_ adjustment: VideoEqualizerAdjustment, value: Double) {}
    func seekToChapter(_ index: Int) {}
    func captureAmbientPreview(maximumDimension: Int) async -> VideoAmbientPreview? { nil }
    func loadExternalSubtitle(url: URL) {}
    func selectTrack(type: VideoTrackType, id: Int?) {}
    func shutdown() {}

    func captureScreenshot(to url: URL) async throws {
        try await Task.sleep(for: delay)
        try Data("screenshot".utf8).write(to: url)
    }

    func exportAudioClip(from start: TimeInterval, to end: TimeInterval, to url: URL) async throws {
        try await Task.sleep(for: delay)
        try Data("audio".utf8).write(to: url)
    }
}

@main
private enum VideoMiningIOCoordinationTests {
    @MainActor
    static func main() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("hoshi-video-mining-io-\(UUID().uuidString)", isDirectory: true)
        let ankiMediaDirectory = root.appendingPathComponent("collection.media", isDirectory: true)
        try? fileManager.createDirectory(at: ankiMediaDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let videoURL = root.appendingPathComponent("Episode 1.mp4")
        try? Data("video identity".utf8).write(to: videoURL)
        let cue = SubtitleCue(id: "cue-1", startTime: 3, endTime: 4, text: "星を見ています。")
        let document = SubtitleDocument(
            sourceURL: root.appendingPathComponent("Episode 1.srt"),
            format: .srt,
            cues: [cue],
            warnings: []
        )

        let start = Date()
        let context = await VideoMiningCoordinator.context(
            cue: cue,
            document: document,
            videoURL: videoURL,
            engine: DelayedMediaEngine(),
            captureScreenshot: true,
            captureAudioClip: true,
            ankiMediaDirectory: ankiMediaDirectory,
            mediaStore: VideoMiningMediaStore(fileManager: fileManager)
        )
        let elapsed = Date().timeIntervalSince(start)

        guard let screenshotFilename = context.video?.screenshotFilename,
              let audioFilename = context.video?.audioClipFilename else {
            fputs("FAIL: direct media context should expose deterministic Anki media filenames\n", stderr)
            exit(1)
        }

        let screenshotURL = ankiMediaDirectory.appendingPathComponent(screenshotFilename)
        let audioURL = ankiMediaDirectory.appendingPathComponent(audioFilename)
        expect(
            elapsed < 0.20,
            "direct media path should return context quickly instead of blocking Anki card creation"
        )
        let suspendedAfterContext = await VideoThumbnailScheduler.shared.isSuspended()
        expect(
            suspendedAfterContext,
            "video thumbnails should be suspended before direct media context returns"
        )
        expect(
            !fileManager.fileExists(atPath: screenshotURL.path(percentEncoded: false)),
            "direct screenshot generation should continue in the background"
        )
        expect(
            !fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)),
            "direct audio generation should continue in the background"
        )

        try? await Task.sleep(for: .seconds(1))
        let suspendedAfterGeneration = await VideoThumbnailScheduler.shared.isSuspended()
        let schedulerEvents = await VideoThumbnailScheduler.shared.eventLog()
        expect(
            fileManager.fileExists(atPath: screenshotURL.path(percentEncoded: false)),
            "direct screenshot file should eventually be written while thumbnails are suspended"
        )
        expect(
            fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)),
            "direct audio file should eventually be written while thumbnails are suspended"
        )
        expect(
            !suspendedAfterGeneration,
            "video thumbnails should resume after direct media generation finishes"
        )
        expect(
            schedulerEvents == ["suspend", "resume"],
            "direct media generation should use one thumbnail suspension window"
        )

        print("Video mining IO coordination tests passed")
    }
}
