# Root Profile Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native root surface the single runtime owner of Global, Book, and Video Profile activation.

**Architecture:** Introduce a narrow coordinator that resolves `ProfileContext` and synchronizes Profile-owned settings, dictionaries, and Anki. `NativeMacRootView` selects the context from the visible surface and observes Profile selection changes; child views only persist selection intent and continue passing explicit Profile IDs to lookup/mining.

**Tech Stack:** Swift 6, SwiftUI Observation, existing ProfileRepository/ProfileResolver, standalone Swift contract tests, Xcode Light and Video schemes.

---

### Task 1: Specify root-owned activation

**Files:**
- Modify: `script/test_profile_repository.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`

- [ ] Extend `testResolutionPrecedenceAndFallbacks()` with an English global Profile and Japanese Video Profile, requiring `.global` to resolve English, `.video(default-ja-video)` to resolve Japanese Video, then `.global` to remain English.
- [ ] Add failing Video contracts requiring `Core/ProfileActivationCoordinator.swift`, root observation of section/global/video selection, and absence of direct `ProfileSettingsStore`, `DictionaryManager`, and `AnkiManager` activation in `VideoPlayerScreen` and `ProfilesView`.
- [ ] Run the Profile test and `swift script/test_video_liquid_glass_contract.swift`; confirm the Video contract fails because root-owned coordination is missing.

### Task 2: Add the activation boundary

**Files:**
- Create: `Core/ProfileActivationCoordinator.swift`
- Modify: `Core/ProfileSettingsStore.swift`

- [ ] Implement:

```swift
@MainActor
enum ProfileActivationCoordinator {
    @discardableResult
    static func activate(
        _ context: ProfileContext,
        userConfig: UserConfig,
        repository: ProfileRepository = .shared
    ) -> HoshiProfile {
        let profile = repository.resolve(context)
        ProfileSettingsStore.shared.activate(profileID: profile.id, userConfig: userConfig)
        DictionaryManager.shared.activateProfile(profile.id)
        AnkiManager.shared.activateProfile(profile.id)
        return profile
    }
}
```

- [ ] Prevent `ProfileSettingsStore.activate` from persisting a deleted `appliedProfileID` by checking that the old Profile still exists before `persistCurrent`; this lets root observation safely activate the deletion fallback without recreating the removed directory.

### Task 3: Move surface ownership to NativeMacRootView

**Files:**
- Modify: `NativeMac/NativeMacRootView.swift`

- [ ] Store the observable shared repository in the root and add `activateCurrentProfileContext()` with precedence Book → active Video → Global.
- [ ] Activate that context on root appearance and changes to selected section, global active Profile ID, and stored Video Profile ID.
- [ ] Replace direct Book/global manager calls with `ProfileActivationCoordinator.activate` while preserving Reader language backfill and English Profile prompting.
- [ ] Run the Video contract and confirm the root ownership assertions pass.

### Task 4: Remove child-view Profile ownership

**Files:**
- Modify: `Features/Video/VideoPlayerScreen.swift`
- Modify: `Features/Settings/ProfilesView.swift`

- [ ] Remove Video `onAppear` activation, `onDisappear` global restoration, and `activateVideoProfile()`.
- [ ] Change Video selection to close the popup stack first and then call only `profileRepository.setVideoProfile(profileID)`; root observation performs runtime activation.
- [ ] Change Profiles settings activation to call only `repository.setGlobalActiveProfile`, and remove direct service activation from deletion. Keep all editing, primary language defaults, and error presentation unchanged.
- [ ] Run Profile and Video contracts and confirm they pass.

### Task 5: Document and verify both variants

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`

- [ ] Document that Profile activation follows the visible root surface and that Video selection cannot be overwritten by the Global Profile.
- [ ] Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift script/test_profile_repository.swift -o /tmp/test_profile_repository && /tmp/test_profile_repository
swift script/test_video_liquid_glass_contract.swift
./script/verify_video_variant_contract.sh
```
- [ ] Run `./script/build_and_run.sh --verify`, then `./script/build_and_run.sh --video --verify`; require exact bundle ID/path verification and leave the Video build running.
- [ ] Run `git diff --check`. Do not commit, push, or release without separate user authorization.
