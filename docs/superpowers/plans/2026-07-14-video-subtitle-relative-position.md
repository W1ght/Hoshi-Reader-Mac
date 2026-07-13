# Video Subtitle Relative Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixed-point Video subtitle offsets with an unlabeled IINA-style top-to-bottom slider whose endpoints keep a fitting subtitle stack fully inside the libmpv-reported video picture.

**Architecture:** Add a small pure `VideoSubtitlePositionPolicy` for normalized position, legacy migration, and vertical-origin math. Keep `UserConfig` as the persistence owner, use a focused SwiftUI `Layout` to measure and place the existing interactive subtitle stack, and keep `VideoPlayerScreen`'s current mpv fitted-viewport boundary unchanged.

**Tech Stack:** Swift 6, SwiftUI `Layout`, AppKit-hosted macOS 26 Video target, `UserDefaults`, libmpv viewport state, standalone Swift contract tests.

## Global Constraints

- Native macOS 26+ is the only target; do not add iOS or cross-platform paths.
- Keep Light free of Video/libmpv linkage and runtime lookup.
- The visible control contains no fraction, percentage, point count, or other numeric position label.
- `0` means fully top-aligned and `1` means fully bottom-aligned when the subtitle stack fits the picture.
- The default normalized position is exactly `0.9`.
- Use the new defaults key `videoSubtitleVerticalPositionFraction`; never delete or overwrite legacy `videoSubtitleVerticalPosition`.
- Position is independent of Floating/Compact Bottom control clearance and contains no full-screen-specific compensation.
- Preserve interactive selection, Shift-hover lookup, mask behavior, popup coordinates, mining context, and mpv fitted-viewport behavior.
- Do not commit, merge, push, release, or remove the current worktree without explicit user authorization.

## File Map

- Create `Core/VideoSubtitlePositionPolicy.swift`: pure normalization, migration, and origin math shared by Light-compatible `UserConfig` and Video layout tests.
- Create `Features/Video/Subtitles/SubtitleVerticalPositionLayout.swift`: SwiftUI layout that measures and positions one subtitle stack.
- Create `script/test_video_subtitle_position_policy.swift`: executable pure tests for normalized endpoints, migration, and geometry.
- Modify `Core/UserConfig.swift`: persist the new fraction key, migrate the legacy key once, and reset to `0.9`.
- Modify `Features/Video/Subtitles/SubtitleOverlayView.swift`: replace bottom padding with the normalized layout and remove control clearance.
- Modify `Features/Settings/VideoSettingsView.swift`: replace the numeric row with an icon-ended slider.
- Modify `Features/Video/VideoInspectorView.swift`: replace the numeric inspector row with the same icon-ended slider.
- Modify `Features/Video/VideoControlsView.swift`: remove unused subtitle-clearance metrics.
- Modify `Features/Video/VideoPlayerScreen.swift`: stop passing subtitle clearance; retain mpv viewport framing.
- Modify `script/test_video_settings_contract.swift`, `script/test_video_player_interactions_contract.swift`, and `script/test_video_liquid_glass_contract.swift`: lock normalized persistence, no-number UI, layout wiring, and clearance removal.
- Modify `docs/CHANGELOG.md`, `docs/TODO.md`, `docs/VIDEO_LEARNING_ARCHITECTURE.md`, and the superseded 2026-07-13 subtitle stability spec/plan: replace fixed-point claims with the approved relative-position behavior.

---

### Task 1: Pure Position Policy

**Files:**
- Create: `script/test_video_subtitle_position_policy.swift`
- Create: `Core/VideoSubtitlePositionPolicy.swift`

**Interfaces:**
- Produces: `VideoSubtitlePositionPolicy.range`, `.defaultPosition`, `.normalized(_:)`, `.migratedLegacyPosition(_:)`, and `.originY(viewportHeight:subtitleHeight:position:)`.
- Consumes: only `Foundation`/`CoreGraphics`; no Video or libmpv type.

