import AppKit
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum ReaderWindowGeometryTests {
    static func main() {
        let visibleFrame = NSRect(x: 12, y: 40, width: 1512, height: 934)
        expect(
            ReaderWindowGeometry.defaultFrame(visibleFrame: visibleFrame) == visibleFrame,
            "Reader default frame should fill the current screen visible area"
        )

        expect(
            ReaderWindowGeometry.defaultFrame(visibleFrame: nil) == NSRect(x: 0, y: 0, width: 1100, height: 760),
            "Reader default frame should keep a stable fallback when no screen is available"
        )

        print("Reader window geometry tests passed")
    }
}
