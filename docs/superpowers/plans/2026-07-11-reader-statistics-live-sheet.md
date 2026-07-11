# Reader Statistics Live Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native Statistics sheet update from `NativeReaderModel` in real time and continue counting only while either the Reader window or that Statistics sheet is key.

**Architecture:** Keep `ReaderStatisticsContentView` presentation-only. Add a native wrapper that observes `NativeReaderModel` and attaches the existing `NativeWindowActivityReader` to the Statistics sheet, while the model reconciles Reader-window and Statistics-sheet focus into one pause/resume state.

**Tech Stack:** Swift 6, SwiftUI Observation, AppKit `NSWindow` key-window notifications through `NativeWindowActivityReader`, standalone Swift regression contracts, native macOS 26 Light build.

## Global Constraints

- Native macOS is the only supported target; do not reintroduce Catalyst or iOS lifecycle APIs.
- Preserve the current native `.sheet` presentation, layout, labels, controls, and localization keys.
- Do not add a second timer or `TimelineView`; the existing one-second `NativeReaderModel` task remains the update source.
- Only the Statistics sheet joins the active statistics focus set; Appearance, Go To, and Sasayaki sheets remain inactive for statistics.
- Switching from the Statistics sheet to another window or app must pause; returning to the sheet must reset the baseline before resuming.
- Focus changes must not start a user-stopped statistics session or include inactive wall-clock time.
- Do not change statistics settings, autostart, sync, bookmark, Sasayaki, window presentation, localization, or user-data paths.
- Do not import, replace, rename, or delete user books, bookmarks, sidecars, or reading progress for validation.
- Use Conventional Commits and keep behavior tests with implementation changes.

---