- [ ] **Step 1: Write the failing pure test**

Create `script/test_video_subtitle_position_policy.swift`:

```swift
import CoreGraphics
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) < 0.0001
}

@main
private enum VideoSubtitlePositionPolicyTests {
    static func main() {
        expect(VideoSubtitlePositionPolicy.range == 0...1, "position range should be normalized")
        expect(VideoSubtitlePositionPolicy.defaultPosition == 0.9, "default should stay near the bottom")
        expect(VideoSubtitlePositionPolicy.normalized(-1) == 0, "negative position should clamp to top")
        expect(VideoSubtitlePositionPolicy.normalized(2) == 1, "oversized position should clamp to bottom")
        expect(VideoSubtitlePositionPolicy.normalized(.nan) == 0.9, "invalid position should use the default")

        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(nil) == 0.9, "missing legacy value should use default")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(.nan) == 0.9, "invalid legacy value should use default")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(0) == 0.9, "legacy neutral should use default")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(200) == 0, "legacy maximum up should map to top")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(400) == 0, "legacy values above released range should clamp to top")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(-200) == 1, "legacy maximum down should map to bottom")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(-400) == 1, "legacy values below released range should clamp to bottom")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(100) == 0.45, "legacy positive midpoint should preserve upward direction")
        expect(VideoSubtitlePositionPolicy.migratedLegacyPosition(-100) == 0.95, "legacy negative midpoint should preserve downward direction")

        expect(close(VideoSubtitlePositionPolicy.originY(viewportHeight: 800, subtitleHeight: 100, position: 0), 0), "top endpoint should use zero origin")
        expect(close(VideoSubtitlePositionPolicy.originY(viewportHeight: 800, subtitleHeight: 100, position: 0.5), 350), "middle should interpolate available travel")
        expect(close(VideoSubtitlePositionPolicy.originY(viewportHeight: 800, subtitleHeight: 100, position: 1), 700), "bottom endpoint should subtract subtitle height")
        expect(close(VideoSubtitlePositionPolicy.originY(viewportHeight: 80, subtitleHeight: 100, position: 1), 0), "oversized subtitle should remain top-aligned")
        expect(close(VideoSubtitlePositionPolicy.originY(viewportHeight: .nan, subtitleHeight: 10, position: 1), 0), "invalid geometry should safely use zero")

        print("Video subtitle position policy tests passed")
    }
}
```

- [ ] **Step 2: Run the pure test to verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-subtitle-position-red-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-subtitle-position-red-swift \
xcrun swiftc -parse-as-library \
  Core/VideoSubtitlePositionPolicy.swift \
  script/test_video_subtitle_position_policy.swift \
  -o /tmp/test_video_subtitle_position_red
```

Expected: non-zero exit because `Core/VideoSubtitlePositionPolicy.swift` does not exist.

- [ ] **Step 3: Add the minimal policy implementation**

Create `Core/VideoSubtitlePositionPolicy.swift`:

```swift
import CoreGraphics
import Foundation

