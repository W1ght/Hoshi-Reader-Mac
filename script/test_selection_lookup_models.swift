import AppKit
import CoreGraphics
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum SelectionLookupModelTests {
    static func main() {
        expect(
            SelectionTextValidator.validate("  星を見る\n") == .success(SelectionSnapshot(text: "星を見る")),
            "selection text should trim surrounding whitespace"
        )
        expect(
            SelectionTextValidator.validate("  \n") == .failure(.noSelection),
            "blank selection text should report no selection"
        )
        expect(
            SelectionTextValidator.validate(nil) == .failure(.unsupported),
            "missing selected-text attributes should report unsupported"
        )
        expect(
            SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: .unsupported),
            "unsupported accessibility selection should allow copy-shortcut fallback"
        )
        expect(
            SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: .readFailed),
            "failed accessibility reads should allow copy-shortcut fallback"
        )
        expect(
            SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: .noSelection),
            "empty accessibility selection should allow copy-shortcut fallback for non-editable surfaces"
        )
        expect(
            !SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: .permissionRequired),
            "missing accessibility permission should not synthesize a copy shortcut"
        )

        let pasteboardName = NSPasteboard.Name("moe.shishamo.hoshi.selection-lookup-test")
        let pasteboard = NSPasteboard(name: pasteboardName)
        pasteboard.clearContents()
        let originalItem = NSPasteboardItem()
        originalItem.setString("original clipboard", forType: .string)
        originalItem.setData(Data([0x48, 0x53]), forType: NSPasteboard.PasteboardType("moe.shishamo.hoshi.test-data"))
        pasteboard.writeObjects([originalItem])
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("temporary lookup", forType: .string)
        snapshot.restore(to: pasteboard)
        expect(
            pasteboard.string(forType: .string) == "original clipboard",
            "pasteboard snapshot should restore string data after fallback lookup"
        )
        expect(
            pasteboard.data(forType: NSPasteboard.PasteboardType("moe.shishamo.hoshi.test-data")) == Data([0x48, 0x53]),
            "pasteboard snapshot should restore non-string item data after fallback lookup"
        )

        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let size = CGSize(width: 360, height: 420)
        let gap: CGFloat = 12

        let lowerRight = QuickLookupPanelGeometry.frame(
            anchor: CGPoint(x: 1080, y: 70),
            size: size,
            visibleFrame: visible,
            gap: gap
        )
        expect(lowerRight.maxX <= visible.maxX, "panel should flip left at the right screen edge")
        expect(lowerRight.minY >= visible.minY, "panel should flip above at the bottom screen edge")

        let upperLeft = QuickLookupPanelGeometry.frame(
            anchor: CGPoint(x: 110, y: 730),
            size: size,
            visibleFrame: visible,
            gap: gap
        )
        expect(upperLeft.minX >= visible.minX, "panel should stay within a screen with a non-zero origin")
        expect(upperLeft.maxY <= visible.maxY, "panel should stay below a top-edge anchor")

        let oversized = QuickLookupPanelGeometry.frame(
            anchor: CGPoint(x: 200, y: 200),
            size: CGSize(width: 2000, height: 1200),
            visibleFrame: visible,
            gap: gap
        )
        expect(oversized == visible, "oversized panels should clamp to the usable screen")

        print("Selection lookup model tests passed")
    }
}
