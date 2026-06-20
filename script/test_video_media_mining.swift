import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoMediaMiningTests {
    static func main() {
        let screenshot = URL(fileURLWithPath: "/tmp/hoshi-shot.png")
        let audio = URL(fileURLWithPath: "/tmp/hoshi-clip.m4a")
        let context = VideoMiningContext(
            fileName: "Episode 1.mkv",
            cueText: "字幕",
            cueStart: 12,
            cueEnd: 15,
            previousCueText: nil,
            nextCueText: nil,
            screenshotURL: screenshot,
            audioClipURL: audio,
            audioClipErrorMessage: nil
        )

        expect(
            context.value(for: .videoScreenshot) == screenshot.path,
            "screenshot handlebar should expose the captured file"
        )
        expect(
            context.value(for: .videoAudioClip) == audio.path,
            "audio clip handlebar should expose the captured file"
        )
        expect(
            Handlebars.videoScreenshot.isVideoSpecific,
            "screenshot handlebar should be video-specific"
        )
        expect(
            Handlebars.videoAudioClip.isVideoSpecific,
            "audio handlebar should be video-specific"
        )

        let range = VideoAudioClipRange.resolve(
            cueStart: 0.05,
            cueEnd: 4.0,
            subtitleDelay: 0.2,
            duration: 4.25
        )
        expect(abs((range?.start ?? -1) - 0.13) < 0.0001, "clip start should apply delay and padding")
        expect(abs((range?.end ?? -1) - 4.25) < 0.0001, "clip end should clamp to duration")
        expect(VideoAudioClipRange.resolve(
            cueStart: 2,
            cueEnd: 1,
            subtitleDelay: 0,
            duration: 10
        ) == nil, "invalid cue ranges should not export")
        print("Video media mining tests passed")
    }
}
