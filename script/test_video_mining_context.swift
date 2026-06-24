import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoMiningContextTests {
    static func main() {
        let video = VideoMiningContext(
            fileName: "lesson-01.mkv",
            cueText: "星を見ています。",
            cueStart: 65.25,
            cueEnd: 68.5,
            previousCueText: "夜になりました。",
            nextCueText: "きれいですね。"
        )

        expect(video.timestamp == "0:01:05.250", "timestamp should be stable and millisecond precise")
        expect(video.value(for: .videoFileName) == "lesson-01.mkv", "file name handlebar should resolve")
        expect(video.value(for: .videoSubtitle) == "星を見ています。", "subtitle handlebar should resolve")
        expect(video.value(for: .videoPreviousSubtitle) == "夜になりました。", "previous cue should resolve")
        expect(video.value(for: .videoNextSubtitle) == "きれいですね。", "next cue should resolve")

        let lapisAnimeMappings = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Lapis",
            availableFields: ["MiscInfo"],
            existing: [:],
            preset: .anime
        )
        expect(
            lapisAnimeMappings["MiscInfo"] == "{video-file-name} ({video-timestamp})",
            "anime defaults should include the video source and subtitle timestamp in MiscInfo"
        )

        let senrenAnimeMappings = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Senren",
            availableFields: ["miscInfo"],
            existing: [:],
            preset: .anime
        )
        expect(
            senrenAnimeMappings["miscInfo"] == "{video-file-name} ({video-timestamp})",
            "anime defaults should include the video source and subtitle timestamp in miscInfo"
        )

        let lapisNovelMappings = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Lapis",
            availableFields: ["MiscInfo"],
            existing: [:],
            preset: .novel
        )
        expect(
            lapisNovelMappings["MiscInfo"] == Handlebars.documentTitle.rawValue,
            "novel defaults should keep document title in MiscInfo"
        )
        print("Video mining context tests passed")
    }
}