enum VideoSubtitlePositionPolicy {
    static let range: ClosedRange<Double> = 0...1
    static let defaultPosition = 0.9
    private static let legacyMaximumMagnitude = 200.0

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPosition }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func migratedLegacyPosition(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return defaultPosition }
        if value >= 0 {
            let progress = min(value / legacyMaximumMagnitude, 1)
            return defaultPosition * (1 - progress)
        }
        let progress = min(-value / legacyMaximumMagnitude, 1)
        return defaultPosition + (1 - defaultPosition) * progress
    }

    static func originY(
        viewportHeight: CGFloat,
        subtitleHeight: CGFloat,
        position: Double
    ) -> CGFloat {
        guard viewportHeight.isFinite,
              subtitleHeight.isFinite,
              viewportHeight >= 0,
              subtitleHeight >= 0 else {
            return 0
        }
        let availableTravel = max(viewportHeight - subtitleHeight, 0)
        return availableTravel * CGFloat(normalized(position))
    }
}
```

- [ ] **Step 4: Run the pure test to verify GREEN**

Run the Step 2 compile command with output `/tmp/test_video_subtitle_position_green`, then run that executable.

Expected: `Video subtitle position policy tests passed` and exit 0.

---

### Task 2: UserDefaults Migration and Normalized Binding

**Files:**
- Modify: `script/test_video_settings_contract.swift`
- Modify: `Core/UserConfig.swift`

**Interfaces:**
- Consumes: `VideoSubtitlePositionPolicy` from Task 1.
- Produces: `UserConfig.videoSubtitleVerticalPosition` normalized to `0...1`, persisted under `videoSubtitleVerticalPositionFraction`.

- [ ] **Step 1: Replace fixed-point persistence assertions with failing normalized assertions**

Update `script/test_video_settings_contract.swift` to require all of the following source boundaries:

```swift
require(userConfig, contains: "VideoSubtitlePositionPolicy.normalized(videoSubtitleVerticalPosition)", "subtitle position assignment should normalize")
require(userConfig, contains: "forKey: \"videoSubtitleVerticalPositionFraction\"", "subtitle position should use the new fraction key")
require(userConfig, contains: "defaults.object(forKey: \"videoSubtitleVerticalPositionFraction\") as? Double", "subtitle position should load the new fraction key")
require(userConfig, contains: "VideoSubtitlePositionPolicy.migratedLegacyPosition(", "subtitle position should migrate the legacy key")
require(userConfig, contains: "defaults.object(forKey: \"videoSubtitleVerticalPosition\") as? Double", "migration should read but retain the legacy key")
require(userConfig, contains: "videoSubtitleVerticalPosition = VideoSubtitlePositionPolicy.defaultPosition", "appearance reset should restore the relative default")
requireCondition(!userConfig.contains("videoSubtitleVerticalPositionRange"), "fixed-point range should be removed")
requireCondition(!userConfig.contains("clampedVideoSubtitleVerticalPosition"), "fixed-point clamp should be removed")
```

- [ ] **Step 2: Run the settings contract to verify RED**

Run `swift script/test_video_settings_contract.swift`.

Expected: exit 1 at the first new normalized-position assertion.

- [ ] **Step 3: Implement normalized persistence and one-time migration**

Replace the fixed-point range/clamp/property section in `Core/UserConfig.swift` with:

```swift
var videoSubtitleVerticalPosition: Double {
    didSet {
        let normalized = VideoSubtitlePositionPolicy.normalized(videoSubtitleVerticalPosition)
        guard normalized == videoSubtitleVerticalPosition else {
            videoSubtitleVerticalPosition = normalized
            return
        }
        Self.defaults.set(normalized, forKey: "videoSubtitleVerticalPositionFraction")
    }
}
```

Replace initialization with a new-key-first migration:

```swift
let storedSubtitlePosition = defaults.object(
    forKey: "videoSubtitleVerticalPositionFraction"
) as? Double
let resolvedSubtitlePosition = storedSubtitlePosition.map(
    VideoSubtitlePositionPolicy.normalized
) ?? VideoSubtitlePositionPolicy.migratedLegacyPosition(
    defaults.object(forKey: "videoSubtitleVerticalPosition") as? Double
)
self.videoSubtitleVerticalPosition = resolvedSubtitlePosition
defaults.set(resolvedSubtitlePosition, forKey: "videoSubtitleVerticalPositionFraction")
```

In `resetVideoSubtitleAppearance()`, assign `VideoSubtitlePositionPolicy.defaultPosition`.

- [ ] **Step 4: Run pure and settings tests to verify GREEN**

Run:

```bash
/tmp/test_video_subtitle_position_green
swift script/test_video_settings_contract.swift
```

Expected: both tests pass. The old defaults key must remain present only as a migration read, never as a write/remove call.

---

### Task 3: Measured Relative Subtitle Layout

**Files:**
- Create: `Features/Video/Subtitles/SubtitleVerticalPositionLayout.swift`
- Modify: `script/test_video_player_interactions_contract.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayView.swift`
- Modify: `Features/Video/VideoControlsView.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

