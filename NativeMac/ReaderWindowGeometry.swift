import AppKit

enum ReaderWindowGeometry {
    static func defaultFrame(visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else {
            return NSRect(x: 0, y: 0, width: 1100, height: 760)
        }
        return visibleFrame
    }
}
