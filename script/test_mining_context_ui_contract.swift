import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum MiningContextUIContractTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }

        let selector = try source("Features/Popup/MiningContextSelectionView.swift")
        let popupWebView = try source("Features/Popup/PopupWebView.swift")
        let popupScript = try source("Features/Popup/popup.js")
        let selectionScript = try source("Features/Reader/ReaderWebView/selection.js")
        let subtitleTextView = try source("Features/Video/Subtitles/InteractiveSubtitleTextView.swift")

        for label in ["Add Previous", "Remove Previous", "Add Next", "Remove Next"] {
            expect(selector.contains("\"\(label)\""), "context selector should expose \(label)")
        }
        expect(selector.contains("selection.addPrevious()"), "previous add should mutate the lower range")
        expect(selector.contains("selection.removePrevious()"), "previous rollback should mutate the lower range")
        expect(selector.contains("selection.addNext()"), "next add should mutate the upper range")
        expect(selector.contains("selection.removeNext()"), "next rollback should mutate the upper range")

        expect(popupScript.contains("createButtonSlot('context'"), "popup entries should include a context action")
        expect(popupScript.contains("prepareContextMiningAtIndex"), "context action should prepare fields without mining")
        expect(popupWebView.contains("prepareContextMining"), "WKWebView should bridge the context action")
        expect(!popupWebView.contains("sender.tag % 2"), "native popup actions should not depend on two-button tag parity")

        expect(selectionScript.contains("miningContextForSelection"), "Reader and nested Popup selection should capture sentence context")
        expect(selectionScript.contains("closest('.glossary-content')"), "nested Popup context should stay inside its definition block")
        expect(selectionScript.contains("|| document.body"), "Reader context should use the current chapter body")

        expect(subtitleTextView.contains("super.mouseDown(with: event)"), "Video subtitle dragging should use native AppKit selection")
        expect(subtitleTextView.contains("addTemporaryAttribute"), "Video lookup highlight should be independent of native text selection")
        print("Mining context UI contract tests passed")
    }
}
