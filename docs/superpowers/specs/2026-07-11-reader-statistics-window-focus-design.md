# Reader Statistics Window Focus Design

## Context

The Catalyst Reader in `v0.5.0` paused reading statistics when the application resigned active and reset the tracking baseline before resuming. The native macOS Reader retained `isPaused` and the one-second statistics task, but its migration omitted the lifecycle transition that ever sets `isPaused` to `true`. As a result, elapsed wall-clock time can be counted while the Reader is not being used.

The native Reader already receives an `isActive` value derived from `NativeWindowActivityReader`, which observes the owning Reader window's key-window state. This existing signal is narrower than application `scenePhase` and matches the requested behavior: pause whenever the Reader window loses focus, including when Niratan moves to the background or another Niratan window becomes key.

## Goal

Count reading time only while all of these conditions are true:

- Statistics are enabled.
- Tracking has been started manually or by the configured autostart mode.
- The Reader window is the key window.

When the Reader window stops being key, preserve the final foreground interval and pause further accumulation. When it becomes key again, resume only an already-running tracking session without including the inactive interval.

## Non-goals

- Do not change statistics settings or autostart semantics.
- Do not pause merely because Reader chrome, a lookup popup, or another in-window control is shown while the Reader window remains key.
- Do not add another AppKit notification bridge or application-wide lifecycle coordinator.
- Do not change sync, bookmark, Sasayaki, or window presentation behavior.
- Do not add user-visible controls or localized strings.

## Design

### Reuse the existing key-window signal

`ReaderWindowRootView` already receives key-window changes through `NativeWindowActivityReader` and passes that state as `isActive` through `NativeReaderLoader` to `NativeReaderView`. `NativeReaderView` will reuse this value for both shortcut registration and statistics lifecycle handling.

The existing `onChange(of: isActive)` modifier will become an initial-aware transition so a Reader that first renders while its window is not key is immediately paused rather than waiting for a later focus change.

### Model-owned lifecycle transitions

`NativeReaderModel` will expose two idempotent methods:

- A window-inactive transition that acts only when tracking is running and not already paused. It flushes the current foreground interval first, then sets `isPaused` to `true`.
- A window-active transition that acts only when tracking is running and currently paused. It resets `lastTimestamp` and `lastCount` before setting `isPaused` to `false`.

Keeping the ordering inside model methods makes the invariant explicit:

1. Focus loss cannot discard the last partial second of valid reading time.
2. Focus regain cannot add the inactive wall-clock interval.
3. Repeated focus notifications do not double-flush or reset an active baseline.
4. A user-stopped timer remains stopped when focus returns.

The one-second task remains unchanged. While paused it stays attached to the Reader view but skips `updateStats()`, then continues after the model resumes.

### Data flow

```text
NSWindow key state
  -> NativeWindowActivityReader
  -> ReaderWindowRootView.isKeyWindow
  -> NativeReaderView.isActive
  -> NativeReaderModel pause/resume transition
  -> existing isPaused guard in the statistics task
```

## Testing

Follow test-driven development using `script/test_reader_popup_sasayaki_regressions.swift`:

1. Add contract assertions that require the Reader's existing `isActive` transition to drive statistics pause/resume.
2. Require a focus-loss method that flushes before setting `isPaused = true`.
3. Require a focus-gain method that resets the baseline before setting `isPaused = false`.
4. Require guards that keep both transitions idempotent and prevent focus gain from starting a stopped timer.
5. Run the contract before implementation and confirm it fails for the missing behavior.
6. Implement the model methods and wire them to the existing focus change.
7. Re-run the contract and confirm it passes.

After the focused contract passes:

- Run the full Reader popup/Sasayaki regression contract using the repository's documented `swiftc` invocation.
- Build and verify the Light configuration with an isolated instance identifier.
- Launch the exact DerivedData product produced by that verification.
- Do not import, replace, or delete user books or mutate user bookmarks for manual validation. If a safe disposable Reader fixture cannot prove the live focus transition, report that runtime scenario as unverified rather than using user data.

## Documentation

Add a concise user-visible entry to `docs/CHANGELOG.md` stating that reading statistics pause while the Reader window is not focused. No architecture or migration source-of-truth document changes are required because this restores intended Reader behavior without changing module boundaries.
