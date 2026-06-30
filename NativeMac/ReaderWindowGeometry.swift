import AppKit

enum ReaderWindowGeometry {
    static let minimumSize = NSSize(width: 720, height: 520)

    static func defaultFrame(visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else {
            return NSRect(x: 0, y: 0, width: 1100, height: 760)
        }
        return visibleFrame
    }

    static func shouldUseSavedFrame(
        _ savedFrame: NSRect,
        visibleFrame: NSRect?,
        hasCompletedLegacyMigration: Bool
    ) -> Bool {
        guard isFinite(savedFrame),
              savedFrame.width >= minimumSize.width,
              savedFrame.height >= minimumSize.height else {
            return false
        }

        guard let visibleFrame else {
            return true
        }

        guard isFinite(visibleFrame),
              visibleFrame.width > 0,
              visibleFrame.height > 0,
              isMostlyVisible(savedFrame, in: visibleFrame) else {
            return false
        }

        if !hasCompletedLegacyMigration,
           isLegacyCompactFrame(savedFrame, in: visibleFrame) {
            return false
        }

        return true
    }

    private static func isLegacyCompactFrame(_ savedFrame: NSRect, in visibleFrame: NSRect) -> Bool {
        let savedArea = savedFrame.width * savedFrame.height
        let visibleArea = visibleFrame.width * visibleFrame.height
        guard visibleArea > 0 else { return false }
        return savedArea / visibleArea < 0.55
    }

    private static func isMostlyVisible(_ savedFrame: NSRect, in visibleFrame: NSRect) -> Bool {
        let intersection = savedFrame.intersection(visibleFrame)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return false
        }

        let comparableWidth = min(savedFrame.width, visibleFrame.width)
        let comparableHeight = min(savedFrame.height, visibleFrame.height)
        return intersection.width >= comparableWidth * 0.75
            && intersection.height >= comparableHeight * 0.75
    }

    private static func isFinite(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
    }
}