### Task 1: Add a live observable Statistics sheet with aggregate focus

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift:1588-1660`
- Modify: `NativeMac/NativeReaderView.swift:145-180`
- Modify: `NativeMac/NativeReaderView.swift:501-545`
- Modify: `NativeMac/NativeReaderView.swift:1580-1615`
- Modify: `NativeMac/NativeReaderView.swift:1728-1750`
- Modify: `NativeMac/NativeReaderView.swift` after `NativeReaderView`

**Interfaces:**
- Consumes: existing `NativeReaderView.isActive`, `NativeWindowActivityReader`, `NativeReaderModel` statistics/progress properties, and `ReaderStatisticsContentView` value inputs.
- Produces: `NativeReaderModel.updateReaderWindowActivity(_ isActive: Bool)`, `NativeReaderModel.updateStatisticsSheetActivity(_ isActive: Bool)`, private `isStatisticsContextActive`, private `reconcileStatisticsFocus()`, and private `NativeReaderStatisticsSheet`.
- Preserves: `startTracking()`, `stopTracking()`, the one-second task, `ReaderStatisticsContentView`, and Reader shortcut registration.

- [ ] **Step 1: Replace the old single-window contract with failing aggregate-focus and live-sheet assertions**

In `script/test_reader_popup_sasayaki_regressions.swift`, replace the current assertions for `isReaderWindowActive`, `pauseTrackingForWindowInactivity()`, `resumeTrackingAfterWindowActivation()`, and the `isActive` observer with these assertions:

```swift
assertContains(
    nativeReader,
    "private var isReaderWindowActive = false\n    private var isStatisticsSheetActive = false",
    "native Reader should retain independent Reader-window and Statistics-sheet focus sources"
)
assertContains(
    nativeReader,
    "private var isStatisticsContextActive: Bool {\n        isReaderWindowActive || isStatisticsSheetActive\n    }",
    "native Reader should count while either approved statistics surface is key"
)
let statisticsStartSection = sourceSection(
    nativeReader,
    from: "func startTracking()",
    to: "func stopTracking()",
    "native Reader should expose statistics start behavior"
)
assertContains(
    statisticsStartSection,
    "isTracking = true\n        isPaused = !isStatisticsContextActive\n        resetTrackingBaseline()",
    "statistics started outside both approved focus surfaces should wait in a paused state"
)
let statisticsFocusSection = sourceSection(
    nativeReader,
    from: "func updateReaderWindowActivity(_ isActive: Bool)",
    to: "func toggleStatisticsTracking()",
    "native Reader should expose aggregate statistics focus reconciliation"
)
assertContains(
    statisticsFocusSection,
    "func updateReaderWindowActivity(_ isActive: Bool) {\n        isReaderWindowActive = isActive\n        reconcileStatisticsFocus()\n    }",
    "Reader-window focus should update its source before reconciliation"
)
assertContains(
    statisticsFocusSection,
    "func updateStatisticsSheetActivity(_ isActive: Bool) {\n        isStatisticsSheetActive = isActive\n        reconcileStatisticsFocus()\n    }",
    "Statistics-sheet focus should update its source before reconciliation"
)
assertContains(
    statisticsFocusSection,
    "if isStatisticsContextActive {\n            guard isTracking, isPaused else { return }\n            resetTrackingBaseline()\n            isPaused = false\n            return\n        }",
    "aggregate focus gain should reset the baseline before resuming an existing session"
)
assertContains(
    statisticsFocusSection,
    "guard isTracking, !isPaused else { return }\n        flushStats()\n        isPaused = true",
    "aggregate focus loss should flush foreground time before pausing"
)
assertContains(
    nativeReader,
    ".onChange(of: isActive, initial: true) { _, isActive in\n            updateKeyboardShortcutRegistration(isActive: isActive)\n            model.updateReaderWindowActivity(isActive)\n        }",
    "Reader key-window changes should keep shortcut and statistics focus responsibilities separate"
)
let statisticsSheetSection = sourceSection(
    nativeReader,
    from: "private struct NativeReaderStatisticsSheet: View",
    to: "private struct NativeReaderGlassIconButton: View",
    "native Reader should expose an observable Statistics sheet wrapper"
)
assertContains(
    statisticsSheetSection,
    "let model: NativeReaderModel",
    "Statistics sheet wrapper should observe the Reader model directly"
)
assertContains(
    statisticsSheetSection,
    "ReaderStatisticsContentView(\n            sessionStatistics: model.sessionStatistics,\n            todaysStatistics: model.todaysStatistics,\n            allTimeStatistics: model.allTimeStatistics",
    "Statistics sheet wrapper should pass fresh model values into the presentation view"
)
assertContains(
    statisticsSheetSection,
    "NativeWindowActivityReader { _, isKey in\n                model.updateStatisticsSheetActivity(isKey)\n            }",
    "Statistics sheet should reuse the existing window-activity reader for its own key state"
)
assertContains(
    statisticsSheetSection,
    ".onDisappear {\n            model.updateStatisticsSheetActivity(false)\n        }",
    "Statistics sheet dismissal should clear its focus source"
)
assertContains(
    nativeReader,
    "case .statistics:\n                NativeReaderStatisticsSheet(",
    "native Reader should present the observable Statistics sheet wrapper"
)
assertNotContains(
    statisticsSheetSection,
    "TimelineView",
    "Statistics sheet should rely on model observation instead of a second timer"
)
```

- [ ] **Step 2: Run the focused contract and confirm the live-sheet behavior is missing**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-live-sheet-red && \
/tmp/test_reader_popup_sasayaki_regressions-live-sheet-red
```

Expected: exit nonzero with `FAIL: native Reader should retain independent Reader-window and Statistics-sheet focus sources` and the missing two-property sequence.

- [ ] **Step 3: Replace single-window pause/resume with aggregate focus reconciliation**

In `NativeReaderModel`, add the Statistics sheet source and aggregate state beside `isReaderWindowActive`:

```swift
private var isReaderWindowActive = false
private var isStatisticsSheetActive = false

private var isStatisticsContextActive: Bool {
    isReaderWindowActive || isStatisticsSheetActive
}
```

Update `startTracking()`:

```swift
func startTracking() {
    guard enableStatistics else { return }
    isTracking = true
    isPaused = !isStatisticsContextActive
    resetTrackingBaseline()
    readerStatisticsLogger.notice(
        "reader.statistics.start book=\(self.book.folder, privacy: .public) mode=\(self.statisticsAutostartMode.rawValue, privacy: .public) chapter=\(self.index, privacy: .public) progress=\(self.progress, privacy: .public) current=\(self.currentCharacter, privacy: .public)"
    )
}
```

Replace `pauseTrackingForWindowInactivity()` and `resumeTrackingAfterWindowActivation()` with:

```swift
func updateReaderWindowActivity(_ isActive: Bool) {
    isReaderWindowActive = isActive
    reconcileStatisticsFocus()
}

func updateStatisticsSheetActivity(_ isActive: Bool) {
    isStatisticsSheetActive = isActive
    reconcileStatisticsFocus()
}

private func reconcileStatisticsFocus() {
    if isStatisticsContextActive {
        guard isTracking, isPaused else { return }
        resetTrackingBaseline()
        isPaused = false
        return
    }

    guard isTracking, !isPaused else { return }
    flushStats()
    isPaused = true
}
```

- [ ] **Step 4: Keep shortcut registration separate from Reader focus reconciliation**

Replace the current `isActive` observer in `NativeReaderView.body` with:

```swift
.onChange(of: isActive, initial: true) { _, isActive in
    updateKeyboardShortcutRegistration(isActive: isActive)
    model.updateReaderWindowActivity(isActive)
}
```

- [ ] **Step 5: Add the observable Statistics sheet wrapper and use it from the sheet switch**

Add this private wrapper before `NativeReaderGlassIconButton` in `NativeMac/NativeReaderView.swift`:

```swift
private struct NativeReaderStatisticsSheet: View {
    let model: NativeReaderModel
    let contentLanguage: ContentLanguageProfile
    let onClose: () -> Void

    var body: some View {
        ReaderStatisticsContentView(
            sessionStatistics: model.sessionStatistics,
            todaysStatistics: model.todaysStatistics,
            allTimeStatistics: model.allTimeStatistics,
            bookCharacterCount: model.bookInfo.characterCount,
            currentCharacter: model.currentCharacter,
            currentChapterCount: model.currentChapterCount,
            contentLanguage: contentLanguage,
            isTracking: model.isTracking,
            onStart: model.startTracking,
            onStop: model.stopTracking,
            onClose: onClose
        )
        .background {
            NativeWindowActivityReader { _, isKey in
                model.updateStatisticsSheetActivity(isKey)
            }
        }
        .onDisappear {
            model.updateStatisticsSheetActivity(false)
        }
    }
}
```

Replace the `.statistics` sheet case with:

```swift
case .statistics:
    NativeReaderStatisticsSheet(
        model: model,
        contentLanguage: ProfileRepository.shared.resolve(
            .book(profileID: model.book.profileId, bookLanguage: model.book.bookLanguage)
        ).language,
        onClose: {
            activeSheet = nil
        }
    )
    .frame(minWidth: 520, minHeight: 560)
```

