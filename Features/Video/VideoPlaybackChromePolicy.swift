#if HOSHI_VIDEO
import Foundation

struct VideoPlaybackChromeAutoHidePolicy: Equatable {
    let autoHideEnabled: Bool
    let pointerInsideControls: Bool
    let isDragging: Bool
    let isScrubbing: Bool

    func shouldScheduleHide(hasMedia: Bool) -> Bool {
        hasMedia
            && autoHideEnabled
            && !pointerInsideControls
            && !isDragging
            && !isScrubbing
    }

    func shouldHideCursor(
        hasInteractiveOverlay: Bool,
        pointerInsideSubtitle: Bool
    ) -> Bool {
        autoHideEnabled
            && !pointerInsideControls
            && !isDragging
            && !isScrubbing
            && !hasInteractiveOverlay
            && !pointerInsideSubtitle
    }

    static func normalizedDelay(_ value: TimeInterval) -> TimeInterval {
        min(max(value, 0.5), 10)
    }
}

struct VideoPlaybackChromePosition: Equatable {
    let x: Double
    let y: Double

    static let defaultPosition = VideoPlaybackChromePosition(x: 0.5, y: 1)

    static func normalized(
        centerX: Double,
        centerY: Double,
        containerWidth: Double,
        containerHeight: Double
    ) -> VideoPlaybackChromePosition {
        guard containerWidth > 0, containerHeight > 0 else {
            return defaultPosition
        }
        return VideoPlaybackChromePosition(
            x: min(max(centerX / containerWidth, 0), 1),
            y: min(max(centerY / containerHeight, 0), 1)
        )
    }

    func resolvedCenter(
        containerWidth: Double,
        containerHeight: Double,
        chromeWidth: Double,
        chromeHeight: Double,
        edgeInset: Double
    ) -> (x: Double, y: Double) {
        let halfWidth = chromeWidth / 2
        let halfHeight = chromeHeight / 2
        let minX = min(edgeInset + halfWidth, containerWidth / 2)
        let maxX = max(containerWidth - edgeInset - halfWidth, containerWidth / 2)
        let minY = min(edgeInset + halfHeight, containerHeight / 2)
        let maxY = max(containerHeight - edgeInset - halfHeight, containerHeight / 2)
        return (
            min(max(containerWidth * x, minX), maxX),
            min(max(containerHeight * y, minY), maxY)
        )
    }

    static func snappedCenterX(
        proposedCenterX: Double,
        containerWidth: Double,
        threshold: Double
    ) -> (centerX: Double, didSnap: Bool) {
        let center = containerWidth / 2
        guard abs(proposedCenterX - center) <= threshold else {
            return (proposedCenterX, false)
        }
        return (center, true)
    }
}
#endif
