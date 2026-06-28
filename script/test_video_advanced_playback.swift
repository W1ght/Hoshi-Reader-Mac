import Foundation

@MainActor
private final class AdvancedFakePlaybackEngine: PlaybackEngine {
    var snapshot = VideoPlaybackSnapshot()
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)?
    var audioDelayTarget: TimeInterval?
    var loopModeTarget: VideoLoopMode?
    var abLoopTarget: VideoABLoop?
    var aspectRatioTarget: VideoAspectRatio?
    var rotationTarget: Int?
    var chapterTarget: Int?
    var hardwareDecodingTarget: Bool?
    var deinterlacingTarget: Bool?
    var hdrEnhancementTarget: Bool?
    var equalizerTargets: [VideoEqualizerAdjustment: Double] = [:]

    func load(url: URL) throws {}
    func play() {}
    func pause() {}
    func seek(to time: TimeInterval) {}
    func setSpeed(_ speed: Double) {}
    func setVolume(_ volume: Double) {}
    func setMuted(_ muted: Bool) {}
    func setSubtitleDelay(_ delay: TimeInterval) {}
    func selectTrack(type: VideoTrackType, id: Int?) {}
    func setAudioDelay(_ delay: TimeInterval) { audioDelayTarget = delay }
    func setLoopMode(_ mode: VideoLoopMode) { loopModeTarget = mode }
    func setABLoop(_ loop: VideoABLoop?) { abLoopTarget = loop }
    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {
        aspectRatioTarget = aspectRatio
    }
    func setRotation(_ degrees: Int) { rotationTarget = degrees }
    func seekToChapter(_ index: Int) { chapterTarget = index }
    func setHardwareDecodingEnabled(_ enabled: Bool) { hardwareDecodingTarget = enabled }
    func setDeinterlacingEnabled(_ enabled: Bool) { deinterlacingTarget = enabled }
    func setHDREnhancementEnabled(_ enabled: Bool) { hdrEnhancementTarget = enabled }
    func setVideoEqualizer(_ adjustment: VideoEqualizerAdjustment, value: Double) {
        equalizerTargets[adjustment] = value
    }
    func shutdown() {}
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoAdvancedPlaybackTests {
    @MainActor
    static func main() {
        let engine = AdvancedFakePlaybackEngine()
        let model = VideoPlayerViewModel(
            engine: engine,
            autoPlayNext: false,
            rememberPlaybackPosition: false
        )

        model.setAudioDelay(40)
        expect(engine.audioDelayTarget == 30, "audio delay should clamp to 30 seconds")
        model.adjustAudioDelay(by: -80)
        expect(engine.audioDelayTarget == -30, "audio delay should clamp to -30 seconds")

        model.setLoopMode(.file)
        expect(engine.loopModeTarget == .file, "file loop should reach the engine")

        model.setABLoopStart()
        model.snapshot.currentTime = 12
        model.setABLoopStart()
        model.snapshot.currentTime = 18
        model.setABLoopEnd()
        expect(
            engine.abLoopTarget == VideoABLoop(start: 12, end: 18),
            "A-B loop should use the selected playback times"
        )
        model.snapshot.duration = 100
        model.setABLoopStart(at: 25)
        expect(model.pendingABLoopStart == 25, "explicit A point should be staged from transcript rows")
        model.setABLoopEnd(at: 32)
        expect(
            engine.abLoopTarget == VideoABLoop(start: 25, end: 32),
            "explicit B point should complete transcript-row A-B loops"
        )
        model.setABLoopStart(at: -5)
        expect(model.pendingABLoopStart == 0, "explicit A point should clamp to the video start")
        model.setABLoopEnd(at: 140)
        expect(
            engine.abLoopTarget == VideoABLoop(start: 0, end: 100),
            "explicit B point should clamp to the video duration"
        )
        model.clearABLoop()
        expect(engine.abLoopTarget == nil, "clearing A-B loop should reach the engine")

        model.setAspectRatio(.ratio16x9)
        expect(
            engine.aspectRatioTarget == .ratio16x9,
            "aspect ratio should reach the engine"
        )
        model.rotateClockwise()
        expect(engine.rotationTarget == 90, "rotation should advance in 90 degree steps")
        model.rotateClockwise()
        model.rotateClockwise()
        model.rotateClockwise()
        expect(engine.rotationTarget == 0, "rotation should wrap after 360 degrees")

        model.seekToChapter(2)
        expect(engine.chapterTarget == 2, "chapter selection should reach the engine")

        model.setHardwareDecodingEnabled(true)
        expect(engine.hardwareDecodingTarget == true, "hardware decoding should reach the engine")
        model.setDeinterlacingEnabled(true)
        expect(engine.deinterlacingTarget == true, "deinterlacing should reach the engine")
        model.setHDREnhancementEnabled(true)
        expect(engine.hdrEnhancementTarget == true, "HDR enhancement should reach the engine")

        model.setVideoEqualizer(.brightness, value: 140)
        expect(
            engine.equalizerTargets[.brightness] == 100,
            "brightness should clamp to mpv's maximum equalizer value"
        )
        model.setVideoEqualizer(.hue, value: -140)
        expect(
            engine.equalizerTargets[.hue] == -100,
            "hue should clamp to mpv's minimum equalizer value"
        )
        model.setVideoEqualizer(.gamma, value: .nan)
        expect(
            engine.equalizerTargets[.gamma] == 0,
            "non-finite equalizer values should reset to neutral"
        )
        print("Video advanced playback tests passed")
    }
}
