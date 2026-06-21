# Shift-Hover Lookup Design

## Goal

Restore the v0.5 macOS interaction where hovering text and pressing Shift performs lookup, and extend the same behavior to interactive Video subtitles without creating a second lookup path.

## Behavior

- Hovering without Shift does not open a lookup.
- Pressing Shift while the pointer is over Reader, Popup, or Video subtitle text triggers lookup after `desktopLookupHoverDelayMs`.
- Holding Shift while moving across text continuously triggers debounced lookups at the new pointer position.
- Releasing Shift, leaving interactive text, hiding the view, or destroying it cancels pending hover lookup.
- Plain click lookup remains immediate and unchanged.

The existing Dictionary setting `Mac Hover Delay` controls all three surfaces.

## Reader and Popup

`selection.js` remains the shared scan and selection implementation. Native Reader restores the missing `focusRequested` WKWebView message bridge and calls `registerShiftHoverLookup` after modifier tracking. The message bridge makes the hovered Reader WebView the first responder, matching v0.5 behavior. Popup already registers the same functions and remains unchanged.

Both click and Shift-hover deliver the existing `textSelected` payload, so Reader Popup placement, Profile context, nested lookup, highlights, Sasayaki pause, and dictionary scanning stay on their current path.

## Video

`ClickableSubtitleTextView` owns a single point-to-character lookup method used by both `mouseDown` and Shift-hover. Its tracking area records pointer movement over rendered subtitle text. A local modifier-flags observer is installed only while the text view belongs to a window; it never consumes events and is removed when detached or deinitialized.

When Shift becomes active at a valid hover point, or the pointer moves while Shift remains active, the text view schedules the shared lookup method using `desktopLookupHoverDelayMs`. It ignores points outside rendered glyph bounds and cancels stale work before scheduling another lookup.

`InteractiveSubtitleTextView` and `SubtitleOverlayView` only pass the configured delay and the existing selection callback. The resulting `SelectionData` continues through `VideoLookupCoordinator`, `PopupPresentationCoordinator`, the resolved Video Profile, and the current pause/resume behavior.

## Input Safety

- Modifier observation is scoped to the current key window and returns the original event unchanged.
- Hover lookup does not register a shortcut, write shortcut configuration, or replace Popup-first shortcut dispatch.
- Reader focus is requested only on pointer movement inside Reader content, matching the existing Popup/v0.5 bridge.
- Pending Video hover work is canceled on Shift release, pointer exit, window detachment, and deinitialization.

## Verification

- Reader contract: `focusRequested` is installed/removed/handled and Shift-hover registration uses `scanLength` plus `desktopLookupHoverDelayMs`.
- Video logic tests: modifier activation, delay clamping/cancellation, point reuse, and Shift-held pointer movement.
- Video UI contract: click and hover call the same point-to-character lookup function, and modifier monitoring is lifecycle-bound and non-consuming.
- Run Reader regression tests, Video subtitle-selection tests, Video UI/variant contracts, Light `--verify`, and Video `--video --verify`.
- Leave the exact Video build running. Manually verify actual Reader and Video hover lookup when suitable EPUB/video data can be used safely; otherwise report that gap.
