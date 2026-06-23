# Sasayaki Page-Turn Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sasayaki-triggered page and chapter changes honor the Reader's `Page Turn` statistics autostart setting.

**Architecture:** Keep the autostart mode in `NativeReaderModel` and reuse one page-turn starter across manual and Sasayaki navigation. Treat a returned Sasayaki progress value or a Sasayaki chapter load as the evidence that navigation occurred; ordinary cue highlights remain side-effect free for statistics.

**Tech Stack:** SwiftUI, WKWebView JavaScript bridge, Swift contract scripts, native macOS build harness

---

### Task 1: Add a failing Sasayaki page-turn statistics contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`

- [x] Require the model to retain `StatisticsAutostartMode` and use it in the shared page-turn starter.
- [x] Require Sasayaki cross-chapter loading to call the starter.
- [x] Require the WebView bridge to call `onPageTurn` only after Sasayaki highlighting returns a progress value.
- [x] Run the focused Reader contract and confirm the missing Sasayaki trigger causes failure.

### Task 2: Wire both Sasayaki navigation boundaries

**Files:**
- Modify: `NativeMac/NativeReaderView.swift`

- [x] Replace the one-shot autostart Boolean with the configured mode and remove the helper's `UserConfig` parameter.
- [x] Update manual page-turn call sites to use the shared model helper.
- [x] Call the helper before Sasayaki cross-chapter loading.
- [x] Call `onPageTurn` when a same-chapter Sasayaki highlight returns changed progress.
- [x] Run the focused Reader contract and confirm it passes.

### Task 3: Verify all combined fixes

**Files:**
- Verify only

- [x] Run the bookshelf layout contract.
- [x] Run the focused Reader/Popup/Sasayaki regression contract.
- [x] Run `./script/build_and_run_native.sh --verify` and confirm the exact Light app identity and executable path.
- [x] Inspect the final diff and run `git diff --check`; do not commit without explicit approval.
