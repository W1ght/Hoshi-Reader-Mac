# Video Render Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Repository policy forbids commits unless the user explicitly requests one, so this plan does not commit automatically.

**Goal:** Render Video at physical display resolution, preserve SDR/HDR color precision, and pace swap reporting against the active macOS display.

**Architecture:** Keep the existing SwiftUI `NSViewRepresentable` and libmpv boundaries. Extend `HSMpvOpenGLView`/`HSMpvOpenGLLayer` with backing-scale, pixel-format, display-color, and display-link ownership while `HSMpvClient` supplies ICC/HDR mpv configuration; capability failures fall back to the current 8-bit SDR/immediate-swap behavior.

**Tech Stack:** Swift 6, Objective-C++, AppKit, QuartzCore, CoreVideo, OpenGL 3.2, libmpv 0.38 render API, standalone Swift source-contract tests, Xcode Light/Video schemes.

## Global Constraints

- Native macOS 26.0+ is the only target.
- Light builds must not link, copy, or runtime-discover Video/libmpv.
- Do not recreate the Video window, playback engine, or render context during scale/color/screen changes.
- Do not change subtitle, lookup, mining, screenshot, audio extraction, aspect-ratio, or full-screen semantics.
- Do not add sharpening, AI upscaling, shaders, user mpv configuration, or a new user-visible setting.
- Use `apply_patch` for hand edits and do not commit, push, tag, or release.

---

### Task 1: Retina and 10-bit framebuffer correctness

**Files:**
- Modify: `script/test_video_render_bridge_contract.swift`
- Modify: `Features/Video/Playback/HSMpvClient.mm`

**Interfaces:**
- Consumes: existing `HSMpvOpenGLView`, `HSMpvOpenGLLayer`, and `MPV_RENDER_PARAM_DEPTH` path.
- Produces: `updateBackingConfiguration`, a high-depth pixel-format attempt with 8-bit fallback, and a backing-pixel-sized `CAOpenGLLayer` surface.

- [x] **Step 1: Add failing Retina and pixel-depth contracts**

Add assertions equivalent to:

```swift
require(clientImpl.contains("wantsBestResolutionOpenGLSurface = YES"),
        "video render host should request a best-resolution OpenGL surface")
require(clientImpl.contains("backingScaleFactor")
        && clientImpl.contains("contentsScale")
        && clientImpl.contains("NSWindowDidChangeBackingPropertiesNotification"),
        "video render host should follow the active window backing scale")
require(clientImpl.contains("kCGLPFAColorSize")
        && clientImpl.contains("kCGLPFAColorFloat")
        && clientImpl.contains("kCAContentsFormatRGBA16Float")
        && clientImpl.contains("_bufferDepth = 16")
        && clientImpl.contains("_bufferDepth = 8"),
        "video render host should prefer a half-float framebuffer and fall back to 8-bit")
```

- [x] **Step 2: Run the contract and verify RED**

Run: `swift script/test_video_render_bridge_contract.swift`

Expected: failure naming the missing best-resolution/backing-scale contract before any production edit.

- [x] **Step 3: Implement backing-scale lifecycle**

In `HSMpvOpenGLView`, set `wantsBestResolutionOpenGLSurface = YES`, observe only the current window's `NSWindowDidChangeBackingPropertiesNotification`, and route `initWithFrame:`, `viewDidMoveToWindow`, notification callbacks, and `layout` through one `updateBackingConfiguration` method:

```objc
CGFloat scale = self.window ? self.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
self.openGLLayer.contentsScale = MAX(scale, 1.0);
[self requestForcedRender];
```

Remove the old observer before changing windows and in `dealloc`. Do not mutate the window frame or render-context identity.

- [x] **Step 4: Implement 10-bit-first pixel-format fallback**

Try accelerated OpenGL 3.2 with `kCGLPFAColorSize, 64, kCGLPFAColorFloat` first. On failure, retry the existing accelerated 8-bit attributes. Set `_bufferDepth` to `16` only for the high-depth format and assign `contentsFormat = kCAContentsFormatRGBA16Float`; otherwise retain depth `8`.

- [x] **Step 5: Run focused verification GREEN**

Run:

```bash
swift script/test_video_render_bridge_contract.swift
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
```

Expected: all three scripts exit 0.

---

### Task 2: SDR ICC and opt-in HDR/EDR output

**Files:**
- Modify: `script/test_video_render_bridge_contract.swift`
- Modify: `Features/Video/Playback/HSMpvClient.mm`
- Modify: `script/test_video_settings_contract.swift`

