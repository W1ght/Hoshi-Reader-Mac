# Native Reader Navigation History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the native Reader's backward and forward progress controls after chapter, highlight, character, and internal-link jumps.

**Architecture:** Keep session-only position stacks inside `NativeReaderModel`, record only explicit jumps, and restore destinations through the model's existing chapter/bookmark path. Route manual page/scroll activity through one model callback so forward history expires without treating ordinary reading as another jump.

**Tech Stack:** Swift 6, SwiftUI, Observation, WKWebView, the existing source-contract Swift harness, and the native macOS build script.

---

### Task 1: Add a failing Reader navigation-history contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] **Step 1: Add assertions for the missing behavior**

Add source-contract assertions requiring `NativeReaderPosition`, back/forward stacks and targets, `recordPosition()` in all three jump paths, guarded history navigation, manual-navigation forward-history clearing, and the two return-arrow controls wired to `navigateBackwards()` and `navigateForwards()`.

```swift
assertContains(nativeReader, "private struct NativeReaderPosition", "native Reader should model jump destinations")
assertContains(nativeReader, "private var backHistory: [NativeReaderPosition] = []", "native Reader should retain backward jump history")
assertContains(nativeReader, "private var forwardHistory: [NativeReaderPosition] = []", "native Reader should retain forward jump history")
assertOccurrenceCountAtLeast(nativeReader, "recordPosition()", 4, "all explicit Reader jumps should record their origin")
assertContains(nativeReader, "func navigateBackwards()", "native Reader should restore a backward destination")
assertContains(nativeReader, "func navigateForwards()", "native Reader should restore a forward destination")
assertContains(nativeReader, "func handleManualNavigation()", "manual reading should invalidate stale forward history")
assertContains(nativeReader, "arrow.uturn.backward.circle", "native Reader should show the backward progress control")
assertContains(nativeReader, "arrow.uturn.right.circle", "native Reader should show the forward progress control")
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
```

Expected: FAIL because the native model has no navigation-history types, stacks, methods, or controls.

### Task 2: Implement session navigation history and controls

**Files:**
- Modify: `NativeMac/NativeReaderView.swift`

- [ ] **Step 1: Add model state and safe destination conversion**

Define `NativeReaderPosition(index:progress:)`, `backHistory`, `forwardHistory`, `currentPosition`, optional `backTarget`/`forwardTarget`, and a bounds-checked helper that converts a position through `document.manifest` and `bookInfo.chapterInfo` into a raw book character count.

- [ ] **Step 2: Record explicit jumps and restore history destinations**

Call `recordPosition()` after validation but before mutation in `jumpToCharacter`, `jumpToChapter`, and resolved `jumpToLink`. Implement guarded backward/forward navigation that moves the current position to the opposite stack and restores the target using one private method that preserves stats flushing, Sasayaki transition preparation, bookmark saving, popup dismissal, load state, and chapter state refresh.

```swift
func navigateBackwards() {
    guard let target = backHistory.popLast() else { return }
    forwardHistory.append(currentPosition)
    restorePosition(target)
}

func navigateForwards() {
    guard let target = forwardHistory.popLast() else { return }
    backHistory.append(currentPosition)
    restorePosition(target)
}
```

- [ ] **Step 3: Clear stale forward history on manual reading**

Add `handleManualNavigation()` to retain page-turn statistics behavior and clear forward history when the user reads away from a returned position. Use it for native backward/forward page actions, the WebView `onPageTurn` callback, and continuous-scroll progress messages.

```swift
func handleManualNavigation() {
    startTrackingOnPageTurnIfNeeded()
    forwardHistory.removeAll()
}
```

- [ ] **Step 4: Render both progress controls**

In `nativeBottomControls`, display the optional backward control after the close button and the optional forward control before the existing right-side tools. Convert raw target counts with the active Profile language's `displayCount(forRawCharacters:)`, use `arrow.uturn.backward.circle` / `arrow.uturn.right.circle`, and wire the buttons to the model history methods.

- [ ] **Step 5: Run the focused contract and verify GREEN**

Run the command from Task 1. Expected: PASS with `Reader popup/Sasayaki regression checks passed`.

### Task 3: Update the Reader validation truth source

**Files:**
- Modify: `docs/READER_REGRESSION_TESTING.md`

- [ ] **Step 1: Extend the actual-EPUB matrix**

Add one focused item covering chapter, highlight, character-count and internal-link jumps; backward/forward progress restoration; manual navigation invalidating forward history; same/cross-chapter destinations; and paginated/continuous modes.

- [ ] **Step 2: Check documentation and patch formatting**

Run:

```bash
git diff --check
```

Expected: exit 0 with no whitespace errors.

### Task 4: Verify and commit the complete working tree

**Files:**
- Verify all current tracked and untracked task files intended for the branch.

- [ ] **Step 1: Run focused Swift contracts**

Run the Reader command from Task 1 and:

```bash
swift script/test_bookshelf_layout_contract.swift
```

Expected: both exit 0.

- [ ] **Step 2: Build, launch, and verify the Light app identity**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build success, bundle id `moe.shishamo.hoshi`, and a running executable inside the exact DerivedData `.app` path.

- [ ] **Step 3: Inspect scope and create the requested commit**

Review `git diff`, `git diff --stat`, and `git status --short`; stage the current branch work after verification and commit it with a Conventional Commit message describing the combined native Reader work.
