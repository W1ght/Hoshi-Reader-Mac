import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoPlaybackChromePolicyTestRunner {
static func main() {
let defaultPolicy = VideoPlaybackChromeAutoHidePolicy(
    autoHideEnabled: true,
    pointerInsideControls: false,
    isDragging: false,
    isScrubbing: false
)
require(defaultPolicy.shouldScheduleHide(hasMedia: true), "loaded video should schedule auto-hide")
require(!defaultPolicy.shouldScheduleHide(hasMedia: false), "empty player should remain visible")
require(VideoPlaybackChromeAutoHidePolicy.normalizedDelay(0.1) == 0.5, "delay should clamp to 0.5 seconds")
require(VideoPlaybackChromeAutoHidePolicy.normalizedDelay(2.5) == 2.5, "default delay should remain 2.5 seconds")
require(VideoPlaybackChromeAutoHidePolicy.normalizedDelay(30) == 10, "delay should clamp to 10 seconds")

require(
    !VideoPlaybackChromeAutoHidePolicy(
        autoHideEnabled: false,
        pointerInsideControls: false,
        isDragging: false,
        isScrubbing: false
    ).shouldScheduleHide(hasMedia: true),
    "disabled auto-hide should never schedule"
)
require(
    !VideoPlaybackChromeAutoHidePolicy(
        autoHideEnabled: true,
        pointerInsideControls: true,
        isDragging: false,
        isScrubbing: false
    ).shouldScheduleHide(hasMedia: true),
    "hovering controls should pause auto-hide"
)
require(
    !VideoPlaybackChromeAutoHidePolicy(
        autoHideEnabled: true,
        pointerInsideControls: false,
        isDragging: true,
        isScrubbing: false
    ).shouldScheduleHide(hasMedia: true),
    "dragging controls should pause auto-hide"
)
require(
    !VideoPlaybackChromeAutoHidePolicy(
        autoHideEnabled: true,
        pointerInsideControls: false,
        isDragging: false,
        isScrubbing: true
    ).shouldScheduleHide(hasMedia: true),
    "scrubbing should pause auto-hide"
)

require(
    defaultPolicy.shouldHideCursor(
        hasInteractiveOverlay: false,
        pointerInsideSubtitle: false
    ),
    "pure video playback should hide the cursor with chrome"
)
require(
    !defaultPolicy.shouldHideCursor(
        hasInteractiveOverlay: true,
        pointerInsideSubtitle: false
    ),
    "interactive overlays should preserve the cursor"
)
require(
    !defaultPolicy.shouldHideCursor(
        hasInteractiveOverlay: false,
        pointerInsideSubtitle: true
    ),
    "interactive subtitles should preserve the cursor"
)

let defaultPosition = VideoPlaybackChromePosition.defaultPosition
require(defaultPosition == VideoPlaybackChromePosition(x: 0.5, y: 1), "default position should be bottom-center")

let normalized = VideoPlaybackChromePosition.normalized(
    centerX: 600,
    centerY: 700,
    containerWidth: 1200,
    containerHeight: 800
)
require(normalized == VideoPlaybackChromePosition(x: 0.5, y: 0.875), "position should persist proportionally")

let resolved = VideoPlaybackChromePosition(x: -2, y: 3).resolvedCenter(
    containerWidth: 900,
    containerHeight: 620,
    chromeWidth: 760,
    chromeHeight: 86,
    edgeInset: 16
)
require(resolved.x == 396, "x position should clamp inside narrow windows")
require(resolved.y == 561, "y position should clamp inside the window")

let snap = VideoPlaybackChromePosition.snappedCenterX(
    proposedCenterX: 603,
    containerWidth: 1200,
    threshold: 5
)
require(snap.centerX == 600 && snap.didSnap, "position should snap within five points of center")

let noSnap = VideoPlaybackChromePosition.snappedCenterX(
    proposedCenterX: 607,
    containerWidth: 1200,
    threshold: 5
)
require(noSnap.centerX == 607 && !noSnap.didSnap, "position should not snap outside the threshold")

print("Video playback chrome policy tests passed")
}
}
