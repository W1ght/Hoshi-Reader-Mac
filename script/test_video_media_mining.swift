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
            audioClipURL: audio
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
        print("Video media mining tests passed")
    }
}