**Interfaces:**
- Consumes: `VideoSubtitlePositionPolicy.originY(...)` and the existing fitted subtitle viewport.
- Produces: `SubtitleVerticalPositionLayout(position:)` containing the existing subtitle stack.
- Removes: `VideoControlsMetrics.subtitleBottomClearance` and `SubtitleOverlayView.bottomClearance`.

- [ ] **Step 1: Add failing layout-wiring contracts**

Update `script/test_video_player_interactions_contract.swift` and `script/test_video_liquid_glass_contract.swift` to require:

```swift
subtitles.contains("SubtitleVerticalPositionLayout(position: verticalPosition)")
subtitles.contains("VStack(spacing: 8)")
!subtitles.contains("bottomClearance")
!subtitles.contains("verticalPositionOffset")
!subtitles.contains(".padding(.bottom")
screen.contains("verticalPosition: userConfig.videoSubtitleVerticalPosition")
!screen.contains("bottomClearance: videoControlsMetrics.subtitleBottomClearance")
!controls.contains("subtitleBottomClearance")
```

Also load `Features/Video/Subtitles/SubtitleVerticalPositionLayout.swift` in the interaction contract and require that it contains `struct SubtitleVerticalPositionLayout: Layout`, `VideoSubtitlePositionPolicy.originY(`, and `.topLeading` placement.

- [ ] **Step 2: Run interaction and Liquid Glass contracts to verify RED**

Run:

```bash
swift script/test_video_player_interactions_contract.swift
swift script/test_video_liquid_glass_contract.swift
```

Expected: both exit 1 because the old bottom-padding/clearance path still exists.

- [ ] **Step 3: Create the focused SwiftUI layout**

Create `Features/Video/Subtitles/SubtitleVerticalPositionLayout.swift`:

```swift
#if HOSHI_VIDEO
import SwiftUI

struct SubtitleVerticalPositionLayout: Layout {
    let position: Double

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let fallback = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(
            width: max(proposal.width ?? fallback.width, 0),
            height: max(proposal.height ?? fallback.height, 0)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subtitle = subviews.first else { return }
        let childProposal = ProposedViewSize(width: max(bounds.width, 0), height: nil)
        let subtitleSize = subtitle.sizeThatFits(childProposal)
        let y = VideoSubtitlePositionPolicy.originY(
            viewportHeight: bounds.height,
            subtitleHeight: subtitleSize.height,
            position: position
        )
        subtitle.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: subtitleSize.height)
        )
    }
}
#endif
```

- [ ] **Step 4: Replace bottom padding with the measured layout**

In `SubtitleOverlayView`, remove `bottomClearance`, `verticalPositionOffset`, and bottom padding. Wrap the existing `VStack` as follows while retaining its rows and horizontal padding unchanged:

```swift
SubtitleVerticalPositionLayout(position: verticalPosition) {
    VStack(spacing: 8) {
        ForEach(cues) { cue in
            SubtitleCueMaskRow(
                cue: cue,
                contextCues: contextCues,
                scanLength: scanLength,
                hoverLookupDelayMs: hoverLookupDelayMs,
                maskEnabled: maskEnabled,
                maskMode: maskMode,
                maskBlurRadius: maskBlurRadius,
                maskHiddenOpacity: maskHiddenOpacity,
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                edgeStyle: edgeStyle,
                edgeStrength: edgeStrength,
                backgroundOpacity: backgroundOpacity,
                backgroundDisabled: backgroundDisabled,
                subtitleColor: subtitleColor,
                lookupHighlightColor: lookupHighlightColor,
                lookupHighlightTextColor: lookupHighlightTextColor,
                isLookupPopupVisible: isLookupPopupVisible,
                isPlaybackPaused: isPlaybackPaused,
                onSelection: onSelection
            )
        }
    }
    .padding(.horizontal, 24)
}
```

