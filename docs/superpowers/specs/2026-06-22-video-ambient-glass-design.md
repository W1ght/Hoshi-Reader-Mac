# Video Ambient Liquid Glass Design

## Goal

Bring the dedicated Video window closer to the supplied macOS subtitle-studio reference by replacing windowed letterbox black with a restrained ambient Liquid Glass treatment, while preserving a pure-black full-screen viewing mode.

## Visual Structure

- The Video window remains a single native macOS window with the existing mpv canvas, floating playback bar, inspector, and fixed study sidebar.
- In windowed mode, unused video-canvas space displays a low-resolution sample of the current video frame. The sample is scaled to fill, heavily blurred, slightly desaturated, and dimmed before a semantic system material and subtle edge tint are applied.
- The sharp mpv video remains centered at its original aspect ratio above the ambient layer. Hoshi subtitles remain a transparent overlay over the sharp video and never receive a glass or opaque background.
- The video workspace uses a restrained continuous corner radius and a thin semantic border so the video, controls, inspector, and study sidebar read as one macOS workspace rather than unrelated surfaces.
- Existing playback controls and study-list cards keep their current Liquid Glass implementation. This change aligns their surrounding canvas instead of adding another thick glass layer over them.
- In full screen, the ambient frame, material, tint, workspace radius, and border are disabled. The letterbox background becomes pure black and the video reaches the normal full-screen bounds.

## Ambient Frame Pipeline

- Add a Video-only ambient-frame API at the playback boundary. SwiftUI must not call mpv C APIs directly.
- `MpvPlayerEngine` asks `HSMpvClient` for a current video-only preview frame. The preview excludes Hoshi subtitles, controls, Popup UI, inspector, sidebar, and any ambient treatment.
- The client returns an in-memory image suitable for immediate downsampling; it must not create persistent media files or a second mpv instance.
- The UI stores only the latest downsampled ambient image. A new request never overlaps an in-flight request, and stale results from an earlier media load generation are discarded.
- Refresh immediately after a media load becomes ready, after a completed seek, and when playback pauses. While playing in windowed mode, refresh no more than once every three seconds.
- Stop periodic refresh in full screen, when the Video window is not active, after media unload, and during shutdown. Clear the previous image when switching media so the old episode cannot flash behind the new one.
- If preview capture fails, playback continues normally and the backdrop falls back to a semantic light/dark glass tint. Ambient capture errors are not shown as playback errors.

## Letterbox Mask Boundary

- Keep the libmpv/AppKit render surface opaque and unchanged. A SwiftUI even-odd mask reveals the ambient layer only in the unused area outside the aspect-fitted sharp video rectangle.
- Derive the fitted video rectangle from the in-memory preview aspect ratio and the current canvas geometry, so horizontal and vertical letterboxing use the same path without requiring transparent OpenGL output.
- When full-screen state changes, remove the ambient layer and workspace rounding together. The existing opaque mpv background remains pure black, avoiding transient desktop or glass visibility.
- The existing `VideoWindowChromeController` is the single source of full-screen state changes exposed to `VideoPlayerScreen`.

## Interaction and Existing Behavior

- Single click, double-click full screen, Shift-hover lookup, native subtitle selection, drag-and-drop, Popup positioning, inspector overlay, study sidebar resizing, and playback-control auto-hide remain unchanged.
- Opening or closing the inspector and study sidebar must not trigger a new ambient capture by itself.
- Mining screenshots and `{video-screenshot}` use mpv's video-only capture path and therefore never include the ambient backdrop, window chrome, controls, or Hoshi subtitle overlay.
- The feature has no new user-facing setting in this phase. Windowed ambient glass is enabled by default; full screen always remains black.
- Light appearance uses a brighter cool neutral material. Dark appearance uses a darker neutral material. The sampled frame contributes color but must not overpower text, controls, or the study sidebar.

## Internal Interfaces

- Add a preview-frame result type carrying the image and media-load generation.
- Extend `PlaybackEngine` with an ambient preview request that has a no-op default for non-mpv implementations.
- Extend `MpvPlayerEngine` and `HSMpvClient` with the Video-only preview capture implementation.
- Add a focused ambient-backdrop model responsible for throttling, cancellation, stale-result rejection, and the latest downsampled image.
- Add a reusable SwiftUI `VideoAmbientBackdrop` responsible only for rendering image blur, tint, material, and full-screen fallback.
- Extend `VideoWindowChromeController` to publish full-screen transitions without adding another window notification observer in `VideoPlayerScreen`.

## Performance and Failure Rules

- Only one preview capture may run at a time.
- Periodic capture cadence is three seconds and only while loaded, playing, active, and windowed.
- Downsample before storing the image used by SwiftUI; the ambient layer does not retain full-resolution frames.
- Blur and tint use system/GPU-backed rendering where available, with material fallback on older supported macOS versions.
- Preview capture failure, unsupported pixel formats, or alpha-render fallback must never stop, pause, or reload playback.
- If preview capture fails, retain the existing opaque black letterbox rather than changing playback state or exposing the desktop.

## Verification

- Unit-test refresh throttling, no-overlap behavior, stale-generation rejection, load/seek/pause immediate refresh, full-screen suspension, and failure fallback.
- Contract-test that SwiftUI does not access mpv C APIs, full-screen state comes from `VideoWindowChromeController`, and Light remains free of libmpv/runtime Video dependencies.
- Verify the exact Debug-Video app in light and dark appearance with 16:9, 4:3, and ultrawide media in both normal and full-screen windows.
- Verify play, pause, seek, episode switching, inspector, study sidebar, subtitle lookup/selection, Popup, and two-second chrome hiding.
- Compare frame pacing and CPU/GPU usage with ambient capture enabled; capture must not introduce visible stutter.
- Verify `{video-screenshot}` from disposable test data when authorized; otherwise confirm the mpv video-only path through a temporary local screenshot without creating an Anki card.
- Run the relevant Video narrow tests, `verify_video_variant_contract.sh`, Light `--verify`, and Video `--video --verify`.

## Out of Scope

- Multiple Video windows.
- A user-adjustable blur, tint, refresh-rate, or ambient-background toggle.
- Rendering native mpv subtitles instead of Hoshi's interactive subtitle overlay.
- Replacing the current inspector, study sidebar, or playback controls with the reference app's editing workflow.
- Copying the reference application's assets or layout pixel-for-pixel.
