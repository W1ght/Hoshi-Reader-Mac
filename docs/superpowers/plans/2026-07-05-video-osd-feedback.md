# Video OSD Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable top-left Video OSD for the approved playback, volume, subtitle, and timing feedback events.

**Architecture:** Keep the OSD inside `Features/Video/` so Light builds remain isolated from Video UI. `VideoPlayerScreen` owns one current OSD item and one dismissal task, while small helper methods format and show approved event types after model changes succeed.

**Tech Stack:** SwiftUI, Swift Observation state in `VideoPlayerScreen`, existing Video contract scripts, `Localizable.xcstrings`.

---

### Task 1: Contract Test

**Files:**
- Create: `script/test_video_osd_feedback_contract.swift`
- Modify: none

- [ ] **Step 1: Write the failing test**

Create `script/test_video_osd_feedback_contract.swift` with source checks that require:

```swift
let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let screenURL = repo.appendingPathComponent("Features/Video/VideoPlayerScreen.swift")
let osdURL = repo.appendingPathComponent("Features/Video/VideoOnScreenDisplay.swift")

func read(_ url: URL) -> String {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Missing \(url.path)")
    }
    return source
}

func require(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("Missing Video OSD contract: \(message)\n", stderr)
        exit(1)
    }
}

let screen = read(screenURL)
let osd = read(osdURL)

require(osd.contains("struct VideoOnScreenDisplayItem"), "reusable OSD item type")
require(osd.contains("struct VideoOnScreenDisplayView"), "reusable OSD SwiftUI view")
require(osd.contains("meterProgress"), "optional meter progress for ranged values")

for helper in [
    "showSpeedOSD",
    "showVolumeOSD",
    "showMuteOSD",
    "showSubtitleVisibilityOSD",
    "showSubtitleTrackOSD",
    "showSubtitleDelayOSD",
    "showAudioDelayOSD",
] {
    require(screen.contains(helper), "\(helper) helper")
}

for marker in [
    "showSpeedOSD(model.snapshot.speed)",
    "showVolumeOSD(model.snapshot.volume)",
    "showMuteOSD(isMuted: model.snapshot.isMuted)",
    "showSubtitleVisibilityOSD(isVisible: areSubtitlesVisible)",
    "showSubtitleTrackOSD(track: track)",
    "showSubtitleDelayOSD(model.snapshot.subtitleDelay)",
    "showAudioDelayOSD(model.snapshot.audioDelay)",
    "videoOSDTask?.cancel()",
] {
    require(screen.contains(marker), "wiring marker \(marker)")
}

print("Video OSD feedback contract passed")
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift script/test_video_osd_feedback_contract.swift
```

Expected before implementation: failure because `Features/Video/VideoOnScreenDisplay.swift` is missing.

### Task 2: Reusable OSD View

**Files:**
- Create: `Features/Video/VideoOnScreenDisplay.swift`
- Modify: `Localizable.xcstrings`

- [ ] **Step 1: Implement the reusable item and view**

Create a `#if HOSHI_VIDEO` Swift file with:

```swift
struct VideoOnScreenDisplayItem: Equatable, Identifiable {
    let id = UUID()
    var title: LocalizedStringKey
    var value: String
    var detail: String?
    var meterProgress: Double?
}
```

and a `VideoOnScreenDisplayView` that renders top-left white, shadowed text with no visible card background and an optional blue meter line.

- [ ] **Step 2: Add localized strings**

Add Chinese translations for the new OSD titles and state values:

```text
Speed, Volume, Muted, Unmuted, Subtitles, Subtitle Track, Subtitle Delay, Audio Delay, On, Off
```

### Task 3: Wire Approved Events

**Files:**
- Modify: `Features/Video/VideoPlayerScreen.swift`

- [ ] **Step 1: Add OSD state**

Add `@State private var videoOSD: VideoOnScreenDisplayItem?` and `@State private var videoOSDTask: Task<Void, Never>?`.

- [ ] **Step 2: Render the OSD**

Overlay `VideoOnScreenDisplayView(item:)` in `videoSurface` above the video canvas and below popups/notices, aligned to top-leading with safe padding.

- [ ] **Step 3: Add OSD helpers**

Add helpers for speed, volume, mute, subtitle visibility, subtitle track, subtitle delay, and audio delay. All helpers call one common `showVideoOSD(_:)` that cancels/restarts the dismissal task.

- [ ] **Step 4: Wire helpers after successful changes**

Call helpers from the existing control, inspector, menu-command, and shortcut closures for the approved required events only.

### Task 4: Verify

**Files:**
- Test: `script/test_video_osd_feedback_contract.swift`

- [ ] **Step 1: Run the new contract**

Run:

```bash
swift script/test_video_osd_feedback_contract.swift
```

Expected: `Video OSD feedback contract passed`.

- [ ] **Step 2: Run nearby Video contracts**

Run:

```bash
swift script/test_video_menu_commands_contract.swift
swift script/test_video_player_interactions_contract.swift
```

Expected: both pass.

- [ ] **Step 3: Build Light and Video**

Run:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --video --verify
```

Expected: both variants build and verify the exact running `moe.shishamo.hoshi` executable path. If local signing prevents launch, report that separately from compile status.
