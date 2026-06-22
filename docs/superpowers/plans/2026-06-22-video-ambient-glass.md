# Video Ambient Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace windowed Video letterbox black with a throttled current-frame ambient Liquid Glass backdrop while preserving pure-black full screen and unchanged mining screenshots.

**Architecture:** `HSMpvClient` captures mpv's video-only `screenshot-raw` result in memory and downsamples it before returning an `NSImage` through `PlaybackEngine`. A focused `VideoAmbientBackdropModel` owns three-second throttling, cancellation and load-generation rejection, while `VideoAmbientBackdrop` renders the image/material through an even-odd letterbox mask above the unchanged opaque mpv surface. `VideoWindowChromeController` publishes full-screen state, leaving video pixels and screenshot export unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Objective-C++, libmpv client/render APIs, standalone Swift contract tests, Xcode Video/Light schemes.

---

### Task 1: Lock ambient scheduling and UI boundaries with failing tests

**Files:**
- Create: `script/test_video_ambient_backdrop.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `script/verify_video_variant_contract.sh`

- [ ] Add pure scheduling tests using a `VideoAmbientRefreshState` value that accepts loaded/playing/active/full-screen/time/generation inputs and asserts immediate load, pause and seek refresh; three-second playback throttling; no overlap; and stale-generation rejection.
- [ ] Add source contracts requiring `VideoAmbientBackdrop`, a full-screen callback owned by `VideoWindowChromeController`, an ambient preview method on `PlaybackEngine`, an in-memory `screenshot-raw` command in `HSMpvClient`, and no ambient screenshot file path.
- [ ] Add variant membership checks so the new Video files compile only through the Video boundary and Light remains free of libmpv.
- [ ] Run the new Swift test and updated contracts; verify failures identify the missing ambient types and interfaces.

### Task 2: Add in-memory mpv preview capture

**Files:**
- Modify: `Features/Video/Playback/HSMpvClient.h`
- Modify: `Features/Video/Playback/HSMpvClient.mm`
- Modify: `Features/Video/Playback/PlaybackEngine.swift`
- Modify: `Features/Video/Playback/MpvPlayerEngine.swift`

- [ ] Add `VideoAmbientPreview` with `NSImage` and media load generation, plus `captureAmbientPreview(maximumDimension:) async throws` to `PlaybackEngine` and a no-op default.
- [ ] Add an Objective-C completion API that dispatches `mpv_command_ret` with `screenshot-raw video`, validates the node map (`w`, `h`, `stride`, `format`, `data`), copies pixels before `mpv_free_node_contents`, and creates a downsampled `NSImage` without writing a file.
- [ ] Support mpv `bgr0`, `bgra`, `rgb0`, and `rgba` output explicitly; return a quiet preview error for unsupported results without touching playback error state.
- [ ] Return the guarded `_loadGeneration` with the image and bridge the completion API into Swift continuation code.
- [ ] Run the ambient contract and build the Video target to catch Objective-C++/Swift bridging errors.

### Task 3: Mask the ambient surface to letterbox pixels

**Files:**
- Create: `Features/Video/VideoAmbientBackdrop.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

- [x] Keep the mpv OpenGL surface opaque and preserve its pure-black clear path.
- [x] Add an even-odd SwiftUI mask that removes the aspect-fitted sharp-video rectangle from the ambient layer.
- [x] Add a contract that screenshot mining still calls `screenshot-to-file ... video` and does not reference the ambient SwiftUI layer.
- [x] Build and run the exact Video app, checking that video pixels remain sharp and only aspect-fit bars reveal the ambient layer.

### Task 4: Implement throttled ambient state and rendering

**Files:**
- Create: `Features/Video/VideoAmbientBackdrop.swift`
- Create: `Features/Video/VideoAmbientBackdropModel.swift`
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj`

- [ ] Implement `VideoAmbientRefreshState` as pure logic with a three-second interval, in-flight state, latest accepted generation, immediate-reason handling, and stale result rejection.
- [ ] Implement `VideoAmbientBackdropModel` as a main-actor observable owner of the latest downsampled image and a single capture task; clear it on generation changes and cancel it during full screen, inactivity and shutdown.
- [ ] Implement `VideoAmbientBackdrop`: black in full screen; otherwise scaled-to-fill image with heavy blur, reduced saturation and opacity, plus a light/dark semantic tint, `.ultraThinMaterial`, subtle border and macOS 26 glass treatment with fallback.
- [ ] Add both files to the synchronized Video target membership exceptions.
- [ ] Run the pure scheduling test and Liquid Glass contract until green.

### Task 5: Integrate window/full-screen and player lifecycle

**Files:**
- Modify: `Features/Video/VideoWindowChromeController.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`

- [ ] Make `VideoWindowChromeController` observable and update `isFullScreen` from its existing enter/exit observers; do not add duplicate window observers in the screen.
- [ ] Add one scene-owned ambient model to `VideoPlayerScreen`, render it below `MpvRenderView`, and replace the outer windowed `Color.black` with the ambient workspace surface.
- [ ] Trigger immediate refresh on successful load generation, seek completion and transition to paused; trigger throttled refresh from playback time; stop and clear on inactive/unloaded/shutdown.
- [x] Disable the ambient mask and workspace corner radius/border in full screen, leaving the opaque mpv background pure black.
- [ ] Preserve existing click, lookup, subtitle, Popup, inspector, study sidebar and chrome auto-hide layers and z-index ordering.
- [ ] Run the ambient tests, Video contracts and exact Video build.

### Task 6: Documentation and complete verification

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`

- [ ] Document windowed ambient glass, full-screen black fallback, three-second in-memory preview cadence and unchanged video-only mining screenshots.
- [ ] Compile the ambient model test with `PlaybackEngine.swift`, `VideoAmbientBackdrop.swift` and `VideoAmbientBackdropModel.swift`, then run it together with `swift script/test_video_liquid_glass_contract.swift` and the related Video playback tests.
- [ ] Run `./script/verify_video_variant_contract.sh`.
- [ ] Run `./script/build_and_run.sh --verify` and confirm the exact Light executable and `moe.shishamo.hoshi` bundle identifier.
- [ ] Run `./script/build_and_run.sh --video --verify` and confirm the exact Video executable and bundle identifier.
- [ ] In the exact Video build, verify windowed and full-screen behavior, seek/pause/load refresh, light/dark materials, inspector/sidebar, subtitle lookup/selection and two-second chrome hiding. Use only temporary local screenshot output and do not create an Anki card.
