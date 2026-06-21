# Shift-Hover Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore v0.5 Shift-hover lookup in native Reader and add the same continuous interaction to Video subtitles through existing click lookup paths.

**Architecture:** Native Reader re-enables the already-shared `selection.js` registration and focus bridge. Video adds a small pure hover/modifier state plus lifecycle-bound AppKit tracking; click and Shift-hover converge on one point-to-character lookup method and continue through existing Popup/Profile coordinators.

**Tech Stack:** Swift 6, SwiftUI, AppKit NSTextView/NSTrackingArea/NSEvent, WKWebView JavaScript bridge, standalone Swift contract tests.

---

### Task 1: Lock the Reader restoration contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`
- Modify: `NativeMac/NativeReaderView.swift`

- [ ] Add failing assertions requiring Native Reader to add, remove, and handle `focusRequested`, and inject:

```javascript
window.hoshiSelection.registerModifierTracking();
window.hoshiSelection.registerShiftHoverLookup(scanLength, hoverLookupDelayMs);
```

using `userConfig.scanLength` and `userConfig.desktopLookupHoverDelayMs`.
- [ ] Run the Reader regression command and confirm failure on the missing bridge/registration:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
```

- [ ] Add `focusRequested` to the Native Reader message configuration and teardown, make the requested WKWebView first responder, and register Shift-hover after modifier tracking.
- [ ] Re-run the Reader regression command and require a clean pass.

### Task 2: Add testable Video Shift-hover state

**Files:**
- Create: `Features/Video/Subtitles/VideoShiftHoverLookupState.swift`
- Create: `script/test_video_shift_hover_lookup.swift`
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj`

- [ ] Write failing tests requiring a pure state that schedules only when both Shift and a valid hover point exist, keeps scheduling while Shift-held pointer movement continues, and stops after Shift release or pointer exit. Require delay normalization to `0...1000` milliseconds.
- [ ] Run:

```bash
xcrun swiftc -parse-as-library Features/Video/Subtitles/VideoShiftHoverLookupState.swift script/test_video_shift_hover_lookup.swift -o /tmp/test_video_shift_hover_lookup && /tmp/test_video_shift_hover_lookup
```

and confirm failure because the state file/API is missing.
- [ ] Implement `VideoShiftHoverLookupState` with `setShiftPressed(_:)`, `setHoverPointAvailable(_:)`, `pointerMoved()`, `cancel()`, and `normalizedDelayMilliseconds(_:)`.
- [ ] Add the new synchronized Feature file to the target membership exception list, re-run the test, and require a clean pass.

### Task 3: Reuse Video click lookup for Shift-hover

**Files:**
- Modify: `Features/Video/Subtitles/InteractiveSubtitleTextView.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayView.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`

- [ ] Add failing contracts requiring a shared `performLookup(at:)` used by `mouseDown` and delayed hover, text tracking with `.mouseMoved`, a `.flagsChanged` local monitor that returns the event, and cleanup on detachment/deinitialization.
- [ ] Require `desktopLookupHoverDelayMs` to flow from Video screen through Subtitle overlay to the AppKit text view.
- [ ] Run `swift script/test_video_liquid_glass_contract.swift` and confirm failure on the missing behavior.
- [ ] Refactor click lookup into `performLookup(at:)`; track the last valid local pointer point and use `VideoShiftHoverLookupState` to schedule/cancel a `DispatchWorkItem`.
- [ ] Install the local modifier monitor only while attached to a key window, never consume its event, and remove it on detachment/deinitialization. Cancel pending work on Shift release and pointer exit.
- [ ] Pass the existing `desktopLookupHoverDelayMs` setting through Video screen and overlay, then run state and Video contracts.

### Task 4: Documentation and both-variant verification

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Modify: `docs/READER_REGRESSION_TESTING.md`

- [ ] Document restored Reader Shift-hover and new Video subtitle Shift-hover, both using `Mac Hover Delay` and existing Popup/Profile paths.
- [ ] Run Reader regression, Video Shift-hover state, Video subtitle-selection, Video Liquid Glass, and Video variant contracts.
- [ ] Run `./script/build_and_run.sh --verify` and `./script/build_and_run.sh --video --verify`; require exact bundle/path verification and leave Video running.
- [ ] Run `git diff --check`. Do not commit or push without separate authorization.
