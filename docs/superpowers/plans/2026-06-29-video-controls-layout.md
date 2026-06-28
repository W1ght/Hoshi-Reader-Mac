# Video Controls Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Video setting that keeps the current floating control bar as default and lets users opt into a compact YouTube-like bottom rail.

**Architecture:** Store the layout choice as a Video-only `UserConfig` enum. `VideoPlayerScreen` passes the active layout to `VideoControlsView`, which renders either the existing floating chrome or a compact bottom rail while reusing all playback actions and interaction state. Subtitle clearance and chrome frame math become layout-aware.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults, Xcode project scripts, lightweight Swift contract tests.

---

### Task 1: Add the Video Control Layout Model

**Files:**
- Create: `script/test_video_control_bar_layout.swift`
- Modify: `Core/UserConfig.swift`

- [ ] **Step 1: Write the failing contract test**

Create `script/test_video_control_bar_layout.swift` with a local assertion helper and checks for:

```swift
import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

assertEqual(VideoControlBarLayout.floating.rawValue, "floating", "floating raw value")
assertEqual(VideoControlBarLayout.compactBottom.rawValue, "compactBottom", "compact bottom raw value")
assertEqual(VideoControlBarLayout(rawValue: "floating"), .floating, "floating decode")
assertEqual(VideoControlBarLayout(rawValue: "compactBottom"), .compactBottom, "compact bottom decode")
assertEqual(VideoControlBarLayout(rawValue: "missing") ?? .floating, .floating, "unknown layout falls back to floating")

print("Video control bar layout tests passed")
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swiftc Core/UserConfig.swift script/test_video_control_bar_layout.swift -D HOSHI_VIDEO -o /tmp/test_video_control_bar_layout && /tmp/test_video_control_bar_layout
```

Expected: compile failure because `VideoControlBarLayout` is not defined.

- [ ] **Step 3: Add the production enum and persisted property**

In `Core/UserConfig.swift`, under the existing `#if HOSHI_VIDEO` model definitions, add:

```swift
enum VideoControlBarLayout: String, CaseIterable, Codable {
    case floating
    case compactBottom
}
```

Add `videoControlBarLayout` under the existing Video settings properties:

```swift
var videoControlBarLayout: VideoControlBarLayout {
    didSet {
        Self.defaults.set(videoControlBarLayout.rawValue, forKey: "videoControlBarLayout")
    }
}
```

Initialize it in `init()`:

```swift
self.videoControlBarLayout = defaults.string(forKey: "videoControlBarLayout")
    .flatMap(VideoControlBarLayout.init) ?? .floating
```

- [ ] **Step 4: Run the test and verify GREEN**

Run the same `swiftc` command. Expected: exit 0 and `Video control bar layout tests passed`.

### Task 2: Add Settings UI and Localization

**Files:**
- Modify: `Features/Settings/VideoSettingsView.swift`
- Modify: `Localizable.xcstrings`

- [ ] **Step 1: Extend Video settings contract**

Inspect `script/test_video_settings_contract.swift`, then add checks that `VideoSettingsView.swift` contains `Control Bar Layout`, `videoControlBarLayout`, `VideoControlBarLayout.allCases`, `Floating`, and `Compact Bottom`.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
swift script/test_video_settings_contract.swift
```

Expected: failure for missing control-bar layout setting.

- [ ] **Step 3: Add the segmented setting**

In `Features/Settings/VideoSettingsView.swift`, add a `NativeSettingsRow("Control Bar Layout")` inside the `Playback` section, using `NativeGlassSegmentedPicker` over `VideoControlBarLayout.allCases`.

Display labels:

```swift
switch layout {
case .floating: Text("Floating")
case .compactBottom: Text("Compact Bottom")
}
```

- [ ] **Step 4: Add localized strings**

Add Chinese and English entries in `Localizable.xcstrings` for:

```text
Control Bar Layout
Floating
Compact Bottom
```

- [ ] **Step 5: Run the contract and verify GREEN**

Run:

```bash
swift script/test_video_settings_contract.swift
```

Expected: pass.

### Task 3: Render Floating and Compact Bottom Controls

**Files:**
- Modify: `Features/Video/VideoControlsView.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayView.swift`

- [ ] **Step 1: Add a layout contract**

Create or extend a Video contract test so it scans `VideoControlsView.swift`, `VideoPlayerScreen.swift`, and `SubtitleOverlayView.swift` for:

```text
layout: VideoControlBarLayout
compactBottomControls
controlMetrics(for:
subtitleBottomClearance
```

- [ ] **Step 2: Run the layout contract and verify RED**

Run the selected contract. Expected: failure because the compact layout is not wired yet.

- [ ] **Step 3: Add layout metrics**

Add a small metrics helper in `VideoControlsView.swift` with at least:

```swift
struct VideoControlsMetrics {
    let chromeSize: CGSize
    let controlHeight: CGFloat
    let subtitleBottomClearance: CGFloat
    let popupBottomInset: CGFloat
}
```

Expose `VideoControlsView.metrics(for:)` so `VideoPlayerScreen` and `SubtitleOverlayView` can use the same clearance assumptions.

- [ ] **Step 4: Split the control body**

Keep the existing floating layout intact as `floatingControls`. Add `compactBottomControls` with:

- top progress rail
- one compact row of icon buttons
- existing speed button and speed panel
- existing profile menu
- existing timeline hover/scrub handling

- [ ] **Step 5: Wire layout through the player**

Pass `userConfig.videoControlBarLayout` into `VideoControlsView`. Use active metrics for:

- `playbackChromeSize`
- `playbackChromeBasePosition`
- `playbackChromeFrame`
- Popup `bottomInset`
- `SubtitleOverlayView` bottom clearance

- [ ] **Step 6: Run the layout contract and verify GREEN**

Run the selected contract. Expected: pass.

### Task 4: Build, Launch, and Performance Verification

**Files:**
- No production files expected unless verification exposes a bug.

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift script/test_video_control_bar_layout.swift
swift script/test_video_settings_contract.swift
swift script/test_video_player_interactions_contract.swift
```

Expected: all pass.

- [ ] **Step 2: Build Light**

Run:

```bash
./script/build_and_run.sh --verify --instance video-controls-light
```

Expected: Light build and exact-app verification pass, with no Video-only dependency leak.

- [ ] **Step 3: Build and launch Video**

Run:

```bash
./script/build_and_run.sh --video --verify --instance video-controls-video
```

Expected: Video build and exact-app verification pass.

- [ ] **Step 4: Manual UI verification**

Using the exact built Video app, verify both `Floating` and `Compact Bottom`:

- playback/pause/previous/next
- seek and timeline hover preview
- volume/mute
- speed popover
- mining history/profile/mine subtitle/inspector/full screen
- subtitle clearance
- auto-hide and reveal on pointer movement

- [ ] **Step 5: Performance sanity check**

While Video is running, inspect process CPU/memory briefly during playback and while moving the pointer over controls. The new compact layout must not introduce polling, repeated preview generation, or visible stutter beyond the existing timeline preview behavior.

Run a lightweight sample if needed:

```bash
ps -o pid,%cpu,%mem,rss,command -p "$(pgrep -f 'Hoshi Reader.*Contents/MacOS/Hoshi Reader' | head -1)"
```

Expected: no runaway CPU or memory growth from idle controls.

### Notes

- Do not commit, push, tag, or release unless the user explicitly asks.
- If a verification fails repeatedly, stop and report the smallest useful blocker.
