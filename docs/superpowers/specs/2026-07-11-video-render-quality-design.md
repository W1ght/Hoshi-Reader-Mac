# Video Render Quality Design

## Goal

Make Niratan's Video playback render at the display's physical pixel density, preserve color precision across SDR and HDR displays, and pace frame presentation against the active display without changing playback, subtitle, lookup, mining, or window semantics.

## Scope

The work is split into three independently verifiable stages:

1. Retina and framebuffer correctness.
2. SDR/HDR color-output correctness.
3. Display-linked frame pacing.

The stages are implemented and validated in order. A later stage must not obscure a regression in an earlier stage.

## Stage 1: Retina and Framebuffer Correctness

`HSMpvOpenGLView` remains the narrow `NSViewRepresentable` boundary. Its owned `HSMpvOpenGLLayer` must use the hosting window's current `backingScaleFactor` as `contentsScale`, request a best-resolution OpenGL surface, and refresh the scale when the view moves to a window or the window's backing properties change.

The OpenGL framebuffer handed to libmpv must match the view's backing-pixel dimensions, not its logical-point dimensions. A 2x 800-by-450 point surface therefore renders into a 1600-by-900 framebuffer. A 1x display remains unchanged.

Pixel-format creation should request the existing mpv/IINA-compatible 10-bit-capable half-float context first and fall back to the current accelerated 8-bit context when unavailable. The selected framebuffer depth is passed to `MPV_RENDER_PARAM_DEPTH`; fallback is non-fatal.

Scale changes force exactly one fresh render and do not recreate the playback engine, detach the render context, mutate the video window frame, or interfere with native full-screen transitions.

## Stage 2: Color and HDR Output

SDR output uses the active screen's `NSColorSpace`. The display ICC profile is provided to libmpv through `MPV_RENDER_PARAM_ICC_PROFILE`, then `icc-profile-auto` is enabled. Moving the player between displays refreshes both the layer color space and the render-context ICC profile.

The OpenGL surface advertises Extended Dynamic Range capability. HDR media may promote the layer to an appropriate EDR color space only when the existing Video HDR preference is enabled and the active display supports EDR. Disabling HDR returns the layer and mpv target options to the SDR/ICC path.

The existing HDR preference remains the user-visible control. No new setting or localization is added. HDR peak computation remains an enhancement toggle; automatic SDR ICC correctness is always enabled because it is display calibration rather than a stylistic effect.

Missing ICC data, unsupported HDR primaries, or lack of EDR support falls back to calibrated SDR without stopping playback or surfacing a playback error.

## Stage 3: Display-Linked Frame Pacing

The render host owns one `CVDisplayLink` bound to its current display. It reports the active display refresh rate to mpv through `display-fps-override` and calls `mpv_render_context_report_swap` from the display-link cadence rather than immediately after every `glFlush`.

The display link follows screen changes, starts only while a render context is attached, and stops before the render context is freed. Failure to create or rebind a display link falls back to the existing immediate swap reporting so playback remains available.

This stage changes presentation timing only. It does not enable interpolation, alter playback speed, or introduce frame-generation shaders.

## Boundaries and Non-Goals

- Keep all libmpv and OpenGL details inside `Features/Video/Playback/`.
- Keep SwiftUI and `PlaybackEngine` free of OpenGL, ICC, and display-link APIs.
- Do not replace the current OpenGL path with Metal in this task.
- Do not add sharpening, upscaling shaders, debanding profiles, user mpv configuration, or AI enhancement.
- Do not change subtitle overlay rendering, popup lookup, screenshots, audio extraction, mining metadata, aspect-ratio persistence, or full-screen window identity.
- Light builds must continue to exclude libmpv and all Video implementation.

## Error Handling

Framebuffer and color upgrades are capability-based. Each optional capability falls back narrowly:

- 10-bit pixel format failure falls back to accelerated 8-bit.
- ICC profile absence falls back to the screen color space without ICC transformation.
- EDR/HDR incompatibility falls back to SDR tone mapping.
- Display-link failure falls back to immediate swap reporting.

Only failure to create any accelerated OpenGL context remains a playback initialization error.

## Verification

Automated contracts must prove:

- the render host tracks `backingScaleFactor` and backing-property changes;
- the layer requests high-resolution output;
- 10-bit pixel-format selection has an explicit 8-bit fallback;
- ICC is supplied through the libmpv render API before enabling automatic ICC handling;
- HDR/EDR state returns cleanly to SDR;
- display-link teardown precedes render-context teardown;
- Light source and bundle contracts remain free of Video/libmpv leakage.

Build and runtime validation must cover:

- Light build and exact-path launch verification;
- Video build and exact-path launch verification;
- 1x and 2x framebuffer dimensions;
- moving the window between displays with different scale factors;
- windowed and native full-screen transitions;
- paused-frame sharpness and moving playback;
- SDR 8-bit, SDR 10-bit, and HDR 10-bit media where fixtures are available;
- screenshot capture, ambient preview, subtitle overlay, lookup popup, and mining capture smoke checks.

If 1x/2x multi-display hardware or HDR media/display validation is unavailable, completion notes must state the uncovered scenarios explicitly.

## Success Criteria

- On a 2x display, libmpv receives a framebuffer whose width and height equal the view's backing-pixel dimensions.
- Paused SDR frames no longer receive an additional Core Animation upscale.
- A failed 10-bit, ICC, EDR, or display-link capability does not prevent playback.
- Full-screen, render attachment, screenshot/mining, and Light/Video bundle contracts remain intact.
- No default sharpening or subjective image-style processing is introduced.
