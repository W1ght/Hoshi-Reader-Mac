# Anki Media Mining Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reliably attach book covers and Video audio clips to Anki cards, set the Lapis sentence-audio default, and remove the special anime-card settings UI.

**Architecture:** Keep media attachment in the existing `MiningContext` and `AnkiManager` pipeline. Add a narrow Objective-C++ bundled-libmpv encoder used asynchronously by Swift, and fail before AnkiConnect when a required mapped video clip is unavailable.

**Tech Stack:** Swift, SwiftUI, Objective-C++, libmpv, AnkiConnect, shell/Swift contract tests.

---

### Task 1: Lock expected mappings and UI behavior

**Files:**
- Modify: `script/test_anki_field_templates.swift`
- Modify: `script/test_video_anime_mining_contract.swift`

- [ ] Add a Lapis `SentenceAudio == {sasayaki-audio}` assertion and assertions that the anime-card section/preset helpers are absent while manual Video handlebars remain.
- [ ] Run the two tests and confirm they fail against the current implementation.
- [ ] Remove `videoAnimeCardSection` and its private preset helpers from `Features/Settings/AnkiView.swift`.
- [ ] Add the Lapis mapping to `Models/Anki.swift`, rerun both tests, and confirm they pass.

### Task 2: Restore Reader book-cover context

**Files:**
- Modify: `NativeMac/NativeReaderView.swift`
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] Add a static regression assertion requiring the Reader popup to pass `model.coverURL`.
- [ ] Run the contract and confirm it fails.
- [ ] Replace the Reader popup's nil cover with `model.coverURL` and rerun the contract.

### Task 3: Export subtitle audio with bundled libmpv

**Files:**
- Modify: `Features/Video/Playback/HSMpvClient.h`
- Modify: `Features/Video/Playback/HSMpvClient.mm`
- Modify: `Features/Video/Playback/VideoAudioClipExporter.swift`
- Modify: `Features/Video/Playback/MpvPlayerEngine.swift`
- Modify: `script/test_video_audio_export.swift`

- [ ] Extend the audio-export contract to require an audio track ID and the bundled-libmpv bridge, and confirm the current implementation fails.
- [ ] Add a synchronous isolated libmpv encoder bridge that selects `aid`, disables video/subtitles, writes mono AAC/M4A, waits for `MPV_EVENT_END_FILE`, and validates the output.
- [ ] Call the bridge from `Task.detached`, passing the selected audio track from `MpvPlayerEngine`; remove AVFoundation from the exporter.
- [ ] Compile and export a non-empty clip from the reported MKV into `/tmp`.

### Task 4: Apply subtitle timing and prevent incomplete cards

**Files:**
- Modify: `Models/Anki.swift`
- Modify: `Features/Video/VideoMiningCoordinator.swift`
- Modify: `Core/AnkiManager.swift`
- Modify: `script/test_video_media_mining.swift`
- Modify: `script/test_video_anime_mining_contract.swift`

- [ ] Add failing assertions for 120 ms padding, subtitle-delay adjustment, duration clamping, retained export errors, and mapped-audio preflight.
- [ ] Add a pure clip-range resolver and store an optional audio export error in `VideoMiningContext`.
- [ ] Catch export failures in the coordinator and make `AnkiManager` return failure before its AnkiConnect request when `{video-audio-clip}` is mapped but no clip exists.
- [ ] Rerun the focused media-mining tests.

### Task 5: Align user-facing documentation and verify variants

**Files:**
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Modify: `docs/TODO.md`
- Modify: `docs/CHANGELOG.md`
- Modify only other truth-source documents whose preset description becomes false.

- [ ] Remove claims that the app provides a Video anime-card preset and document manual placeholder mapping plus bundled-libmpv clip export.
- [ ] Run focused tests and `./script/verify_video_variant_contract.sh`.
- [ ] Run `./script/build_and_run.sh --verify`, then `./script/build_and_run.sh --video --verify`, leaving the exact Video build running.
- [ ] Report that real Anki success/duplicate/failure card writes were not performed without permission.
