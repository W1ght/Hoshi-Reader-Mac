# Video Subtitle and Controls Stability Implementation Plan

> **Superseded in part:** The fixed-point subtitle-position work in this historical plan was replaced by [Video Subtitle Relative Position Design](../specs/2026-07-14-video-subtitle-relative-position-design.md) and [its implementation plan](2026-07-14-video-subtitle-relative-position.md). The control-layout, button-style, speed-panel, and fitted-viewport portions remain valid history.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep subtitle placement relative to the fitted video picture, keep Compact Bottom controls attached to the player-surface bottom, remove the play/speed button backgrounds, and dismiss the speed panel from a canvas click. The final relative-position behavior is defined by the superseding documents above.

**Architecture:** Keep the existing `VideoPlayerScreen` and `VideoControlsView` pipeline. Publish libmpv's actual `osd-dimensions` video margins through the playback snapshot, derive one fitted viewport with the existing effective video ratio as a loading fallback, frame the subtitle overlay inside that viewport, make player-surface state own speed-panel presentation, and isolate draggable offsets to the Floating layout so Compact Bottom has no mutable position. The final subtitle control and persistence policy use the superseding normalized relative-position design. Do not add AppKit event monitors, screen-specific constants, or full-screen-specific layout branches.

**Tech Stack:** Swift 6, SwiftUI on macOS 26+, AppKit-owned Video window, source contract tests executed with `swift`, Xcode Light/Video schemes.

## Global Constraints

- Work only in `/Users/wight/Documents/code/Hoshi-Reader/.worktrees/video-window-aspect-ratio` on `codex/video-window-aspect-ratio`.
- Preserve the uncommitted live-aspect-ratio implementation already in this worktree.
- Keep Light free of Video/libmpv linkage and runtime lookup.
- Do not install persistent `NSWindow.contentAspectRatio` or mutate window frames during native full-screen transitions.
- Preserve the legacy `videoSubtitleVerticalPosition` key as migration input; persist the normalized value separately and do not delete user data.
- Measure subtitle vertical position from the fitted video picture, not from the outer player or display edge.
- Derive viewport geometry primarily from libmpv's current OSD-to-video margins and use the effective media/override/rotation ratio only as a fallback; do not hardcode a display size, backing scale, or letterbox inset.
- Keep Compact Bottom and Floating controls positioned against the outer player surface; do not move them into the fitted video viewport.
- Do not change playback actions, shortcut semantics, subtitle timing, lookup, mining, or study-sidebar behavior.
- Do not commit, push, tag, release, or delete user data without explicit user authorization.
- Use `apply_patch` for every manual source or documentation edit.

---

## File Map

- `Core/UserConfig.swift`: owns subtitle vertical-position persistence and load behavior; its final normalized policy is specified by the superseding plan.
- `Features/Video/Playback/HSMpvClient.h` and `.mm`: observe libmpv `osd-dimensions` and publish its surface size plus video margins.
- `Features/Video/Playback/PlaybackEngine.swift` and `MpvPlayerEngine.swift`: carry render geometry through the existing playback snapshot boundary.
- `Features/Settings/VideoSettingsView.swift`: exposes subtitle vertical position in global Video settings.
- `Features/Video/VideoInspectorView.swift`: exposes subtitle vertical position in the in-player inspector.
- `Features/Video/VideoWindowChromeController.swift`: keeps the pure effective-ratio helpers and adds mpv-margin-first viewport geometry without changing AppKit window lifecycle behavior.
- `Features/Video/Subtitles/SubtitleOverlayView.swift`: renders subtitle position without presentation-specific compensation.
- `Features/Video/VideoPlayerScreen.swift`: frames subtitles inside the fitted video viewport and owns speed-panel presentation, canvas dismissal, and playback-control placement.
- `Features/Video/VideoControlsView.swift`: binds speed-panel state and renders the play/speed buttons without persistent backgrounds.
- `script/test_video_settings_contract.swift`: locks the subtitle position policy and shared UI wiring.
- `script/test_video_window_aspect_layout.swift`: executes pure geometry coverage for scaled mpv margins, equal-aspect, letterbox, pillarbox, invalid-geometry fallback, media ratio, override, and rotation cases.
- `script/test_video_player_interactions_contract.swift`: locks the mpv-to-snapshot-to-subtitle viewport wiring and existing popup coordinate space.
- `script/test_video_liquid_glass_contract.swift`: locks Compact Bottom placement, Floating drag behavior, plain play/speed buttons, and speed-panel dismissal.
- `docs/CHANGELOG.md`, `docs/TODO.md`, `docs/VIDEO_LEARNING_ARCHITECTURE.md`: update the minimal user-visible and architectural truth sources.

