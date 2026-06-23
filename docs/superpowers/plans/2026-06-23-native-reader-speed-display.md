# Native Reader Speed Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native Reader honor its existing reading-speed and reading-time display settings.

**Architecture:** Format the current session statistics inside `NativeReaderView`, using the active book Profile for display units. Reuse the existing bottom information capsule so statistics and bottom-positioned progress remain one coherent, focus-mode-aware surface.

**Tech Stack:** SwiftUI, Observation, Swift contract scripts, native macOS build harness

---

### Task 1: Add a failing native Reader statistics-display contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`

- [x] Require a native `statisticsString` that reads both display switches and the matching session statistic values.
- [x] Require Profile-aware rate conversion and bottom information rendering.
- [x] Run the focused Reader contract and confirm failure is caused by the missing native display.

### Task 2: Restore native reading-speed and reading-time chrome

**Files:**
- Modify: `NativeMac/NativeReaderView.swift`

- [x] Add the session statistics formatter gated by Statistics and the existing display switches.
- [x] Update the bottom information overlay to show statistics and optional bottom progress in one capsule.
- [x] Run the focused Reader contract and confirm it passes.

### Task 3: Verify the combined Reader and bookshelf fixes

**Files:**
- Verify only

- [x] Run the bookshelf layout contract.
- [x] Run the focused Reader/Popup/Sasayaki regression contract.
- [x] Run `./script/build_and_run_native.sh --verify` and confirm the exact Light app identity and executable path.
- [x] Inspect the final diff and run `git diff --check`; do not commit without explicit approval.
