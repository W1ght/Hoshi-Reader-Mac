# Video Controls Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the existing Video control layouts so compact bottom controls are white and floating controls stay glass-styled but smaller.

**Architecture:** Reuse `VideoControlsView` and add small layout-aware sizing/style parameters. Contract tests lock the visual rules by scanning the Swift source for the new constants and style calls. No model, persistence, playback, subtitle, or popup behavior changes are planned.

**Tech Stack:** Swift, SwiftUI, lightweight Swift source contract tests, Hoshi build scripts.

---

### Task 1: Lock the Visual Contract

**Files:**
- Modify: `script/test_video_player_interactions_contract.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`

- [ ] **Step 1: Add failing assertions**

Add source checks for these exact production markers:

```swift
private static let floatingControlsWidth: CGFloat = 690
private static let floatingControlsHeight: CGFloat = 74
VideoGlassIconButtonStyle(treatment: controlTreatment)
VideoSpeedControlButtonStyle(isSelected: isSpeedPanelVisible, treatment: controlTreatment)
VideoPlaybackButtonStyle(treatment: controlTreatment)
.foregroundStyle(compactControlForeground)
private var controlTreatment: VideoControlTreatment
```

- [ ] **Step 2: Run focused contracts and verify RED**

Run:

```bash
swift script/test_video_player_interactions_contract.swift
swift script/test_video_liquid_glass_contract.swift
```

Expected: at least one failure naming the missing compact floating sizing or layout-aware control treatment.

### Task 2: Apply Layout-Aware Sizing and Color

**Files:**
- Modify: `Features/Video/VideoControlsView.swift`

- [ ] **Step 1: Add treatment enum and compact sizing constants**

Add a private `VideoControlTreatment` enum with `floating` and `compactBottom`. Add floating constants:

```swift
private static let floatingControlsWidth: CGFloat = 690
private static let floatingControlsHeight: CGFloat = 74
private static let floatingProgressSliderWidth: CGFloat = 300
private static let floatingProgressStripWidth: CGFloat = 410
```

- [ ] **Step 2: Make sizing use the floating constants**

Change floating metrics, frame widths, progress width, and fallback progress frame math to use the `floating*` constants. Keep compact-bottom `activeChromeWidth` full-width behavior unchanged.

- [ ] **Step 3: Make button styles treatment-aware**

Pass `controlTreatment` into icon, speed, and playback button styles. Floating returns existing `.primary` / `.tertiary`; compact bottom returns white foreground with reduced opacity when disabled.

- [ ] **Step 4: Make compact-bottom text white**

Apply `.foregroundStyle(compactControlForeground)` to compact-bottom time text and other compact-only labels. Keep floating progress time text `.secondary`.

### Task 3: Verify

**Files:**
- No production files expected unless verification exposes a bug.

- [ ] **Step 1: Run focused contracts**

Run:

```bash
swift script/test_video_control_bar_layout.swift
swift script/test_video_settings_contract.swift
swift script/test_video_player_interactions_contract.swift
swift script/test_video_liquid_glass_contract.swift
```

Expected: all pass.

- [ ] **Step 2: Build and launch Light**

Run:

```bash
./script/build_and_run.sh --verify --instance video-controls-polish-light
```

Expected: exact Debug Light app verifies with bundle id `moe.shishamo.hoshi`.

- [ ] **Step 3: Build and launch Video**

Run:

```bash
./script/build_and_run.sh --video --verify --instance video-controls-polish-video
```

Expected: exact Debug-Video app verifies with bundle id `moe.shishamo.hoshi`.

- [ ] **Step 4: Sample idle performance**

Run `ps` against the launched Video pid five times at one-second intervals.

Expected: no sustained CPU usage from the control polish.
