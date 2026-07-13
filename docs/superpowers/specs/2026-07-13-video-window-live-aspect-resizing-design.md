# Video Window Live Aspect Resizing Design

## Goal

Keep the dedicated Video window stable and aspect-correct throughout user-driven window resizing. In windowed playback, every edge and corner drag must preserve the effective video aspect ratio without reintroducing the persistent AppKit aspect constraint that previously destabilized native full-screen exit.

## Product Behavior

- The effective video aspect ratio comes from mpv's display dimensions, the current aspect-ratio override, and the current 90-degree rotation, using the existing `VideoWindowAspectLayout.videoAspectRatio` path.
- When the study sidebar is hidden, the Video content width and height follow the effective video ratio during every live resize.
- When Mining History, Transcript, or Chapters is visible, the video surface remains aspect-correct and the total content width additionally reserves the current study-sidebar width.
- The inspector remains an overlay and does not participate in window-size calculations.
- Existing one-shot fitting remains responsible for media, rotation, aspect-override, and study-sidebar state changes. The new path only adds stable user-driven live resizing.
- Before media dimensions are known, resizing remains unconstrained.
- Native full screen and all native full-screen enter/exit transitions remain unconstrained. Full screen continues to use black letterboxing and AppKit's own window sizing.

## Considered Approaches

### 1. Delegate-driven proposed-size correction — selected

`VideoWindowPresenter`, which already owns the `NSWindowDelegate`, asks the window-scoped `VideoWindowChromeController` to resolve every proposed frame size received by `windowWillResize(_:to:)`. The controller returns the proposal unchanged unless the window is safely windowed and has a valid video layout policy.

This keeps all resize corrections inside the user resize transaction. It installs no persistent `NSWindow.aspectRatio` or `NSWindow.contentAspectRatio`, performs no follow-up `setFrame`, and can reuse the existing full-screen transition state as the single safety gate.

### 2. IINA-style persistent `NSWindow.aspectRatio` — rejected

IINA currently uses the frame-level `window.aspectRatio` property when aspect unlocking is disabled. Hoshi keeps a standard native title bar and can add a fixed-width study sidebar, so a constant frame ratio does not exactly describe its video content geometry. It would also leave another persistent AppKit constraint active near native full-screen transitions.

### 3. Persistent `NSWindow.contentAspectRatio` — rejected

This is the shortest way to constrain user resizing and was used by Hoshi previously. It was removed after native full-screen exit crashes and freezes in AppKit's resize snapshot path. Restoring it would violate the existing full-screen stability contract.

## Architecture

### Pure geometry

`VideoWindowAspectLayout` gains pure helpers that:

1. Convert the proposed frame size to a proposed content size using the current frame-to-content decoration delta supplied by the caller.
2. Determine whether the proposal is width-driven or height-driven by comparing its deltas with the current content size. A horizontal-edge drag changes width, a vertical-edge drag changes height, and a corner drag uses the dominant normalized delta.
3. Resolve the other dimension from `contentWidth = contentHeight * videoAspectRatio + sidebarWidth`.
4. Grow the result along the same relationship when either frame minimum dimension would otherwise be violated.
5. Convert the resolved content size back to a frame size by restoring the decoration delta.

Invalid ratios, non-finite values, non-positive dimensions, and proposals without meaningful size deltas pass through unchanged.

### Window ownership

`VideoWindowPresenter` continues to be the only `NSWindowDelegate`. It creates the `VideoWindowChromeController` before building the SwiftUI root and retains that same instance for the lifetime of the player window. `VideoWindowRootView` receives the instance instead of constructing a separate controller.

`windowWillResize(_:to:)` verifies that the sender is the current player window and forwards the proposed frame size to the controller. The presenter does not maintain an independent full-screen flag or copy the video layout policy.

### Full-screen safety

`VideoWindowChromeController` remains the only source of native full-screen state. Its proposed-size resolver returns the AppKit proposal unchanged when the state is entering, full screen, or exiting. The delegate path must never set either AppKit aspect-ratio property and must never call `setFrame`.

The existing will/did full-screen observers, repeated-toggle guard, fallback task, stable mpv render view, and one-shot windowed fitting remain unchanged. After exit completes, ordinary user resizing becomes constrained again through the delegate.

### Lifecycle

The presenter clears its retained controller together with the current window during the existing deferred close teardown. Reopening Video creates a fresh controller/window pair, preserving the current non-restoring single-player-window lifecycle.

## Testing

### Focused geometry tests

Extend `script/test_video_window_aspect_layout.swift` first and observe failures for:

- horizontal-edge resizing;
- vertical-edge resizing;
- corner resizing using the dominant normalized delta;
- standard title-bar frame decoration;
- fixed study-sidebar reservation;
- effective rotated and overridden ratios through the existing ratio resolver;
- minimum frame width and height while retaining the video relationship;
- invalid or missing layout policies passing through unchanged.

### Contract tests

Update the Video window and full-screen contracts to require:

- `VideoWindowPresenter.windowWillResize(_:to:)` forwarding to the window-scoped controller;
- one controller instance shared by the presenter and SwiftUI root;
- no nonzero persistent `window.aspectRatio` or `window.contentAspectRatio` assignment;
- no aspect or frame mutation during full-screen transitions;
- existing AppKit-owned full-screen and close teardown behavior.

### Build and runtime verification

- Run the focused aspect-layout, Video window, and full-screen contracts.
- Run all affected `script/test_video_*.swift` contracts selected by the changed boundaries.
- Build and launch the Light variant with exact bundle/executable verification to prove no Video dependency leaked.
- Build and launch the Video variant with an isolated DerivedData instance and exact bundle/executable verification.
- With a real video, manually drag all four edges and corners at several sizes, then repeat after opening the study sidebar.
- Enter and exit native full screen through the bottom control, green traffic light, `f`, and `Esc`, waiting for each AppKit transition before the next action. Confirm resizing remains constrained after returning to windowed mode and that no crash, freeze, render detachment, or stale frame occurs.

## Documentation

Update `docs/VIDEO_LEARNING_ARCHITECTURE.md` so the windowed behavior describes delegate-driven live aspect resizing rather than only one-shot fitting, while preserving the prohibition on persistent AppKit aspect constraints. Update `docs/TODO.md` only where its current validation/status text would otherwise become inaccurate. This is a user-visible Video behavior fix, so add a concise entry to `docs/CHANGELOG.md`.

## Non-Goals

- No setting to unlock the Video window aspect ratio.
- No change to full-screen letterboxing, ambient presentation, inspector layout, playback state, subtitle lookup, mining, or shortcut semantics.
- No custom `NSWindow` subclass, replacement full-screen implementation, alternate player window, or Video dependency in the Light configuration.
