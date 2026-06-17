import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoEmbeddedSubtitleTests {
    @MainActor
    static func main() async {
        let controller = VideoSubtitleController()
        let videoURL = URL(fileURLWithPath: "/tmp/Episode 1.mkv")
        controller.loadEmbedded(
            [
                VideoEmbeddedSubtitleCue(
                    id: "embedded-1",
                    startTime: 1,
                    endTime: 2.5,
                    text: "内蔵字幕"
                )
            ],
            sourceURL: videoURL
        )

        expect(
            controller.document?.format == .embedded,
            "embedded cues should use the embedded subtitle source"
        )
        controller.update(time: 1.5)
        expect(
            controller.currentCues.map(\.text) == ["内蔵字幕"],
            "embedded text cues should drive the Hoshi overlay"
        )
        controller.loadEmbedded(
            [
                VideoEmbeddedSubtitleCue(
                    id: "embedded-2",
                    startTime: 3,
                    endTime: 4.5,
                    text: "次の字幕"
                ),
                VideoEmbeddedSubtitleCue(
                    id: "embedded-2-duplicate",
                    startTime: 3,
                    endTime: 4.5,
                    text: "次の字幕"
                )
            ],
            sourceURL: videoURL
        )
        expect(
            controller.transcript.rows.map(\.primaryText) == ["内蔵字幕", "次の字幕"],
            "embedded transcript should merge rolling cue snapshots and deduplicate repeated cues"
        )
        controller.loadEmbedded([], sourceURL: videoURL)
        expect(
            controller.transcript.rows.map(\.primaryText) == ["内蔵字幕", "次の字幕"],
            "empty embedded snapshots between subtitle lines should not clear the transcript list"
        )

        let externalURL = URL(fileURLWithPath: "/tmp/external.srt")
        let external = """
        1
        00:00:01,000 --> 00:00:03,000
        外掛字幕
        """
        try! external.write(to: externalURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: externalURL)
        }
        let externalLoad = controller.load(externalURL)
        await externalLoad.value
        controller.loadEmbedded(
            [
                VideoEmbeddedSubtitleCue(
                    id: "embedded-2",
                    startTime: 1,
                    endTime: 3,
                    text: "不应覆盖"
                )
            ],
            sourceURL: videoURL
        )
        controller.update(time: 2)
        expect(
            controller.currentCues.map(\.text) == ["外掛字幕"],
            "embedded updates should not replace an active external subtitle"
        )

        print("Video embedded subtitle tests passed")
    }
}
