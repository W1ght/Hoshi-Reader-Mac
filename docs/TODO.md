# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-19

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current Catalyst-based GitHub release. The next release line builds the single native macOS target, removes all code signatures, and publishes an unnotarized DMG with checksum.
- Reader: the native content layer uses the complete GeometryReader viewport, extends into the top safe area to avoid wasting the titlebar band, stays out of the leading/trailing rounded-corner safe areas, applies only user-selected Reader padding, and consumes a final partial page before changing chapters, matching the `v0.5.0` Catalyst layout semantics without fixed side masks or chrome-derived text insets; Reader navigation structure remains a high-risk area.
- Reader validation: the misleading generated-fixture/Debug Lab/screenshot-baseline pipeline has been removed. Lightweight contract checks remain, but visual Reader claims must be validated with real EPUBs in the exact `moe.shishamo.hoshi` build.
- Mac native migration: target, app identity, UIKit/Catalyst branches, ShareExtension coupling, legacy Reader wrappers, build scripts, and DMG workflow have moved to the single native `Hoshi Reader` App.
- Native open routing: Finder document opens and `hoshi://search` / `hoshi://open` requests now route through the native sidebar into the existing bookshelf import and dictionary search surfaces.
- Interactive native check: earlier Computer Use observations made through the ambiguous app name `Hoshi Reader` are invalid because the tool opened the old `/Applications/Hoshi Reader.app` (`de.manhhao.hoshi`). Native UI behavior must be revalidated against the exact DerivedData product with bundle id `moe.shishamo.hoshi`; no affected Reader safe-area UI claim remains accepted from that run.
- Native Reader image preview: SVG fixture images now render through an embedded WebKit document with contain sizing, avoiding the cropping and broken local-file access seen with `NSImage` and direct file references.
- AnkiConnect: the local API v6 endpoint, connected settings state, and read-only deck/model refresh succeed while preserving the selected `Lapis` deck/model. Card creation success/duplicate/failure paths remain intentionally untested because they mutate the user's Anki collection.
- Upgrade compatibility: the earlier isolated Catalyst-to-native replacement test used the former `de.manhhao.hoshi` identity. It proves file-layout compatibility for that build, but no longer proves `UserDefaults` continuity after the active App moved to `moe.shishamo.hoshi`. Books, sidecars, dictionaries, and Anki JSON remain in shared Application Support paths; the Google Keychain service intentionally stays legacy-compatible. The old defaults domain, Google Drive defaults fallback/folder IDs, and real-account token continuity still require an explicit non-destructive migration and isolated validation.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.
- Video variants: the native target has Light (`Debug`/`Release`) and Video (`Debug-Video`/`Release-Video`) configurations. Light excludes Video/libmpv; Video provides local playback, SRT/VTT overlay, shared popup/nested lookup/local word audio, and video-specific Anki mining fields.
- Video playback controls now include pointer-move show plus short-delay, app-inactive, and pointer-exit auto-hide for the playback chrome, an IINA-like compact draggable control surface, single-click play/pause, double-click native fullscreen, same-folder episode selection, previous/next and configurable EOF auto-advance, playback speed shortcuts, volume/mute shortcuts, subtitle previous/next seek, subtitle visibility and track cycling, subtitle timing, video/audio/subtitle track selection, visible/full-shortcut native fullscreen, optional per-file position restore, and a configurable shortcut seek interval. The Video detail stays alive across sidebar section switches so playback can continue while Bookshelf, Dictionary, or Settings is selected; Video shortcuts are active only while the Video section is visible. Embedded text subtitle tracks use the interactive Hoshi overlay; image subtitles remain mpv-rendered.
- App bundle identity is now `moe.shishamo.hoshi` for both Light and Video variants. Google Drive keychain service intentionally keeps the legacy `de.manhhao.hoshi.google-drive` service string for token continuity.
- Video subtitle import and transcript loading were validated with a real Documents video plus a 797 KB SRT. Video open no longer blocks the main actor on same-folder playlist scanning, external subtitle parsing prepares off-main, mpv `sub-add` failure is retried with a file URL and no longer blocks the Hoshi overlay, and the transcript panel renders only the current time-neighborhood instead of laying out the entire subtitle file. The Video surface accepts dropped media and SRT/VTT files through the same primary video/subtitle import path as the picker controls.
- Video subtitle appearance controls set Hoshi-owned text subtitle font and size, defaulting to asbplayer-style system font and 36 px size. Subtitle mask controls can blur or hide text subtitles until pointer hover. These settings are shared between Video Settings and the playback inspector and remain text-only overlay effects without adding a subtitle background frame.
- Video subtitle mining now follows the anime-card path: pressing Add to Anki captures the current video frame and selected subtitle time-range audio, sends those media files through existing AnkiConnect picture/audio fields when `{video-screenshot}` and `{video-audio-clip}` are mapped, records the attempt in mining history, and exposes an Anki Settings helper for common video/anime card field mappings.
- Video release: packaging and GitHub Actions produce Light and Video DMGs with the same bundle id and data paths; bundle checks require universal dylibs and reject Homebrew paths.
- Local Video debug launches re-sign every embedded libmpv dylib and verify the complete App bundle before opening it. This prevents the observed dyld termination where `libharfbuzz.0.dylib` reached an invalidly signed `libgraphite2.3.dylib`; the attached crash was from the superseded `de.manhhao.hoshi` build, not a shortcut handler stack.

