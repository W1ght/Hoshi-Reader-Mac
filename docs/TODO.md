# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-17

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current Catalyst-based GitHub release. The next release line builds the single native macOS target, removes all code signatures, and publishes an unnotarized DMG with checksum.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: the deterministic fixture/Lab/scenario pipeline launches `Hoshi Reader`, restores temporary settings/bookmarks, writes Reader metrics, and captures all 10 planned scenarios. The local `macOS 27.0 / WebKit 22625` baseline is committed under `testdata/reader-baselines/macos-27.0-webkit-22625/` with a measured 12% pixel / 12-channel material-rendering tolerance.
- Mac native migration: target, app identity, UIKit/Catalyst branches, ShareExtension coupling, legacy Reader wrappers, build scripts, and DMG workflow have moved to the single native `Hoshi Reader` App.
- Native open routing: Finder document opens and `hoshi://search` / `hoshi://open` requests now route through the native sidebar into the existing bookshelf import and dictionary search surfaces.
- Interactive native check: Bookshelf and Settings sidebars expand/collapse; Light, Dark, System, and Sepia themes render correctly; grouped settings cards and segmented pickers remain legible; Dictionary accepts `星` and renders grouped results; keyboard shortcut and Sasayaki settings are present; Reader shortcut navigation, narrow/wide content, full-screen chrome, popup layout, and image tapping were exercised through Computer Use and local UI automation.
- Native Reader image preview: SVG fixture images now render through an embedded WebKit document with contain sizing, avoiding the cropping and broken local-file access seen with `NSImage` and direct file references.
- AnkiConnect: the local API v6 endpoint, connected settings state, and read-only deck/model refresh succeed while preserving the selected `Lapis` deck/model. Card creation success/duplicate/failure paths remain intentionally untested because they mutate the user's Anki collection.
- Upgrade compatibility: an unsigned `v0.5.0` Mac Catalyst build was installed and launched from an isolated location, then replaced in place by the unsigned native App with the same bundle id. The native App launched against the same isolated HOME; the fixture book, EPUB, bookmark/sidecars, dictionary config, Anki mappings, UserDefaults marker, and arbitrary upgrade marker were preserved. Real Google tokens were absent or inaccessible, so account continuity still requires external validation.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.
- Video variants: the native target has Light (`Debug`/`Release`) and Video (`Debug-Video`/`Release-Video`) configurations. Light excludes Video/libmpv; Video provides local playback, SRT/VTT overlay, shared popup/nested lookup/local word audio, and video-specific Anki mining fields.
- Video playback controls now include same-folder episode selection, previous/next and configurable EOF auto-advance, playback speed, volume/mute, subtitle timing, video/audio/subtitle track selection, visible/full-shortcut native fullscreen, optional per-file position restore, and a configurable shortcut seek interval. Embedded text subtitle tracks use the interactive Hoshi overlay; image subtitles remain mpv-rendered.
- Video subtitle import and transcript loading were validated with a real Documents video plus a 797 KB SRT. Video open no longer blocks the main actor on same-folder playlist scanning, external subtitle parsing prepares off-main, mpv `sub-add` failure is retried with a file URL and no longer blocks the Hoshi overlay, and the transcript panel renders only the current time-neighborhood instead of laying out the entire subtitle file.
- Video mining history records video subtitle mining attempts when triggered, updates each row with Anki success/duplicate/failure state, persists a bounded recent history, and exposes a fixed right sidebar that pushes the video instead of covering the picture.
- Video release: packaging and GitHub Actions produce Light and Video DMGs with the same bundle id and data paths; bundle checks require universal dylibs and reject Homebrew paths.

## Next Actions

- Decide whether a future release should add Developer ID signing and notarization; the current approved pipeline intentionally remains unsigned.
- Decide whether hosted Reader CI has a stable enough WindowServer, scale, font, macOS, and WebKit environment to publish screenshot/diff artifacts; local versioned baselines are now available, but hosted runners are not assumed pixel-stable.
- Validate Google Drive auth on native macOS with a real Google account and callback flow.
- Validate AnkiConnect card creation success, duplicate, and failure feedback with a disposable deck or explicit approval.
- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.
- Manually verify video playback, seek, window/page lifecycle, subtitle click coordinates, nested popup, local audio, mining-history sidebar behavior, and disposable-deck Anki success/duplicate/failure before shipping the Video variant. Primary SRT import and transcript-list performance have a real UI smoke test, but Anki state transitions still need a disposable-deck manual pass.
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
./script/verify_reader_ci_contract.sh
./script/verify_reader_harness.sh
./script/verify_video_harness.sh
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
python3 -m py_compile script/generate_reader_fixtures.py
bash -n script/capture_reader_regression.sh
swift script/test_color_hex_codec.swift
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_css_editor_snippets.swift
swiftc NativeMac/NativeFullscreenImageDocument.swift script/test_native_fullscreen_image_document.swift -o /tmp/test_native_fullscreen_image_document && /tmp/test_native_fullscreen_image_document
```

For release-specific work, also inspect:

```bash
gh run list --repo W1ght/Hoshi-Reader-Mac --workflow release-mac.yml --limit 5
```
## Video playback alignment

- [x] Add chapters, audio timing, file/A-B loops, aspect ratio, rotation and transcript seek.
- [x] Reuse AnkiConnect media upload for on-demand video screenshots and subtitle-range audio clips.
- [ ] Re-plan secondary/bilingual subtitles after primary subtitle import, transcript navigation, lookup and mining are fully validated.
- [ ] Keep embedded secondary subtitle extraction, ASS layout fidelity, study statistics and sync as later work.