---

### Task 1: Subtitle Vertical Position (Superseded)

This task recorded the intermediate fixed-point implementation. It is no longer authoritative; use the linked 2026-07-14 relative-position design and plan for the final `0...1` policy, icon-only sliders, legacy migration, measured subtitle-stack placement, tests, and implementation.

**Files:**
- Modify: `script/test_video_settings_contract.swift`
- Modify: `Core/UserConfig.swift`
- Modify: `Features/Settings/VideoSettingsView.swift`
- Modify: `Features/Video/VideoInspectorView.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayView.swift`

**Interfaces:**
- Produces: an intermediate range and clamping policy, now superseded.
- Consumes: the existing `videoSubtitleVerticalPosition` preference key and binding.

- [ ] **Step 1: Change the settings contract to describe the new behavior**

The original intermediate checks covered a fixed numeric range, shared clamping, both UI consumers, and direct rendering. They are retained below only as historical execution context and must not be used for the final behavior:

```swift
require(
    userConfig,
    contains: "static let videoSubtitleVerticalPositionRange: ClosedRange<Double>",
    "historical fixed-position range should be centralized"
)
require(
    userConfig,
    contains: "static func clampedVideoSubtitleVerticalPosition(_ value: Double) -> Double",
    "video subtitle vertical position should expose shared clamping"
)
require(
    userConfig,
    contains: "Self.clampedVideoSubtitleVerticalPosition(videoSubtitleVerticalPosition)",
    "video subtitle vertical position assignment should use shared clamping"
)
require(
    settings,
    contains: "in: UserConfig.videoSubtitleVerticalPositionRange",
    "Video settings should use the shared subtitle vertical position range"
)
require(
    inspector,
    contains: "range: UserConfig.videoSubtitleVerticalPositionRange",
    "Video inspector should use the shared subtitle vertical position range"
)
require(
    subtitleOverlay,
    contains: "CGFloat(UserConfig.clampedVideoSubtitleVerticalPosition(verticalPosition))",
    "historical subtitle overlay should map its configured offset directly"
)
require(
    !subtitleOverlay.contains("* 3"),
    "subtitle overlay should not multiply the configured point offset"
)
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
swift script/test_video_settings_contract.swift
```

Expected at the time: exit 1 with the first new range/clamping failure because production still contained the former narrower range and `* 3`.

- [ ] **Step 3: Add the shared range and clamp in `UserConfig`**

Add these members near the Video subtitle preferences:

```swift
static let videoSubtitleVerticalPositionRange: ClosedRange<Double> = /* historical fixed range */

static func clampedVideoSubtitleVerticalPosition(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(
        max(value, videoSubtitleVerticalPositionRange.lowerBound),
        videoSubtitleVerticalPositionRange.upperBound
    )
}
```

Change the property observer so the in-memory value and persisted value are both clamped:

```swift
var videoSubtitleVerticalPosition: Double {
    didSet {
        let clampedValue = Self.clampedVideoSubtitleVerticalPosition(videoSubtitleVerticalPosition)
        if clampedValue != videoSubtitleVerticalPosition {
            videoSubtitleVerticalPosition = clampedValue
        }
        Self.defaults.set(clampedValue, forKey: "videoSubtitleVerticalPosition")
    }
}
```

Load the saved preference through the same helper:

```swift
self.videoSubtitleVerticalPosition = Self.clampedVideoSubtitleVerticalPosition(
    defaults.object(forKey: "videoSubtitleVerticalPosition") as? Double ?? 0
)
```

- [ ] **Step 4: Make both sliders and the overlay consume the shared policy**

Use the range directly in Settings:

```swift
Slider(
    value: $userConfig.videoSubtitleVerticalPosition,
    in: UserConfig.videoSubtitleVerticalPositionRange,
    step: 1
)
```

Use the same range in the inspector:

```swift
subtitleAppearanceSlider(
    title: "Vertical Position",
    value: "\(Int(userConfig.videoSubtitleVerticalPosition))",
    binding: subtitleVerticalPosition,
    range: UserConfig.videoSubtitleVerticalPositionRange,
    step: 1
)
```

Map it directly to points in the overlay:

```swift
private var verticalPositionOffset: CGFloat {
    CGFloat(UserConfig.clampedVideoSubtitleVerticalPosition(verticalPosition))
}
```

- [ ] **Step 5: Run the focused contract and verify GREEN**

Run:

```bash
swift script/test_video_settings_contract.swift
```

Expected: `Video settings contract tests passed` and exit 0.

---

### Task 2: Align Subtitles to libmpv's Effective Video Viewport

**Files:**
- Modify: `script/test_video_window_aspect_layout.swift`
- Modify: `script/test_video_player_interactions_contract.swift`
- Modify: `Features/Video/Playback/HSMpvClient.h`
- Modify: `Features/Video/Playback/HSMpvClient.mm`
- Modify: `Features/Video/Playback/PlaybackEngine.swift`
- Modify: `Features/Video/Playback/MpvPlayerEngine.swift`
- Modify: `Features/Video/VideoWindowChromeController.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

**Interfaces:**
- Consumes: libmpv `osd-dimensions` with `w`, `h`, `mt`, `mb`, `ml`, and `mr`.
- Produces: `VideoRenderGeometry` in `VideoPlaybackSnapshot` and `VideoWindowAspectLayout.videoViewport(in:renderGeometry:aspectRatio:) -> CGRect`.
- Preserves: `SubtitleOverlayView`'s `video-player` coordinate-space lookup rectangles and the outer player-surface placement of both control layouts.

- [ ] **Step 1: Add failing pure viewport geometry cases**

Add cases covering scaled symmetric and asymmetric mpv margins, invalid mpv geometry falling back to the existing effective aspect ratio, equal-aspect surfaces, pillarboxing, and missing/invalid fallback data. The primary full-screen case should use the Retina geometry observed from a 1470×923-point surface:

```swift
let fullScreenViewport = VideoWindowAspectLayout.videoViewport(
    in: CGSize(width: 1470, height: 923),
    renderGeometry: VideoRenderGeometry(
        osdSize: CGSize(width: 2940, height: 1846),
        topMargin: 96,
        bottomMargin: 96,
        leftMargin: 0,
        rightMargin: 0
    ),
    aspectRatio: 16.0 / 9.0
)
```

- [ ] **Step 2: Compile the pure test and run the source contract to verify RED**

Use the command below plus `swift script/test_video_player_interactions_contract.swift`. Expected: the pure test cannot find `VideoRenderGeometry`/the new viewport argument, and the source contract fails because no mpv geometry path exists.

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-viewport-red-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-viewport-red-swift-module-cache \
xcrun swiftc -D HOSHI_VIDEO -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout_red
```

- [ ] **Step 3: Publish libmpv render geometry through the playback boundary**

Observe `osd-dimensions` as an `MPV_FORMAT_NODE` in `HSMpvClient`, parse all six required values with the existing numeric node helper, and dispatch a dedicated geometry handler to the main queue under the current load-generation guard. Add `VideoRenderGeometry` to `VideoPlaybackSnapshot`, preserve it across normal state emissions, clear it on a new load, and update it from `MpvPlayerEngine.videoGeometryHandler`.

- [ ] **Step 4: Add mpv-margin-first pure viewport fitting**

Scale mpv OSD units independently into the current SwiftUI container. Reject non-finite, non-positive, negative-margin, or over-constrained geometry. When rejected or unavailable, use the existing effective media/override/rotation aspect-fit calculation; if that is also unavailable, return the full surface.

- [ ] **Step 5: Frame the subtitle overlay inside the fitted picture**

Derive the viewport from the current playback snapshot, then retain the existing frame/position placement and `video-player` coordinate space:

```swift
let subtitleViewport = VideoWindowAspectLayout.videoViewport(
    in: geometry.size,
    renderGeometry: model.snapshot.videoRenderGeometry,
    aspectRatio: videoWindowAspectRatio
)
```

Do not clip the overlay: negative user offsets retain their existing ability to move below the picture edge, but their origin is now the fitted picture rather than the display.