**Interfaces:**
- Consumes: attached `HSMpvOpenGLView`, observed `video-params`, and existing `setHDREnhancementEnabled:` preference path.
- Produces: `applyDisplayColorConfiguration`, render-context ICC injection, SDR reset, and HDR EDR promotion with safe fallback.

- [x] **Step 1: Add failing color-pipeline contracts**

Require all of the following source behavior:

```swift
require(clientImpl.contains("MPV_RENDER_PARAM_ICC_PROFILE")
        && clientImpl.contains("icc-profile-auto"),
        "SDR output should provide the active display ICC profile to libmpv")
require(clientImpl.contains("wantsExtendedDynamicRangeOpenGLSurface = YES")
        && clientImpl.contains("wantsExtendedDynamicRangeContent"),
        "the render host should support EDR while keeping content state explicit")
require(clientImpl.contains("target-prim")
        && clientImpl.contains("target-trc")
        && clientImpl.contains("kCGColorSpaceITUR_2100_PQ"),
        "HDR output should configure mpv and the layer for PQ EDR")
require(clientImpl.contains("applySDRDisplayColorConfiguration"),
        "HDR disable/fallback should restore calibrated SDR")
```

Keep the settings contract requiring the existing HDR preference default to remain `false`.

- [x] **Step 2: Run contracts and verify RED**

Run:

```bash
swift script/test_video_render_bridge_contract.swift
swift script/test_video_settings_contract.swift
```

Expected: render bridge contract fails on missing ICC/EDR behavior while settings contract still passes.

- [x] **Step 3: Implement display color refresh boundary**

Give `HSMpvOpenGLView` one private display-configuration callback. Trigger it from the same window/screen/backing lifecycle used by Stage 1. In `HSMpvClient.attachToView`, install the callback and immediately configure the active screen; clear it before detach.

- [x] **Step 4: Implement calibrated SDR path**

Use `screen.colorSpace` with sRGB fallback for the layer. While the OpenGL context is current and locked, pass `NSColorSpace.iccProfileData` to `mpv_render_context_set_parameter` as `MPV_RENDER_PARAM_ICC_PROFILE`, then enable `icc-profile-auto`. Reset EDR content to false and mpv `target-prim`, `target-trc`, `target-peak`, and `tone-mapping` to automatic SDR-compatible values. Missing ICC data quietly keeps the layer color space and disables automatic ICC transformation.

- [x] **Step 5: Implement opt-in HDR/EDR promotion and SDR restoration**

Parse `primaries` and `gamma` from the existing `video-params` node. When the existing HDR preference is enabled, gamma is PQ/HLG, primaries are BT.2020 or Display-P3, and the screen exposes EDR headroom, set the layer to the matching PQ color space, enable `wantsExtendedDynamicRangeContent`, disable ICC auto, and configure mpv target primaries/TRC/peak. Otherwise call the single SDR restoration method. Re-run configuration when media params, HDR preference, screen, or backing properties change.

- [x] **Step 6: Run focused tests GREEN**

Run:

```bash
swift script/test_video_render_bridge_contract.swift
swift script/test_video_settings_contract.swift
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Playback/PlaybackEngine.swift Features/Video/VideoPlaylist.swift Features/Video/VideoInspectorState.swift Features/Video/VideoPlaybackHistoryStore.swift Features/Video/VideoPlayerViewModel.swift script/test_video_advanced_playback.swift -o /tmp/hoshi-test-video-advanced-playback && /tmp/hoshi-test-video-advanced-playback
```

Expected: all exit 0.

---

### Task 3: Display-linked swap pacing with immediate fallback

**Files:**
- Modify: `script/test_video_render_bridge_contract.swift`
- Modify: `Features/Video/Playback/HSMpvClient.mm`

**Interfaces:**
- Consumes: current screen display ID, `mpv_render_context`, render attach/detach lifecycle.
- Produces: one `CVDisplayLink` owned by the render layer and `display-fps-override` configuration owned by `HSMpvClient`.

- [x] **Step 1: Add failing display-link lifecycle contracts**

Add assertions equivalent to:

```swift
require(clientImpl.contains("CVDisplayLinkCreateWithActiveCGDisplays")
        && clientImpl.contains("CVDisplayLinkSetCurrentCGDisplay")
        && clientImpl.contains("CVDisplayLinkSetOutputCallback"),
        "video render pacing should follow the active display")
require(clientImpl.contains("display-fps-override"),
        "libmpv should receive the active display refresh rate")
require(clientImpl.contains("stopDisplayLink")
        && clientImpl.range(of: "[view stopDisplayLink]")!.lowerBound
           < clientImpl.range(of: "mpv_render_context_free(contextToFree)")!.lowerBound,
        "display link should stop before the render context is freed")
require(clientImpl.contains("usesImmediateSwapReporting"),
        "display-link failure should preserve immediate swap reporting")
```

- [x] **Step 2: Run the render contract and verify RED**

Run: `swift script/test_video_render_bridge_contract.swift`

Expected: failure naming the missing CoreVideo display-link path.

- [x] **Step 3: Implement render-layer display link**

Create one `CVDisplayLink` in the render layer, install a C callback that reads the currently attached render context and calls `mpv_render_context_report_swap`, bind it to `NSScreenNumber`, and start it only after a render context is attached. Stop it before clearing/freeing that context and release it in layer teardown.

- [x] **Step 4: Preserve immediate fallback and set refresh rate**

If creation, callback installation, display binding, or start fails, keep `usesImmediateSwapReporting = YES` so the existing post-`glFlush` report remains active. On successful display-link start, disable immediate reporting. Calculate actual refresh from `CVDisplayLinkGetActualOutputVideoRefreshPeriod`, fall back to nominal refresh, and set libmpv `display-fps-override` only for a finite positive value.

- [x] **Step 5: Run playback/render contracts GREEN**

Run:

```bash
swift script/test_video_render_bridge_contract.swift
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
swift script/test_video_player_interactions_contract.swift
```

Expected: all exit 0.

---

### Task 4: Source-of-truth documentation and complete verification

**Files:**
- Modify: `docs/TODO.md`
- Modify: `docs/ARCHITECTURE_REFACTORING.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/superpowers/plans/2026-07-11-video-render-quality.md`

**Interfaces:**
- Consumes: completed render implementation and fresh verification evidence.
- Produces: accurate user-visible changelog, architecture state, remaining manual risks, and checked plan steps.

- [x] **Step 1: Update truth-source docs**

Record that Video now renders in backing pixels, attempts a half-float framebuffer with 8-bit fallback, applies calibrated SDR ICC, supports opt-in EDR HDR, and uses display-linked swap pacing with immediate fallback. Keep the existing Metal migration TODO because OpenGL remains deprecated.

- [x] **Step 2: Run complete focused contracts**

Run:

```bash
swift script/test_video_render_bridge_contract.swift
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
swift script/test_video_settings_contract.swift
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Playback/PlaybackEngine.swift Features/Video/VideoPlaylist.swift Features/Video/VideoInspectorState.swift Features/Video/VideoPlaybackHistoryStore.swift Features/Video/VideoPlayerViewModel.swift script/test_video_advanced_playback.swift -o /tmp/hoshi-test-video-advanced-playback && /tmp/hoshi-test-video-advanced-playback
swift script/test_video_player_interactions_contract.swift
./script/verify_video_variant_contract.sh
```

Expected: every command exits 0.

- [x] **Step 3: Build and launch exact Light app**

Run: `./script/build_and_run.sh --instance render-quality-light --verify`

Expected: build succeeds; bundle ID is `moe.shishamo.hoshi`; reported running executable matches this instance's DerivedData path; no libmpv is linked or bundled.

- [x] **Step 4: Build and launch exact Video app**

Run: `./script/build_and_run.sh --video --instance render-quality-video --verify`

Expected: build succeeds; bundle ID and running executable path match the exact Video artifact.

- [ ] **Step 5: Perform available runtime smoke checks**

Use the exact Video artifact and a non-destructive local fixture to check windowed/full-screen transitions, pause/seek, subtitle overlay, popup, screenshot, ambient preview, and render stability. Record unavailable 1x/2x multi-display or HDR-display scenarios rather than claiming them.

Not completed automatically: no disposable video fixture and no isolated 1x/2x or HDR display environment were available without touching the user's shared Video state.

- [x] **Step 6: Review final diff and leave changes uncommitted**

Run:

```bash
git diff --check
git status --short --branch
git diff -- Features/Video/Playback/HSMpvClient.mm script/test_video_render_bridge_contract.swift docs/TODO.md docs/ARCHITECTURE_REFACTORING.md docs/CHANGELOG.md
```

Expected: no whitespace errors; only the intended implementation, tests, specification, plan, and truth-source documentation are modified.
