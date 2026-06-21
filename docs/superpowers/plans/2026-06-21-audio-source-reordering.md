# Audio Source Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent, whole-row drag-and-drop ordering to Audio settings, including the auto-managed local audio source.

**Architecture:** Add an audio-scoped drag payload and destination calculator beside `AudioSource`, mirror the established Dictionary row interaction in `AudioView`, and change local-source normalization to preserve an existing source's index. Continue persisting the ordered array through `UserConfig.audioSources`.

**Tech Stack:** Swift 6, SwiftUI drag and drop, Observation/UserDefaults, standalone Swift contract tests.

---

### Task 1: Audio reorder logic

**Files:**
- Modify: `Models/Dictionary.swift`
- Create: `script/test_audio_source_reorder.swift`

- [ ] Add failing tests that require `AudioSourceReorder.payload(for:)`, `audioSourceID(from:)`, and forward/backward/same-row destination offsets:

```swift
let id = "https://example.test/audio?term={term}"
expect(AudioSourceReorder.audioSourceID(from: AudioSourceReorder.payload(for: id)) == id, "payload round trip")
expect(AudioSourceReorder.audioSourceID(from: id) == nil, "reject unscoped payload")
expect(AudioSourceReorder.destinationOffset(sourceIndex: 0, targetIndex: 2) == 3, "move down")
expect(AudioSourceReorder.destinationOffset(sourceIndex: 2, targetIndex: 0) == 0, "move up")
expect(AudioSourceReorder.destinationOffset(sourceIndex: 1, targetIndex: 1) == nil, "same row")
```

- [ ] Run the compiled test and verify it fails because `AudioSourceReorder` is missing:

```bash
xcrun swiftc -parse-as-library Models/Profile.swift Models/Dictionary.swift script/test_audio_source_reorder.swift -o /tmp/test_audio_source_reorder && /tmp/test_audio_source_reorder
```

- [ ] Implement the audio-scoped helper without accepting generic text payloads:

```swift
enum AudioSourceReorder {
    private static let payloadPrefix = "hoshi-audio-source:"

    static func payload(for audioSourceID: String) -> String { payloadPrefix + audioSourceID }
    static func audioSourceID(from payload: String) -> String? {
        guard payload.hasPrefix(payloadPrefix) else { return nil }
        let id = String(payload.dropFirst(payloadPrefix.count))
        return id.isEmpty ? nil : id
    }
    static func destinationOffset(sourceIndex: Int, targetIndex: Int) -> Int? {
        guard sourceIndex != targetIndex else { return nil }
        return targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
    }
}
```

- [ ] Re-run the focused test and require a clean pass.

### Task 2: Audio settings drag interaction

**Files:**
- Modify: `Features/Settings/AudioView.swift`
- Modify: `script/test_native_settings_navigation_contract.swift`

- [ ] Add failing contract assertions for `audioSourceReorderHandle()`, whole-row `.draggable(AudioSourceReorder.payload(for: source.id))`, audio-specific `.dropDestination`, destination highlighting, and mutation of `userConfig.audioSources`.
- [ ] Run `swift script/test_native_settings_navigation_contract.swift` and verify it fails on the missing Audio interaction.
- [ ] Add `dropTargetAudioSourceID`, place a leading `line.3.horizontal` handle in every source row, and attach a control-free preview plus whole-row draggable/drop destination modifiers.
- [ ] Add `reorderAudioSource(_:onto:)` that resolves indices, calls `AudioSourceReorder.destinationOffset`, and moves `userConfig.audioSources` inside a short snappy animation.
- [ ] Re-run the contract and focused logic tests and require clean passes.

### Task 3: Preserve the local source position

**Files:**
- Modify: `Core/UserConfig.swift`
- Modify: `script/test_native_settings_navigation_contract.swift`

- [ ] Add a failing source contract that requires `syncLocalAudioSource()` to capture the existing canonical/legacy local source and index before removal, preserve `isEnabled`, and reinsert at the bounded prior index.
- [ ] Implement normalization so a missing newly enabled local source starts at index zero, while an existing local source retains its position across launch and setting synchronization.
- [ ] Run both focused tests and confirm they pass.

### Task 4: Documentation and verification

**Files:**
- Modify: `docs/CHANGELOG.md`

- [ ] Add one Unreleased user-facing entry for persistent Audio source drag ordering.
- [ ] Run:

```bash
xcrun swiftc -parse-as-library Models/Profile.swift Models/Dictionary.swift script/test_audio_source_reorder.swift -o /tmp/test_audio_source_reorder && /tmp/test_audio_source_reorder
swift script/test_native_settings_navigation_contract.swift
git diff --check
./script/build_and_run.sh --verify
```

- [ ] Confirm the exact DerivedData Light app with bundle ID `moe.shishamo.hoshi` is running. Do not commit unless the user separately authorizes it.