- [ ] **Step 6: Run the viewport and interaction tests together**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-viewport-final-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-viewport-final-swift-module-cache \
xcrun swiftc -D HOSHI_VIDEO \
  -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout_final && \
  /tmp/test_video_window_aspect_layout_final
swift script/test_video_player_interactions_contract.swift
```

Expected: both tests print their passed messages and exit 0.

---

### Task 3: Anchor Compact Bottom and Isolate Floating Drag State

**Files:**
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

**Interfaces:**
- Consumes: `UserConfig.videoControlBarLayout` with `.floating` and `.compactBottom`.
- Produces: `playbackChromeCurrentOffset(in:)` returning `.zero` for Compact Bottom.
- Preserves: Floating `onDragChanged`, `onDragEnded`, and `clampedPlaybackChromeOffset` behavior.

- [ ] **Step 1: Add failing Compact Bottom isolation assertions**

Extend the control-placement contract with:

```swift
require(
    screen.contains("switch userConfig.videoControlBarLayout")
        && screen.contains("case .compactBottom:\n            .zero")
        && screen.contains("case .floating:\n            clampedPlaybackChromeOffset("),
    "Compact Bottom should ignore draggable playback chrome offsets while Floating remains clamped"
)
require(
    screen.contains("if layout == .compactBottom {")
        && screen.contains("playbackChromeStoredOffset = .zero")
        && screen.contains("playbackChromeDragOffset = .zero"),
    "switching to Compact Bottom should clear stale Floating drag offsets"
)
```

Keep the existing assertions that `controlDragSurface` is attached only to `floatingControls`.

- [ ] **Step 2: Run the Liquid Glass contract and verify RED**

Run:

```bash
swift script/test_video_liquid_glass_contract.swift
```

Expected: exit 1 at the new Compact Bottom offset assertion because both layouts still consume shared drag offsets.

- [ ] **Step 3: Return zero offset for Compact Bottom**

Replace `playbackChromeCurrentOffset(in:)` with:

```swift
private func playbackChromeCurrentOffset(in size: CGSize) -> CGSize {
    switch userConfig.videoControlBarLayout {
    case .floating:
        clampedPlaybackChromeOffset(
            CGSize(
                width: playbackChromeStoredOffset.width + playbackChromeDragOffset.width,
                height: playbackChromeStoredOffset.height + playbackChromeDragOffset.height
            ),
            in: size
        )
    case .compactBottom:
        .zero
    }
}
```

- [ ] **Step 4: Clear stale offsets when Compact Bottom becomes active**

Replace the layout-change handler with:

```swift
.onChange(of: userConfig.videoControlBarLayout) { _, layout in
    if layout == .compactBottom {
        playbackChromeStoredOffset = .zero
    } else {
        playbackChromeStoredOffset = clampedPlaybackChromeOffset(
            playbackChromeStoredOffset,
            in: geometry.size
        )
    }
    playbackChromeDragOffset = .zero
}
```

In the geometry-size handler, clear both offsets when Compact Bottom is active; otherwise retain existing Floating clamping:

```swift
.onChange(of: geometry.size) { _, size in
    if userConfig.videoControlBarLayout == .compactBottom {
        playbackChromeStoredOffset = .zero
    } else {
        playbackChromeStoredOffset = clampedPlaybackChromeOffset(
            playbackChromeStoredOffset,
            in: size
        )
    }
    playbackChromeDragOffset = .zero
}
```

- [ ] **Step 5: Run the focused interaction contracts and verify GREEN**

Run:

```bash
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_player_interactions_contract.swift
```

Expected: both print their passed messages and exit 0.

---

### Task 4: Simplify Play/Speed Buttons and Dismiss the Speed Panel from the Canvas

**Files:**
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `Features/Video/VideoControlsView.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

**Interfaces:**
- Produces: `VideoControlsView.@Binding var isSpeedPanelVisible: Bool`.
- Consumes: `VideoPlayerScreen.@State private var isSpeedPanelVisible = false`.
- Preserves: existing speed presets, slider, numeric input, speed action, auto-hide, and accessibility labels.

- [ ] **Step 1: Replace the old local-state assertion and add failing presentation/style assertions**

Update the speed-panel contract to require a binding instead of internal state, then add:

```swift
require(
    controls.contains("@Binding var isSpeedPanelVisible: Bool")
        && !controls.contains("@State private var isSpeedPanelVisible = false")
        && screen.contains("@State private var isSpeedPanelVisible = false")
        && screen.contains("isSpeedPanelVisible: $isSpeedPanelVisible"),
    "the player surface should own speed panel presentation"
)
require(
    screen.contains("private var shouldShowVideoDismissLayer: Bool")
        && screen.contains("hasActiveVideoPopup || isInspectorVisible || isSpeedPanelVisible")
        && screen.contains("isSpeedPanelVisible = false")
        && screen.contains("|| isSpeedPanelVisible"),
    "a canvas click should dismiss the speed panel while the panel keeps playback chrome visible"
)
require(
    !controls.contains(".glassEffect(.regular.interactive(), in: Circle())")
        && controls.contains("private struct VideoPlaybackButtonStyle")
        && controls.contains("treatment.iconPressedFill(isPressed: configuration.isPressed)"),
    "the play button should use pressed feedback without a glass circle"
)
require(
    controls.contains("private struct VideoSpeedControlButtonStyle")
        && !controls.contains("func speedFill(isSelected:")
        && !controls.contains("func speedStrokeOpacity(isSelected:"),
    "the speed button should not draw a persistent fill or stroke"
)
```

- [ ] **Step 2: Run the Liquid Glass contract and verify RED**

Run:

```bash
swift script/test_video_liquid_glass_contract.swift
```

Expected: exit 1 because speed-panel visibility is still local and the play button still applies a glass circle.

- [ ] **Step 3: Lift speed-panel state to `VideoPlayerScreen`**

Add parent state near the other overlay state:

```swift
@State private var isSpeedPanelVisible = false
```

Replace the child state declaration with:

```swift
@Binding var isSpeedPanelVisible: Bool
```

Pass it into the control view:

```swift
isSpeedPanelVisible: $isSpeedPanelVisible,
```

Keep the existing speed-button toggle and panel rendering unchanged; they now read and write the binding.

- [ ] **Step 4: Integrate the speed panel with canvas dismissal and chrome visibility**

Extend the existing derived states:

```swift
private var shouldShowPlaybackChrome: Bool {
    model.currentURL == nil
        || (
            isPointerInsidePlayerSurface
                && (
                    isPlaybackChromeVisible
                        || hasActiveVideoPopup
                        || isInspectorVisible
                        || isMiningHistoryVisible
                        || isSpeedPanelVisible
                )
        )
}

private var shouldShowVideoDismissLayer: Bool {
    hasActiveVideoPopup || isInspectorVisible || isSpeedPanelVisible
}
```

Close it from the existing canvas dismissal function without changing popup/inspector semantics:

```swift
private func dismissVideoOverlaysFromCanvas() {
    dismissVideoPopupsIfNeeded()
    if isSpeedPanelVisible {
        withAnimation(.smooth(duration: 0.16)) {
            isSpeedPanelVisible = false
        }
    }
    if isInspectorVisible {
        videoScreenLog.info("Closing video inspector from canvas tap")
        isInspectorVisible = false
    }
}
```

- [ ] **Step 5: Remove persistent play and speed button backgrounds**

Change the play style body to a transparent default with pressed feedback:

```swift
func makeBody(configuration: Configuration) -> some View {
    configuration.label
        .foregroundStyle(treatment.foregroundStyle(isEnabled: isEnabled))
        .background {
            Circle().fill(treatment.iconPressedFill(isPressed: configuration.isPressed))
        }
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .contentShape(Circle())
}
```

Remove `speedFill` and `speedStrokeOpacity` from `VideoControlTreatment`. Remove the `isSelected` parameter from `VideoSpeedControlButtonStyle`, update its call site, and render only pressed feedback:

```swift
private struct VideoSpeedControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let treatment: VideoControlTreatment

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(treatment.foregroundStyle(isEnabled: isEnabled))
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(treatment.iconPressedFill(isPressed: configuration.isPressed))
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
```

The call site becomes:

```swift
.buttonStyle(VideoSpeedControlButtonStyle(treatment: controlTreatment))
```

- [ ] **Step 6: Run the focused contracts and verify GREEN**

Run:

```bash
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_player_interactions_contract.swift
swift script/test_video_settings_contract.swift
```

Expected: all three print their passed messages and exit 0.

---