- [ ] **Step 6: Run the focused contract and confirm aggregate focus/live observation passes**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-live-sheet-green && \
/tmp/test_reader_popup_sasayaki_regressions-live-sheet-green
```

Expected: exit 0 with `reader popup/Sasayaki regressions passed`.

- [ ] **Step 7: Inspect and commit the behavior with its contract**

Run:

```bash
git diff --check
git diff -- NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift
git status --short
```

Confirm `Features/Reader/StatisticsView.swift` and `NativeMac/NativeWindowActivityReader.swift` remain unchanged. Then run:

```bash
git add NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift
git commit -m "fix(reader): update statistics sheet live"
```

Expected: one Conventional Commit containing the focus aggregation, observable wrapper, and regression contract.

### Task 2: Update user-visible and actual-data documentation

**Files:**
- Modify: `docs/CHANGELOG.md:8-18`
- Modify: `docs/READER_REGRESSION_TESTING.md:39-45`

**Interfaces:**
- Consumes: the live Statistics sheet and aggregate focus behavior from Task 1.
- Produces: updated Chinese/English release notes and a focused manual validation rule.

- [ ] **Step 1: Expand the existing 1.3.5 changelog entries**

Replace the Chinese statistics entry with:

```markdown
- 修复 Reader 统计在离开阅读窗口或统计面板后仍继续计时的问题；统计面板现在会实时刷新，并在面板处于焦点时继续计时，切到其他窗口或 App 后暂停且不会补算离开时间。
```

Replace the English entry with:

```markdown
- Fixed Reader statistics continuing after leaving the Reader window or Statistics sheet. The open Statistics sheet now updates live and keeps counting while focused, then pauses without backfilling inactive time after switching to another window or app.
```

- [ ] **Step 2: Expand the Reader actual-data matrix item**

Replace the existing statistics focus bullet with:

```markdown
- statistics tracking across Reader and Statistics-sheet key-window changes: with tracking running, open Statistics and confirm session/today/all-time values plus the start/stop control update live; switch from the sheet to another Niratan window and another app, wait long enough to distinguish each interval, then return and confirm inactive time is excluded; close the sheet and repeat with tracking manually stopped to confirm focus gain does not start it; Appearance, Go To, and Sasayaki sheets must not keep statistics active.
```

- [ ] **Step 3: Verify documentation scope and commit**

Run:

```bash
git diff --check
git diff -- docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
git status --short
```

Then run:

```bash
git add docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
git commit -m "docs(reader): document live statistics sheet"
```

Expected: one documentation commit limited to the existing release note and Reader validation matrix.

### Task 3: Verify the live Statistics sheet in the exact Light app

**Files:**
- Verify only; modify files only if a failed check identifies a defect within the approved scope.

**Interfaces:**
- Consumes: Task 1 implementation and Task 2 validation rule.
- Produces: fresh contract, build, launch, identity, and repository-state evidence.

- [ ] **Step 1: Run the complete focused Reader contract from a fresh binary**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions-live-sheet-final && \
/tmp/test_reader_popup_sasayaki_regressions-live-sheet-final
```

Expected: exit 0 with `reader popup/Sasayaki regressions passed`.

- [ ] **Step 2: Build, launch, and verify the isolated Light app**

Run:

```bash
./script/build_and_run.sh --instance reader-statistics-focus --verify
```

Expected: exit 0; the script reports bundle id `moe.shishamo.hoshi` and a running executable inside this worktree's `reader-statistics-focus` DerivedData `Niratan.app`.

- [ ] **Step 3: Perform safe live-sheet validation or record the limitation**

If an already-available disposable Reader fixture can be used without importing a book or changing a bookmark, follow the new matrix item and confirm at least two consecutive per-second changes in the Statistics sheet while it is key, pause after switching away, baseline reset after return, and live start/stop control changes.

If no disposable fixture exists, do not use a user book. Record that the live Statistics-sheet UI and focus transitions were not manually validated with actual EPUB data, while distinguishing the fresh contract and exact Light build/launch evidence from that limitation.

- [ ] **Step 4: Review final branch state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -8
git diff main...HEAD --check
git diff --stat main...HEAD
git diff main...HEAD -- NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift docs/CHANGELOG.md docs/READER_REGRESSION_TESTING.md
```

Expected: clean worktree; the branch contains the live-sheet implementation/test and documentation commits in addition to the existing focus lifecycle work; the product diff remains limited to Reader statistics lifecycle and presentation wiring.
