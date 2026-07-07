import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoEmbeddedSubtitlePayloadTests {
    static func main() {
        expect(
            EmbeddedSubtitlePayloadParser.text(
                from: "75,1,SUB-JPO,,0,0,0,,{\\i1}今度の中間テスト{\\i0}\\Nあなたには負けませんわよ",
                codec: "ass"
            ) == "今度の中間テスト\nあなたには負けませんわよ",
            "ASS packets should drop event metadata and override tags"
        )
        expect(
            EmbeddedSubtitlePayloadParser.text(
                from: "星を見ています。",
                codec: "subrip"
            ) == "星を見ています。",
            "plain subtitle packets should retain their text"
        )
        expect(
            EmbeddedSubtitlePayloadParser.text(
                from: "星<br />空",
                codec: "subrip"
            ) == "星\n空",
            "embedded HTML line breaks should become subtitle hard line breaks before tag stripping"
        )
        expect(
            EmbeddedSubtitlePayloadParser.supportsText(codec: "ass")
                && EmbeddedSubtitlePayloadParser.supportsText(codec: "subrip")
                && !EmbeddedSubtitlePayloadParser.supportsText(codec: "hdmv_pgs_subtitle"),
            "bitmap subtitle tracks should be rejected before extraction"
        )
        print("Video embedded subtitle payload tests passed")
    }
}
