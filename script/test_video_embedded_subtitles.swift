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

        controller.beginEmbeddedTrack(trackID: 4, sourceURL: videoURL)
        expect(
            controller.transcript.rows.isEmpty,
            "switching embedded tracks should immediately clear the previous transcript"
        )
        expect(
            controller.isTranscriptLoading,
            "switching embedded tracks should expose a transcript loading state"
        )
        controller.replaceEmbeddedTranscript(
            [
                VideoEmbeddedSubtitleCue(
                    id: "track-4-1",
                    startTime: 25,
                    endTime: 28.74,
                    text: "今度の中間テスト"
                )
            ],
            sourceURL: videoURL,
            trackID: 4
        )
        expect(
            controller.transcript.rows.map(\.primaryText) == ["今度の中間テスト"],
            "a complete embedded extraction should replace the transcript for the selected track"
        )
        expect(
            !controller.isTranscriptLoading,
            "a complete embedded extraction should finish the loading state"
        )
        controller.replaceEmbeddedTranscript(
            [
                VideoEmbeddedSubtitleCue(
                    id: "stale-track",
                    startTime: 1,
                    endTime: 2,
                    text: "旧轨道"
                )
            ],
            sourceURL: videoURL,
            trackID: 3
        )
        expect(
            controller.transcript.rows.map(\.primaryText) == ["今度の中間テスト"],
            "a stale extraction must not overwrite the newly selected subtitle track"
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
