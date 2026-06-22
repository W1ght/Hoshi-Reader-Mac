# Video Traffic Lights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move top-left Video actions into layout A, synchronize native traffic lights with playback chrome, and restore native full-screen support.

**Architecture:** Keep the system-owned titlebar transparent and unobstructed, while a window-scoped controller synchronizes its title and traffic lights with the playback chrome. Give the singleton Video scene a principal window-manager role and route custom full-screen actions to the attached Video window. Move Mining History and Open Video into one widened bottom control bar; do not create custom traffic lights or modify Reader windows.

**Tech Stack:** SwiftUI macOS scenes, native window toolbar placement, focused source-contract tests.

---

### Task 1: Restore system window chrome

**Files:**
- Modify: `script/test_video_window_contract.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `NativeMac/HoshiNativeMacApp.swift`
- Modify: `docs/CHANGELOG.md`

- [ ] **Step 1: Write the failing contract**

Require `VideoWindowSceneRoot` to avoid `.toolbar(.hidden, for: .windowToolbar)` and to use a transparent window-toolbar background.

- [ ] **Step 2: Run the focused contracts and confirm failure**

Run:

```bash
swift script/test_video_window_contract.swift
swift script/test_video_liquid_glass_contract.swift
```

Expected: failure because the Video root still hides the complete titlebar.

- [ ] **Step 3: Implement the minimum scene change**

Replace complete window-toolbar hiding with a hidden toolbar background while leaving the toolbar and standard window controls visible.

- [ ] **Step 4: Run focused and variant validation**

Run:

```bash
swift script/test_video_window_contract.swift
swift script/test_video_liquid_glass_contract.swift
./script/verify_video_variant_contract.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --video --verify
```

Expected: all commands exit successfully, and the exact DerivedData Video window exposes close, minimize, and zoom buttons.

- [ ] **Step 5: Record the user-visible fix**

Add one Unreleased Changelog entry describing restored native Video window controls. Do not commit or push without explicit user authorization.
