# Native Reader Programmatic Navigation Statistics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent programmatic Reader position changes from being counted as reading while preserving ordinary page and chapter-boundary statistics.

**Architecture:** Split bookmark persistence from statistics checkpoints inside `NativeReaderModel`. Route known programmatic destinations through flush-old, persist-new, reset-baseline semantics, and add a WebView callback that completes fragment jumps with their resolved progress.

**Tech Stack:** Swift 6, SwiftUI, WKWebView, the existing Reader source-contract harness, and the native macOS build script.

---

### Task 1: Add a failing programmatic-navigation statistics contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] Add source assertions requiring `persistBookmark(_:)`, `syncProgressAfterProgrammaticJump(_:)`, the same-chapter link branch, and baseline resets in programmatic navigation.
- [ ] Assert that `restorePosition(_:)` uses persist-only bookmark storage rather than `saveBookmark(_:)`.
- [ ] Run the focused Reader contract and confirm it fails for the missing semantics.

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
```

Expected: FAIL on the first newly required programmatic-navigation statistics contract.

### Task 2: Separate persistence from statistics and align navigation

**Files:**
- Modify: `NativeMac/NativeReaderView.swift`

- [ ] Extract `persistBookmark(_:)` from `saveBookmark(_:)`; retain `flushStats()` only in the public reading checkpoint.
- [ ] Change chapter-list, character/highlight, and history restoration paths to flush the old position, persist the new destination, and reset the baseline.
- [ ] Align adjacent next/previous chapter transitions with one post-switch statistics flush.
- [ ] Handle same-chapter internal links without a reload and cross-chapter links through the existing load path.
- [ ] Add `syncProgressAfterProgrammaticJump(_:)` and an `onInternalJump` WebView callback so resolved fragment progress is persisted and becomes the new baseline without being counted.
- [ ] Run the focused Reader contract and confirm it passes.

### Task 3: Record the regression boundary

**Files:**
- Modify: `docs/READER_REGRESSION_TESTING.md`

- [ ] Extend the existing navigation-history matrix item to require unchanged character totals across chapter-list, history, and internal-link jumps, while confirming normal page turns and chapter-boundary reading still advance statistics.
- [ ] Run `git diff --check`.

### Task 4: Verify the native Reader

**Files:**
- Verify the complete task diff without staging or committing.

- [ ] Run the focused Reader contract.
- [ ] Run `./script/build_and_run.sh --verify` and confirm bundle id `moe.shishamo.hoshi` plus the exact DerivedData executable path.
- [ ] Inspect `git diff`, `git diff --stat`, and `git status --short` for task-only changes.
- [ ] Report any actual-EPUB scenarios that could not be safely exercised without changing user data.