Remove `subtitleBottomClearance` from `VideoControlsMetrics` and both metrics initializers. Stop passing `bottomClearance` from `VideoPlayerScreen`; do not alter the existing `.frame(width:height:)`, `.position(x:y:)`, or popup coordinate-space code around the overlay.

- [ ] **Step 5: Run pure, interaction, and Liquid Glass tests to verify GREEN**

Run:

```bash
/tmp/test_video_subtitle_position_green
swift script/test_video_player_interactions_contract.swift
swift script/test_video_liquid_glass_contract.swift
```

Expected: all three pass.

---

### Task 4: Unlabeled Top-to-Bottom Controls

**Files:**
- Modify: `script/test_video_settings_contract.swift`
- Modify: `Features/Settings/VideoSettingsView.swift`
- Modify: `Features/Video/VideoInspectorView.swift`

**Interfaces:**
- Consumes: `UserConfig.videoSubtitleVerticalPosition` normalized binding.
- Produces: icon-ended sliders with no numeric `Text` value in Settings or Inspector.

- [ ] **Step 1: Add failing no-number UI contracts**

Require both UI sources to contain the shared range and endpoint symbols:

```swift
"VideoSubtitlePositionPolicy.range"
"rectangle.topthird.inset.filled"
"rectangle.bottomthird.inset.filled"
```

Require Settings not to contain `value: "\(Int(userConfig.videoSubtitleVerticalPosition))"` and Inspector not to contain `value: "\(Int(userConfig.videoSubtitleVerticalPosition))"`. Require the inspector to use a dedicated `subtitlePositionSlider(` instead of passing position to the numeric `subtitleAppearanceSlider` helper.

- [ ] **Step 2: Run the settings contract to verify RED**

Run `swift script/test_video_settings_contract.swift`.

Expected: exit 1 because both surfaces still render the fixed-point number.

- [ ] **Step 3: Replace the Settings row**

In `VideoSettingsView`, replace the numeric `NativeSettingsSliderRow` with:

```swift
NativeSettingsRow("Vertical Position") {
    HStack(spacing: 10) {
        Image(systemName: "rectangle.topthird.inset.filled")
            .foregroundStyle(.secondary)
        Slider(
            value: $userConfig.videoSubtitleVerticalPosition,
            in: VideoSubtitlePositionPolicy.range
        )
        .labelsHidden()
        Image(systemName: "rectangle.bottomthird.inset.filled")
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: 280)
}
```

- [ ] **Step 4: Add the dedicated Inspector slider**

Replace the position call with `subtitlePositionSlider(title: "Vertical Position", binding: subtitleVerticalPosition)` and add:

```swift
private func subtitlePositionSlider(
    title: LocalizedStringKey,
    binding: Binding<Double>
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption)
        HStack(spacing: 8) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .foregroundStyle(.secondary)
            Slider(value: binding, in: VideoSubtitlePositionPolicy.range)
                .labelsHidden()
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .foregroundStyle(.secondary)
        }
    }
}
```

Do not add new text or apply a secondary foreground style to the whole `HStack`, because the slider must retain its normal system tint.

- [ ] **Step 5: Run settings, interaction, and pure tests to verify GREEN**

Run:

```bash
swift script/test_video_settings_contract.swift
swift script/test_video_player_interactions_contract.swift
/tmp/test_video_subtitle_position_green
```

Expected: all three pass and source scans find no numeric vertical-position presentation.

---

### Task 5: Source-of-Truth Documentation

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Modify: `docs/superpowers/specs/2026-07-13-video-subtitle-and-controls-stability-design.md`
- Modify: `docs/superpowers/plans/2026-07-13-video-subtitle-and-controls-stability.md`
- Modify: `docs/superpowers/specs/2026-07-14-video-subtitle-relative-position-design.md`

