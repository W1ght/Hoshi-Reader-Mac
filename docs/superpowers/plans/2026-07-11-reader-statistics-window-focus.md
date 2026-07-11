# Reader Statistics Window Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause an active Reader statistics session whenever the native Reader window loses key-window focus, then resume without counting the inactive interval when that window becomes key again.

**Architecture:** Reuse the existing `NativeWindowActivityReader` → `ReaderWindowRootView.isKeyWindow` → `NativeReaderView.isActive` path. Keep focus transition invariants inside two idempotent `NativeReaderModel` methods, and let the existing one-second statistics task continue honoring `isPaused`.

**Tech Stack:** Swift 6, SwiftUI, AppKit key-window state, Observation, standalone Swift regression contracts, native macOS 26 Light build.

## Global Constraints

- Native macOS is the only supported target; do not reintroduce Catalyst or iOS lifecycle APIs.
- Reuse the existing `isActive` key-window signal; do not add another AppKit notification bridge or application-wide lifecycle coordinator.
- Focus loss must flush valid foreground time before pausing.
- Focus regain must reset `lastTimestamp` and `lastCount` before unpausing.
- Focus regain must never start a statistics session that the user stopped.
- Do not change statistics settings, autostart, sync, bookmark, Sasayaki, window presentation, localization, or user-data paths.
- Do not import, replace, rename, or delete user books, bookmarks, sidecars, or reading progress for validation.
- Use Conventional Commits and keep implementation tests/docs with their corresponding behavior.

---

### Task 1: Restore key-window statistics lifecycle

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift:1540-1625`
- Modify: `NativeMac/NativeReaderView.swift:501-590`
- Modify: `NativeMac/NativeReaderView.swift:1568-1598`

**Interfaces:**
- Consumes: `NativeReaderView.isActive: Bool`, already supplied by `ReaderWindowRootView` from `NativeWindowActivityReader`.
- Produces: `NativeReaderModel.pauseTrackingForWindowInactivity() -> Void` and `NativeReaderModel.resumeTrackingAfterWindowActivation() -> Void`.
- Preserves: `NativeReaderModel.isTracking`, `isPaused`, `flushStats()`, `resetTrackingBaseline()`, and the existing one-second task.

- [ ] **Step 1: Add failing lifecycle contract assertions**

Insert these assertions beside the existing native Reader statistics assertions in `script/test_reader_popup_sasayaki_regressions.swift`:

```swift
let statisticsWindowPauseSection = sourceSection(
    nativeReader,
    from: "func pauseTrackingForWindowInactivity()",
    to: "func resumeTrackingAfterWindowActivation()",
    "native Reader should expose the statistics focus-loss transition"
)
assertContains(
    statisticsWindowPauseSection,
    "guard isTracking, !isPaused else { return }\n        flushStats()\n        isPaused = true",
    "Reader focus loss should flush foreground statistics before pausing exactly once"
)
let statisticsWindowResumeSection = sourceSection(
    nativeReader,
    from: "func resumeTrackingAfterWindowActivation()",
    to: "func toggleStatisticsTracking()",
    "native Reader should expose the statistics focus-gain transition"
)
assertContains(
    statisticsWindowResumeSection,
    "guard isTracking, isPaused else { return }\n        resetTrackingBaseline()\n        isPaused = false",
    "Reader focus gain should reset the baseline before resuming an existing session"
)
assertContains(
    nativeReader,
    ".onChange(of: isActive, initial: true) { _, isActive in\n            updateKeyboardShortcutRegistration(isActive: isActive)\n            if isActive {\n                model.resumeTrackingAfterWindowActivation()\n            } else {\n                model.pauseTrackingForWindowInactivity()\n            }\n        }",
    "Reader key-window changes should drive shortcut and statistics lifecycle from the existing isActive signal"
)
```

- [ ] **Step 2: Run the focused contract and confirm the missing behavior fails**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-focus-red && \
/tmp/test_reader_popup_sasayaki_regressions-focus-red
```

Expected: exit nonzero with `FAIL: native Reader should expose the statistics focus-loss transition` and a missing boundary beginning with `func pauseTrackingForWindowInactivity()`.

- [ ] **Step 3: Add the two model-owned focus transition methods**

Insert after `stopTracking()` in `NativeReaderModel`:

```swift
func pauseTrackingForWindowInactivity() {
    guard isTracking, !isPaused else { return }
    flushStats()
    isPaused = true
}

func resumeTrackingAfterWindowActivation() {
    guard isTracking, isPaused else { return }
    resetTrackingBaseline()
    isPaused = false
}
```

This ordering intentionally lets `flushStats()` include the final foreground fraction before `isPaused` blocks further writes, and resets the baseline before the one-second task can observe the resumed state.

