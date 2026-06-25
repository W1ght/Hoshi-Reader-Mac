# Video Library Smart Collections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-pass non-destructive smart collection system to the Video library.

**Architecture:** Extend the existing `VideoLibraryCollection` model with manual and smart variants while preserving old catalog decoding. Evaluate rules in `VideoLibraryViewModel` from existing rows, then add focused SwiftUI controls in the existing inspector.

**Tech Stack:** Swift, SwiftUI, Codable JSON catalog persistence, existing Video-only build flags, no new runtime dependencies.

---

### Task 1: Collection Model And Store

**Files:**
- Modify: `Features/Video/VideoLibraryStore.swift`
- Test: `script/test_video_library_store.swift`

- [ ] Add failing store tests for smart collection persistence, legacy manual decode, and stale-path cleanup that does not delete smart rules.
- [ ] Run `xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/VideoMediaTypes.swift Features/Video/VideoLibraryStore.swift script/test_video_library_store.swift -o /tmp/test_video_library_store && /tmp/test_video_library_store`; expect compile or assertion failure before implementation.
- [ ] Add `VideoLibraryCollectionKind`, `VideoLibrarySmartRule`, and optional `smartRules` to `VideoLibraryCollection`; decode old collections as manual.
- [ ] Add store methods for creating/updating smart collections while keeping existing manual collection methods stable.
- [ ] Re-run the store test command; expect pass.

### Task 2: View Model Rule Evaluation

**Files:**
- Modify: `Features/Video/VideoLibraryViewModel.swift`
- Test: `script/test_video_library_view_model.swift`

- [ ] Add failing view-model tests for smart collection matching by filename/path/folder/tag/subtitle/playback state and for preview sample output.
- [ ] Run the view-model compile command from `docs/TODO.md`; expect failure before implementation.
- [ ] Add matching helpers and preview methods to `VideoLibraryViewModel`.
- [ ] Update Collections sections to resolve manual paths and smart rules.
- [ ] Re-run the view-model test command; expect pass.

### Task 3: SwiftUI First Pass

**Files:**
- Modify: `Features/Video/VideoLibraryView.swift`
- Modify: `Localizable.xcstrings`
- Test: `script/test_video_library_contract.swift`

- [ ] Add failing contract assertions for smart collection UI labels and no Python/Node/imported parser dependency.
- [ ] Run `swift script/test_video_library_contract.swift`; expect failure before implementation.
- [ ] Add inspector controls for creating a smart collection with one or more simple rules and a preview list.
- [ ] Add collection badges/copy that distinguish manual and smart collections.
- [ ] Add required localized strings in English and Chinese.
- [ ] Re-run `swift script/test_video_library_contract.swift`; expect pass.

### Task 4: Verification

**Files:**
- Modify docs only if implementation changes durable validation state.

- [ ] Run store, view-model, and contract tests.
- [ ] Run `./script/verify_video_variant_contract.sh`.
- [ ] Run `./script/build_and_run.sh --video --verify` and confirm the exact built `moe.shishamo.hoshi` Video app path.
- [ ] If time permits, run `./script/build_and_run.sh --verify` to prove Light still launches without Video/libmpv leakage.