## Next Actions

- Decide whether a future release should add Developer ID signing and notarization; the current approved pipeline intentionally remains unsigned.
- Keep Reader visual validation centered on actual EPUB data; do not reintroduce fixture or pixel-baseline automation unless it can reproduce real-book failures without mutating the Reader state being measured.
- Validate Google Drive auth on native macOS with a real Google account and callback flow.
- Validate AnkiConnect card creation success, duplicate, and failure feedback with a disposable deck or explicit approval.
- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- Extend Reader visual validation beyond the current real-EPUB vertical/horizontal and paginated/continuous checks: cover resized/full-screen windows, image-heavy pages, chapter boundaries, lookup popup stacks, and Sasayaki highlight restore in the exact `moe.shishamo.hoshi` build.
- Design and validate a one-time, non-destructive migration from the legacy `de.manhhao.hoshi` defaults domain to `moe.shishamo.hoshi`; preserve current-domain values, migrate only known keys, and cover Google Drive fallback/folder metadata without clearing tokens.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.
- Manually verify video playback, seek, compact draggable playback chrome pointer-reveal/idle-hide/window-exit-hide behavior, single-click play/pause, double-click fullscreen, sidebar section switching while playback continues, video/subtitle drag-and-drop, window/page lifecycle, subtitle click coordinates, subtitle font/size appearance changes, subtitle mask blur/transparent hover reveal, nested popup, local audio, anime-card screenshot/audio mining, mining-history sidebar behavior, and disposable-deck Anki success/duplicate/failure before shipping the Video variant. Primary SRT import and transcript-list performance have a real UI smoke test, but drag-and-drop, playback chrome dragging, subtitle appearance/mask hover, auto-hide feel, video media attachments, and Anki state transitions still need a disposable-deck/manual UI pass.
- Evaluate a Metal render path before the deprecated macOS OpenGL API becomes unavailable; the current libmpv render bridge is intentionally narrow.

## Blockers

- Google Drive auth validation requires a real account/client configuration and callback completion.
- Hardware-specific checks, such as controllers or external audio setups, may need user confirmation.

## Validation Entry Points

```bash
./script/build_and_run.sh --verify
./script/build_and_run_native.sh --open-url 'hoshi://search?text=星'
./script/verify_native_release_contract.sh
./script/verify_native_upgrade_contract.sh
./script/audit_native_upgrade_data.sh
./script/verify_reader_harness.sh
./script/verify_video_harness.sh
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
swift script/test_color_hex_codec.swift
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_css_editor_snippets.swift
swiftc NativeMac/NativeFullscreenImageDocument.swift script/test_native_fullscreen_image_document.swift -o /tmp/test_native_fullscreen_image_document && /tmp/test_native_fullscreen_image_document
```

`./script/build_and_run.sh --verify` is valid only when it prints the verified `moe.shishamo.hoshi` bundle path and a PID whose executable is inside that same `.app`. A same-name process is not sufficient evidence.

For release-specific work, also inspect:

```bash
gh run list --repo W1ght/Hoshi-Reader-Mac --workflow release-mac.yml --limit 5
```
## Video playback alignment

- [x] Add chapters, audio timing, file/A-B loops, aspect ratio, rotation and transcript seek.
- [x] Reuse AnkiConnect media upload for on-demand video screenshots and subtitle-range audio clips.
- [x] Add a video/anime card field helper and make subtitle mining capture current-frame screenshots plus subtitle-range audio before AnkiConnect submission.
- [ ] Re-plan secondary/bilingual subtitles after primary subtitle import, transcript navigation, lookup and mining are fully validated.
- [ ] Keep embedded secondary subtitle extraction, ASS layout fidelity, study statistics and sync as later work.
