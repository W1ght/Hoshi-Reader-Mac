import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoSubtitleSelectionTests {
    static func main() {
        let sentence = "夜空の星を見ています。"
        expect(
            SubtitleSelectionResolver.lookupText(in: sentence, utf16Offset: 3, scanLength: 6) == "星を見ていま",
            "lookup text should begin at the clicked UTF-16 offset"
        )
        expect(
            SubtitleSelectionResolver.lookupText(in: sentence, utf16Offset: 100, scanLength: 6).isEmpty,
            "out-of-range clicks should be ignored"
        )
        expect(
            SubtitleSelectionResolver.lookupText(in: "  星です", utf16Offset: 0, scanLength: 6) == "星です",
            "leading whitespace should not be sent to the lookup engine"
        )
        print("Video subtitle selection tests passed")
    }
}
