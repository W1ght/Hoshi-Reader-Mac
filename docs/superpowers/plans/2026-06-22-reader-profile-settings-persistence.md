# Reader Profile Settings Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist Reader Profile appearance changes to `reader_settings.json` as they happen so relaunch cannot restore an older snapshot.

**Architecture:** Add a focused Reader-only persistence entry point to `ProfileSettingsStore`, retaining its existing atomic JSON writer and current `appliedProfileID`. Observe the equatable `ReaderProfileSettings` snapshot once at the macOS app root and send each changed snapshot to that entry point; keep scene-phase persistence as a fallback.

**Tech Stack:** Swift 6, SwiftUI Observation, Foundation JSON persistence, shell-driven Swift regression scripts.

---

### Task 1: Add the failing persistence regression

**Files:**
- Create: `script/test_reader_profile_settings_persistence.swift`
- Test: `Core/ProfileSettingsStore.swift`
- Test: `Models/Profile.swift`
- Test: `Core/ProfileRepository.swift`

- [x] **Step 1: Write a focused executable test**

Create a temporary `ProfileRepository`, construct `ProfileSettingsStore(repository:)`, call `persistReaderSettings(_:)` with a non-default `ReaderProfileSettings`, decode `reader_settings.json`, and assert exact equality. Include a minimal test-only `UserConfig` stub for the store's existing bootstrap and Profile-switching methods.

- [x] **Step 2: Run the test to verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Models/Anki.swift Models/Profile.swift Models/Dictionary.swift \
  Core/ProfileRepository.swift \
  Core/ProfileSettingsStore.swift \
  script/test_reader_profile_settings_persistence.swift \
  -o /tmp/test_reader_profile_settings_persistence && \
/tmp/test_reader_profile_settings_persistence
```

Expected: compilation fails because `ProfileSettingsStore(repository:)` is private and `persistReaderSettings(_:)` does not exist.

### Task 2: Implement Reader-only immediate persistence

**Files:**
- Modify: `Core/ProfileSettingsStore.swift`
- Modify: `NativeMac/HoshiNativeMacApp.swift`

- [x] **Step 1: Expose the focused persistence seam**

Make the repository initializer internal for the executable regression and add:

```swift
func persistReaderSettings(_ settings: ReaderProfileSettings) {
    save(
        settings,
        to: repository.readerSettingsURL(for: appliedProfileID)
    )
}
```

Update `persistCurrent(userConfig:)` to reuse this method for its Reader half while leaving dictionary persistence unchanged.

- [x] **Step 2: Wire the app-wide change observation**

After bootstrap at the macOS app root, observe the complete equatable snapshot:

```swift
.onChange(of: userConfig.readerProfileSettings()) { _, settings in
    ProfileSettingsStore.shared.persistReaderSettings(settings)
}
```

This preserves Profile switching: the old Profile is saved before `appliedProfileID` changes, and any callback caused by loading the new Profile writes only the new snapshot to the new Profile.

- [x] **Step 3: Run the focused test to verify GREEN**

Run the Task 1 command. Expected: `Reader profile settings persistence tests passed`.

- [x] **Step 4: Add a source-level wiring assertion**

Extend the executable test to read `NativeMac/HoshiNativeMacApp.swift` from the repository root and assert that the full Reader snapshot is observed and passed to `persistReaderSettings`. Re-run the focused test and expect PASS.

### Task 3: Regression and app verification

**Files:**
- Verify: `script/test_profile_repository.swift`
- Verify: `script/test_reader_popup_sasayaki_regressions.swift`
- Verify: `script/build_and_run.sh`

- [x] **Step 1: Run Profile repository tests**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift \
  Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift \
  script/test_profile_repository.swift \
  -o /tmp/test_profile_repository && \
/tmp/test_profile_repository
```

Expected: `Profile repository tests passed`.

- [x] **Step 2: Run Reader contract regressions**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions && \
/tmp/test_reader_popup_sasayaki_regressions
```

Expected: all Reader/Popup/Sasayaki contract assertions pass.

- [x] **Step 3: Build, verify identity, and launch Light**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build succeeds; the product and running process both report bundle id `moe.shishamo.hoshi`, and the running executable path matches this DerivedData product.

- [x] **Step 4: Review the scoped diff**

Run `git diff --check` and inspect only the new design/plan/test plus `Core/ProfileSettingsStore.swift` and `NativeMac/HoshiNativeMacApp.swift`. Do not stage or commit without explicit user approval.