### Task 5: Update Truth Sources and Run Full Verification

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Verify: all source/test files changed in Tasks 1-3 plus the existing aspect-ratio changes.

**Interfaces:**
- Consumes: the final behavior established by Tasks 1-3.
- Produces: current, concise user-visible and architecture documentation.

- [ ] **Step 1: Update the user-visible changelog**

Add matching Chinese and English entries stating that Video subtitle placement remains consistent relative to the visible picture between windowed and full-screen playback, Compact Bottom stays attached to the bottom, the play/speed buttons are visually lighter, and clicking the video dismisses the speed panel. The final changelog wording must follow the superseding relative-position design.

- [ ] **Step 2: Update TODO and architecture truth sources**

In `docs/TODO.md`, extend the current Video control/subtitle state without adding an execution log. In `docs/VIDEO_LEARNING_ARCHITECTURE.md`, document these invariants:

```text
- subtitle vertical position shares one policy across settings, inspector, persistence and rendering, with final semantics defined by the superseding relative-position design;
- windowed and full-screen subtitles use one fitted viewport derived from libmpv's current OSD-to-video margins, with current surface size plus effective media/override/rotation ratio as fallback;
- subtitle wrapping, centering and vertical offset are relative to the visible picture, while Compact Bottom and Floating remain relative to the outer player surface;
- missing or invalid media aspect data temporarily falls back to the complete video surface without screen-specific constants or full-screen branches;
- Compact Bottom has no drag offset, while Floating remains draggable;
- speed-panel presentation belongs to the player surface and canvas clicks dismiss it.
```

- [ ] **Step 3: Run all relevant source and pure contracts**

Run:

```bash
swift script/test_video_settings_contract.swift
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_player_interactions_contract.swift
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-controls-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-controls-swift-module-cache \
xcrun swiftc -D HOSHI_VIDEO \
  -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout && /tmp/test_video_window_aspect_layout
bash script/verify_native_release_contract.sh
./script/verify_video_variant_contract.sh
git diff --check
```

Expected: every command exits 0; contract scripts print their passed messages; `git diff --check` prints nothing.

- [ ] **Step 4: Build and launch the exact Light app**

Run:

```bash
./script/build_and_run.sh --instance video-controls-stability-light --verify
```

Expected: exit 0, bundle id `moe.shishamo.hoshi`, and the running executable path points inside `.build/xcode-derived-data-video-controls-stability-light/Build/Products/Debug/Niratan.app`.

- [ ] **Step 5: Build and launch the exact Video app**

Run:

```bash
./script/build_and_run.sh --video --instance video-controls-stability-video --verify
```

Expected: exit 0, bundle id `moe.shishamo.hoshi`, and the running executable path points inside `.build/xcode-derived-data-video-controls-stability-video/Build/Products/Debug-Video/Niratan.app`.

- [ ] **Step 6: Manually validate the requested UI behavior in the exact Video build**

Using only the exact app path printed by Step 5 and an existing user video without importing/deleting media:

1. Record the current subtitle-position setting, playback time, play/pause state, control layout, and sidebar state.
2. Check the top, default, and bottom positions in windowed playback; confirm the complete subtitle stack remains visible at both endpoints when it fits.
3. Enter native full screen on a display that introduces top/bottom letterboxing; confirm the subtitle retains the same picture-bottom-relative position, then exit and confirm it returns without drift.
4. Resize the window, show the pushed study sidebar, select a non-automatic aspect override, and rotate once; confirm subtitle centering, wrapping width, and picture-bottom-relative position follow the newly fitted viewport.
5. Restore automatic aspect and the original rotation before continuing.
6. Select Floating, drag it upward, then select Compact Bottom; confirm Compact Bottom snaps to and remains on the outer player bottom through resize, native full-screen entry, and exit.
7. Confirm Floating remains draggable after switching back.
8. Confirm play/pause and speed buttons have no persistent glass/fill background and retain pressed feedback.
9. Open the speed panel, use a preset/slider without accidental dismissal, then click elsewhere on the video and confirm the panel closes.
10. Restore every recorded user setting and playback state. Do not create/delete mining history or alter the media library.

- [ ] **Step 7: Review the final diff without committing**

Run:

```bash
git status --short --branch
git diff --stat
git diff --check
```

Expected: only the existing window-aspect work, this feature's production/tests/docs, and the approved spec/plan files are present; no commit is created.