- [ ] **Step 4: Wire the existing key-window state into statistics lifecycle**

In `NativeReaderView.body`, remove the duplicate shortcut-registration call from `.onAppear`:

```swift
.onAppear {
    NativeReaderLifecycleRegistry.markActive(requestID: requestID, modelID: model.instanceID)
    XboxControllerManager.shared.configure(userConfig: userConfig)
    onFocusModeChanged(focusMode)
}
```

Replace the current `isActive` observer with an initial-aware observer:

```swift
.onChange(of: isActive, initial: true) { _, isActive in
    updateKeyboardShortcutRegistration(isActive: isActive)
    if isActive {
        model.resumeTrackingAfterWindowActivation()
    } else {
        model.pauseTrackingForWindowInactivity()
    }
}
```

- [ ] **Step 5: Run the focused contract and confirm it passes**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-focus-green && \
/tmp/test_reader_popup_sasayaki_regressions-focus-green
```

Expected: exit 0 with `reader popup/Sasayaki regressions passed`.

- [ ] **Step 6: Inspect the implementation diff and commit the behavior with its test**

Run:

```bash
git diff --check
git diff -- NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift
git status --short
```

Confirm only the lifecycle methods, existing `isActive` observer, and focused assertions changed. Then run:

```bash
git add NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift
git commit -m "fix(reader): pause statistics when window loses focus"
```

Expected: one Conventional Commit containing both the regression contract and implementation.

### Task 2: Record the user-visible fix and validation rule

**Files:**
- Modify: `docs/CHANGELOG.md:5-17`
- Modify: `docs/READER_REGRESSION_TESTING.md:29-54`

**Interfaces:**
- Consumes: the focus lifecycle behavior implemented in Task 1.
- Produces: release-visible Chinese/English notes and a durable actual-data validation requirement.

- [ ] **Step 1: Add the changelog entries under version 1.3.5**

Add to the Chinese list:

```markdown
- 修复 Reader 统计在阅读窗口失去焦点或 App 切到后台后仍继续计时的问题；重新聚焦时不会把离开期间计入阅读时间。
```

Add the matching English entry:

```markdown
- Fixed Reader statistics continuing to count after the Reader window lost focus or the app moved to the background; refocusing no longer includes the inactive interval in reading time.
```

- [ ] **Step 2: Add the focused actual-data validation item**

Add this bullet to the Reader actual-data matrix in `docs/READER_REGRESSION_TESTING.md`:

```markdown
- statistics tracking across Reader key-window changes: with tracking running, switch to another Niratan window and another app, wait long enough to distinguish the interval, then return and confirm the inactive interval is excluded; repeat with tracking manually stopped and confirm focus gain does not start it.
```

- [ ] **Step 3: Verify documentation scope and commit**

Run:

```bash
git diff --check
git diff -- docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
git status --short
```

Confirm the changelog contains only user-visible behavior and the regression document contains only an executable validation rule. Then run:

```bash
git add docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
git commit -m "docs(reader): cover statistics focus regression"
```

Expected: one documentation commit with the release note and validation matrix update.

### Task 3: Verify the native Reader fix and exact Light app identity

**Files:**
- Verify only; modify files only if a failed check identifies a defect within the approved scope.

**Interfaces:**
- Consumes: Task 1 lifecycle implementation and Task 2 validation requirements.
- Produces: fresh contract, build, launch, identity, and repository-state evidence.

- [ ] **Step 1: Run the complete focused Reader contract from a fresh binary**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-focus-final && \
/tmp/test_reader_popup_sasayaki_regressions-focus-final
```

Expected: exit 0 with `reader popup/Sasayaki regressions passed`.

- [ ] **Step 2: Build, launch, and verify the isolated Light app**

Run:

```bash
./script/build_and_run.sh --instance reader-statistics-focus --verify
```

Expected: exit 0; the script reports bundle id `moe.shishamo.hoshi` and a running executable inside the `reader-statistics-focus` DerivedData `Niratan.app` produced by this worktree.

- [ ] **Step 3: Perform safe runtime validation or record the exact limitation**

If an already-available disposable Reader fixture can be used without importing a book or changing a bookmark, follow the new matrix item: run tracking, move focus to another Niratan window and another app, wait at least five seconds in each state, return, and confirm neither inactive interval is added; manually stop tracking and confirm focus regain does not restart it.

If no disposable fixture exists, do not use a user book. Record that the key-window runtime transition was not manually validated, while distinguishing the fresh contract and exact Light build/launch evidence from that limitation.

- [ ] **Step 4: Review final branch state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -3
git diff main...HEAD --check
git diff --stat main...HEAD
git diff main...HEAD -- NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
```

Expected: clean worktree; the branch contains the design, implementation/test, and documentation commits; the diff is limited to the approved Reader statistics lifecycle scope.
