# Reader Statistics Window Focus Design

## Context

The Catalyst Reader in `v0.5.0` paused reading statistics when the application resigned active and reset the tracking baseline before resuming. The native macOS Reader retained `isPaused` and the one-second statistics task, but its migration omitted the lifecycle transition that ever sets `isPaused` to `true`. As a result, elapsed wall-clock time can be counted while the Reader is not being used.

The native Reader already receives an `isActive` value derived from `NativeWindowActivityReader`, which observes the owning Reader window's key-window state. This existing signal is narrower than application `scenePhase` and matches the requested behavior: pause whenever the Reader window loses focus, including when Niratan moves to the background or another Niratan window becomes key.

The Statistics sheet currently receives `Statistics` value snapshots when its content is created. It does not retain an observation dependency on `NativeReaderModel`, so session, today, all-time, speed, remaining-time, and tracking-control values can remain frozen while the underlying model continues updating. The Statistics sheet is also a separate native sheet window, so it needs its own key-window signal if it is allowed to count as an active Reader statistics surface.

## Goal

Count reading time only while all of these conditions are true:

- Statistics are enabled.
- Tracking has been started manually or by the configured autostart mode.
- Either the Reader window or its Statistics sheet is the key window.

When neither approved statistics surface is key, preserve the final foreground interval and pause further accumulation. When either surface becomes key again, resume only an already-running tracking session without including the inactive interval. While the Statistics sheet is visible, every displayed value and its start/stop control must reflect the current model state in real time.

## Non-goals

- Do not change statistics settings or autostart semantics.
- Do not pause merely because Reader chrome, a lookup popup, or another in-window control is shown while the Reader window remains key.
- Do not treat Appearance, Go To, or Sasayaki sheets as active statistics surfaces; only the Statistics sheet receives this exception.
- Do not add another AppKit notification bridge or application-wide lifecycle coordinator.
- Do not change sync, bookmark, Sasayaki, or window presentation behavior.
- Do not replace the native Statistics sheet with an overlay, popover, inspector, or standalone window.
- Do not add user-visible controls or localized strings.

## Design

### Reuse the existing key-window signal

`ReaderWindowRootView` already receives key-window changes through `NativeWindowActivityReader` and passes that state as `isActive` through `NativeReaderLoader` to `NativeReaderView`. `NativeReaderView` will reuse this value for both shortcut registration and statistics lifecycle handling.

The existing `onChange(of: isActive)` modifier will become an initial-aware transition so a Reader that first renders while its window is not key is immediately paused rather than waiting for a later focus change.

### Model-owned focus reconciliation

`NativeReaderModel` will retain two independent focus sources:

- Reader window key state, supplied by the existing `NativeReaderView.isActive` path.
- Statistics sheet key state, supplied by a second `NativeWindowActivityReader` attached inside the Statistics sheet.

The effective statistics context is active when either source is active. Updating either source will reconcile the aggregate state through one model-owned transition:

- Moving from active to inactive flushes the final foreground interval before setting `isPaused = true`.
- Moving from inactive to active resets `lastTimestamp` and `lastCount` before setting `isPaused = false`.

`startTracking()` will enter a paused state when neither source is active, so a background Sasayaki transition cannot bypass the focus rule. Repeated or reordered parent/sheet notifications remain idempotent because reconciliation compares the aggregate state rather than treating every notification as a standalone pause or resume.

Keeping the ordering inside model methods makes the invariant explicit:

1. Focus loss cannot discard the last partial second of valid reading time.
2. Focus regain cannot add the inactive wall-clock interval.
3. Repeated focus notifications do not double-flush or reset an active baseline.
4. A user-stopped timer remains stopped when focus returns.

The one-second task remains keyed to `isTracking`. Once tracking starts, the task stays attached while paused and skips `updateStats()`, then continues after the model resumes. Its initial guard checks only `isTracking`, allowing a session that starts inactive to remain ready for a later focus-driven resume.

### Live Statistics sheet ownership

`ReaderStatisticsContentView` remains a presentation-only view with value inputs and action closures. A new native Reader wrapper will receive `NativeReaderModel` explicitly and read the current statistics, progress, and tracking state in its own `body`. Swift Observation will then invalidate that wrapper whenever the one-second task updates the model, and the wrapper will pass fresh values into `ReaderStatisticsContentView` without introducing a second UI timer.

The wrapper also hosts `NativeWindowActivityReader` inside the sheet. Its key-window changes update only the Statistics sheet focus source in `NativeReaderModel`; the main Reader signal continues to control Reader shortcuts independently.

### Data flow

```text
Reader NSWindow key state
  -> NativeWindowActivityReader
  -> ReaderWindowRootView.isKeyWindow
  -> NativeReaderView.isActive
  -> NativeReaderModel Reader focus source

Statistics sheet NSWindow key state
  -> NativeWindowActivityReader inside NativeReaderStatisticsSheet
  -> NativeReaderModel Statistics sheet focus source

NativeReaderModel aggregate focus reconciliation
  -> existing isPaused guard in the statistics task
  -> per-second observable statistics updates
  -> NativeReaderStatisticsSheet rebuild
  -> ReaderStatisticsContentView fresh value inputs
```

## Testing

Follow test-driven development using `script/test_reader_popup_sasayaki_regressions.swift`:

1. Add contract assertions that require the Reader's existing `isActive` transition to drive statistics pause/resume.
2. Require a focus-loss method that flushes before setting `isPaused = true`.
3. Require a focus-gain method that resets the baseline before setting `isPaused = false`.
4. Require guards that keep both transitions idempotent and prevent focus gain from starting a stopped timer.
5. Require tracking started while the Reader is inactive to stay paused, with the one-second task retained for later resume.
6. Require the model to combine Reader-window and Statistics-sheet focus sources before pausing or resuming.
7. Require a native Statistics sheet wrapper that reads the observable model directly and attaches the existing window-activity reader to the sheet.
8. Require other Reader sheets to remain outside the active statistics focus set.
9. Run the contract before implementation and confirm it fails for the missing behavior.
10. Implement the focus reconciliation and observable sheet wrapper.
11. Re-run the contract and confirm it passes.

After the focused contract passes:

- Run the full Reader popup/Sasayaki regression contract using the repository's documented `swiftc` invocation.
- Build and verify the Light configuration with an isolated instance identifier.
- Launch the exact DerivedData product produced by that verification.
- Do not import, replace, or delete user books or mutate user bookmarks for manual validation. If a safe disposable Reader fixture cannot prove the live focus transition, report that runtime scenario as unverified rather than using user data.

## Documentation

Add a concise user-visible entry to `docs/CHANGELOG.md` stating that reading statistics pause outside the Reader/Statistics sheet focus scope and that the open Statistics sheet now updates live. No architecture or migration source-of-truth document changes are required because this restores intended Reader behavior without changing module boundaries.