**Interfaces:**
- Documents the final visible behavior and supersedes all fixed `-200...400pt` claims.

- [ ] **Step 1: Update user-visible and architecture truth**

Replace fixed-point wording with these exact invariants:

- Vertical position is an unlabeled top-to-bottom slider relative to the fitted picture.
- A fitting subtitle stack is fully visible at both endpoints.
- Position persists as a normalized fraction and migrates the legacy point value without deleting it.
- Position does not change when switching Floating/Compact Bottom layouts.
- The mpv OSD-margin viewport remains the coordinate-space source.

Mark the 2026-07-13 fixed-point subsection as superseded by `2026-07-14-video-subtitle-relative-position-design.md`; do not retain contradictory `-200...400` or one-setting-unit-equals-one-point claims.

- [ ] **Step 2: Run documentation and source hygiene checks**

Run:

```bash
rg -n -- "-200\.\.\.400|one SwiftUI point|actual points|固定点" \
  docs/CHANGELOG.md docs/TODO.md docs/VIDEO_LEARNING_ARCHITECTURE.md \
  docs/superpowers/specs/2026-07-13-video-subtitle-and-controls-stability-design.md \
  docs/superpowers/plans/2026-07-13-video-subtitle-and-controls-stability.md
git diff --check
```

Expected: `rg` prints no stale claims and `git diff --check` prints nothing.

---

### Task 6: Full Verification and Exact-App Manual Matrix

**Files:**
- Verify only; no new implementation unless a failing check identifies a scoped regression.

**Interfaces:**
- Proves the approved behavior across pure math, source contracts, Light isolation, Video compilation, and the exact running app.

- [ ] **Step 1: Run all focused contracts**

Run:

```bash
set -euo pipefail
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-subtitle-position-final-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-subtitle-position-final-swift \
xcrun swiftc -parse-as-library \
  Core/VideoSubtitlePositionPolicy.swift \
  script/test_video_subtitle_position_policy.swift \
  -o /tmp/test_video_subtitle_position_final
/tmp/test_video_subtitle_position_final
swift script/test_video_settings_contract.swift
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_player_interactions_contract.swift
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-aspect-final-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-aspect-final-swift \
xcrun swiftc -D HOSHI_VIDEO -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout_final
/tmp/test_video_window_aspect_layout_final
bash script/verify_native_release_contract.sh
./script/verify_video_variant_contract.sh
git diff --check
```

Expected: every command exits 0; all test executables/scripts print their passed messages.

- [ ] **Step 2: Build and launch exact Light and Video products**

Run with separate DerivedData instances:

```bash
./script/build_and_run.sh --instance subtitle-relative-final-light --verify
./script/build_and_run.sh --video --instance subtitle-relative-final-video --verify
```

Expected: both exit 0, verify bundle id `moe.shishamo.hoshi`, and report the exact executable path of their own DerivedData product.

- [ ] **Step 3: Validate the exact Video app manually**

Target only the absolute Video `.app` path printed by Step 2. Using an existing local subtitle video without importing, deleting, or editing user media:

1. Pause on a wrapped subtitle.
2. Open the inspector and move the icon-ended slider to top, middle, default-like near-bottom, and bottom.
3. Confirm the entire fitting subtitle stack touches the expected picture endpoint and no number appears.
4. Enter native full screen, wait for transition completion, and repeat top and bottom.
5. Exit full screen and confirm the chosen relative position is unchanged.
6. Switch Floating/Compact Bottom and confirm the subtitle does not move.
7. Click/drag-select subtitle text at both endpoints and confirm popup anchoring remains on the selected text.

- [ ] **Step 4: Review final state without Git mutation**

Run `git status --short --branch`, inspect the focused diff, confirm no diagnostic logging remains, and report any untested physical-display, rotation, pillarbox, or multi-cue scenario. Do not stage or commit.
