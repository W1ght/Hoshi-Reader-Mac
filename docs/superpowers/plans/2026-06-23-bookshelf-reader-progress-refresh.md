# Bookshelf Reader Progress Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the native bookshelf's displayed reading progress immediately after closing the Reader.

**Architecture:** Preserve the Reader's existing bookmark persistence and dismissal flow. Let `NativeBookshelfReuseView`, which owns `BookshelfViewModel`, observe the shared reader selection binding and reload its cached books and progress only on the transition from an open Reader to no selected book.

**Tech Stack:** SwiftUI Observation, Swift contract scripts, native macOS build harness

---

### Task 1: Lock the Reader-close refresh behavior with a contract

**Files:**
- Modify: `script/test_bookshelf_layout_contract.swift`

- [x] Add an assertion that `NativeBookshelfReuseView` observes `selectedReaderBook`, guards the old value as non-`nil` and the new value as `nil`, then calls `viewModel.loadBooks()`.
- [x] Run `swift script/test_bookshelf_layout_contract.swift` and confirm it fails with the new Reader-close refresh message.

### Task 2: Refresh the bookshelf after Reader dismissal

**Files:**
- Modify: `NativeMac/NativeReuseViews.swift`

- [x] Add an `onChange(of: selectedReaderBook)` handler to `NativeBookshelfReuseView.body`.
- [x] Guard for a transition from non-`nil` to `nil` and call `viewModel.loadBooks()`.
- [x] Run `swift script/test_bookshelf_layout_contract.swift` and confirm it passes.

### Task 3: Verify the affected native path

**Files:**
- Verify only

- [x] Run the Reader regression contract command documented in `AGENTS.md`.
- [x] Run `./script/build_and_run_native.sh --verify` and confirm the built bundle identifier and running executable path belong to this DerivedData Light app.
- [x] Inspect `git diff --check`, `git status --short`, and the focused diff. Do not commit without explicit user approval.
