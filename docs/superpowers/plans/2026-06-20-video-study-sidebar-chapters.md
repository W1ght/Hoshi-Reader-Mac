# Video Study Sidebar Chapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Video chapter navigation into the fixed study sidebar beside Mining History and Transcript.

**Architecture:** Extend `VideoStudySidebarTab` with a chapters case and render chapter rows from the existing playback snapshot. Route row selection through the existing player chapter-seek method and remove the duplicate Inspector chapter surface.

**Tech Stack:** Swift 6, SwiftUI for native macOS, existing Video playback abstractions and contract scripts.

---

### Task 1: Lock the UI contract

**Files:**
- Modify: `script/test_video_liquid_glass_contract.swift`

- [ ] Assert that the study sidebar declares a chapters tab, accepts `[VideoChapter]`, renders an empty state and invokes `onSeekChapter`.
- [ ] Assert that `VideoInspectorView` no longer contains the Chapters section or `onSeekToChapter` callback.
- [ ] Run `swift script/test_video_liquid_glass_contract.swift` and confirm failure because chapters are still in Inspector.

### Task 2: Move chapter navigation

**Files:**
- Modify: `Features/Video/VideoMiningHistorySidebar.swift`
- Modify: `Features/Video/VideoInspectorView.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

- [ ] Add `.chapters` to `VideoStudySidebarTab` with `Chapters` and `list.bullet.rectangle` metadata.
- [ ] Pass chapters into the study sidebar and render rows with title, start time and current-chapter highlighting.
- [ ] Route row clicks to `model.seekToChapter(_:)`.
- [ ] Remove the Inspector chapter block and callback.
- [ ] Run the Liquid Glass contract and confirm it passes.

### Task 3: Localize, document and verify

**Files:**
- Modify: `Localizable.xcstrings`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Modify: `docs/TODO.md`
- Modify: `docs/CHANGELOG.md`

- [ ] Add Chinese translations for the chapter empty state if missing.
- [ ] Describe the unified three-tab study sidebar in source-of-truth docs.
- [ ] Run `swift script/test_video_liquid_glass_contract.swift`, `./script/verify_video_variant_contract.sh`, `./script/build_and_run.sh --verify`, and `./script/build_and_run.sh --video --verify`.
- [ ] Confirm the final running process uses the exact Debug-Video DerivedData executable.
