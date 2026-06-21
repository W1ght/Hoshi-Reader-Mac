# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-20

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current Catalyst-based GitHub release. The next release line builds the single native macOS target, removes all code signatures, and publishes an unnotarized DMG with checksum.
- Reader: the native content layer uses the complete GeometryReader viewport, extends into the top safe area to avoid wasting the titlebar band, stays out of the leading/trailing rounded-corner safe areas, applies only user-selected Reader padding, and consumes a final partial page before changing chapters, matching the `v0.5.0` Catalyst layout semantics without fixed side masks or chrome-derived text insets; Reader navigation structure remains a high-risk area.
- Validation tooling: the generated-fixture/Debug Lab/screenshot-baseline pipeline, Reader/Video/shortcut aggregate harnesses, and Reader-specific CI workflow have been removed. Narrow unit/static checks remain available by concern, while Reader completion claims require real EPUB validation in the exact `moe.shishamo.hoshi` build.
- Mac native migration: target, app identity, UIKit/Catalyst branches, ShareExtension coupling, legacy Reader wrappers, build scripts, and DMG workflow have moved to the single native `Hoshi Reader` App.
- Native open routing: Finder document opens and `hoshi://search` / `hoshi://open` requests now route through the native sidebar into the existing bookshelf import and dictionary search surfaces.
- Native Bookshelf/Sasayaki: local-book context menus open the existing SRT matcher, and the native match sheet preserves the v0.5.0 information hierarchy with a centered header and shared native settings cards. Matching continues to use the existing parser, matcher, and `sasayaki_match.json` sidecar format.
- Interactive native check: earlier Computer Use observations made through the ambiguous app name `Hoshi Reader` are invalid because the tool opened the old `/Applications/Hoshi Reader.app` (`de.manhhao.hoshi`). Native UI behavior must be revalidated against the exact DerivedData product with bundle id `moe.shishamo.hoshi`; no affected Reader safe-area UI claim remains accepted from that run.
- Native Reader image preview: SVG fixture images now render through an embedded WebKit document with contain sizing, avoiding the cropping and broken local-file access seen with `NSImage` and direct file references.
- AnkiConnect: the local API v6 endpoint, connected settings state, and read-only deck/model refresh succeed while preserving the selected `Lapis` deck/model. Lapis, Kiku, and Senren receive missing Profile-specific default field mappings without overwriting non-empty custom mappings. Novel defaults map `SentenceAudio`/`Picture` to `{sasayaki-audio}`/`{book-cover}`; anime defaults map them to `{video-audio-clip}`/`{video-screenshot}`. Settings exposes confirmed novel and anime restore actions while retaining template-external fields and clearing the harmful legacy `DefinitionPicture={glossary}` mapping. A uniquely tagged temporary Lapis note verified actual AnkiConnect success, duplicate rejection and invalid-deck failure with pronunciation HTML, then was deleted and confirmed absent; the three Hoshi toast states still need an in-App UI pass.
- Profiles and English: native Settings manages immutable-language Japanese/English Profiles. Built-in `Japanese EPUB` remains the Japanese book/global default, while built-in `Japanese Video` is added non-destructively and becomes the Video default when no explicit Video Profile was chosen. EPUB resolves per-book override, language default, then global active Profile; Video remembers an independent selection from the bottom playback controls. Dictionary order/settings, Reader appearance and Anki mining mappings are isolated while AnkiConnect transport remains global. English lookup uses the multilingual hoshidicts fork, phrase-aware selection, IPA mining HTML and approximate word counts. Dictionary backups include `.hoshi-profiles` metadata and merge only dictionary-owned Profile files.
- Upgrade compatibility: the earlier isolated Catalyst-to-native replacement test used the former `de.manhhao.hoshi` identity. It proves file-layout compatibility for that build, but no longer proves `UserDefaults` continuity after the active App moved to `moe.shishamo.hoshi`. Books, sidecars, dictionaries, and Anki JSON remain in shared Application Support paths; the Google Keychain service intentionally stays legacy-compatible. The old defaults domain, Google Drive defaults fallback/folder IDs, and real-account token continuity still require an explicit non-destructive migration and isolated validation.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.
- Video variants: the native target has Light (`Debug`/`Release`) and Video (`Debug-Video`/`Release-Video`) configurations. Light excludes Video/libmpv; Video provides local playback, SRT/VTT overlay, shared popup/nested lookup/local word audio, and video-specific Anki mining fields.
- Video playback controls now include pointer-move show plus short-delay, app-inactive, and pointer-exit auto-hide for the playback chrome, an IINA-like compact draggable control surface, single-click play/pause, double-click native fullscreen, same-folder episode selection, previous/next and configurable EOF auto-advance, playback speed shortcuts, volume/mute shortcuts, subtitle previous/next seek, subtitle visibility and track cycling, subtitle timing, video/audio/subtitle track selection, visible/full-shortcut native fullscreen, optional per-file position restore, and a configurable shortcut seek interval. The Video detail stays alive across sidebar section switches so playback can continue while Bookshelf, Dictionary, or Settings is selected; Video shortcuts are active only while the Video section is visible. Embedded text subtitle tracks use the interactive Hoshi overlay; image subtitles remain mpv-rendered.
- App bundle identity is now `moe.shishamo.hoshi` for both Light and Video variants. Google Drive keychain service intentionally keeps the legacy `de.manhhao.hoshi.google-drive` service string for token continuity.
- Video Mining History, transcript and chapter navigation now share one fixed right study sidebar. Chapters show the current marker and seek through the existing playback engine. External subtitle parsing and selected embedded text-track extraction prepare off-main; video and track switches invalidate stale track rows even when adjacent episodes expose identical track IDs, and the transcript renders only the current time-neighborhood instead of laying out the entire subtitle file. The Video surface accepts dropped media and SRT/VTT files through the same primary video/subtitle import path as the picker controls.
- Video subtitle appearance controls set Hoshi-owned text subtitle font and size, defaulting to asbplayer-style system font and 36 px size. Subtitle mask controls can blur or hide text subtitles until pointer hover. These settings are shared between Video Settings and the playback inspector and remain text-only overlay effects without adding a subtitle background frame.
- Video subtitle mining now separates capture history from Anki results: the player button or configurable `⌃⇧Z` stores the current visible subtitle in an asbplayer-style bounded history; clicking a history row restores its saved video/subtitle time, with direct copy and delete actions. Add to Anki captures the current frame and uses bundled libmpv to encode the selected audio track over the delayed, padded subtitle range for mapped video fields; a failed required audio capture stops card creation instead of silently creating an incomplete card.
- Video release: packaging and GitHub Actions produce Light and Video DMGs with the same bundle id and data paths; bundle checks require universal dylibs and reject Homebrew paths.
- Local Video debug launches re-sign every embedded libmpv dylib and verify the complete App bundle before opening it. This prevents the observed dyld termination where `libharfbuzz.0.dylib` reached an invalidly signed `libgraphite2.3.dylib`; the attached crash was from the superseded `de.manhhao.hoshi` build, not a shortcut handler stack.

## Next Actions

- Decide whether a future release should add Developer ID signing and notarization; the current pipeline uses ad-hoc signing so Apple Silicon can launch the App, but remains non-notarized and does not establish developer trust.
- Keep Reader visual validation centered on actual EPUB data; do not reintroduce fixture or pixel-baseline automation unless it can reproduce real-book failures without mutating the Reader state being measured.
- Validate Google Drive auth on native macOS with a real Google account and callback flow.
- Validate Hoshi's success, duplicate, and failure toast presentation with a disposable deck; the underlying AnkiConnect paths have been verified and the temporary test note was removed.
- Complete the remaining disposable-data UI validation for per-Profile Anki mining and profile-aware dictionary backup restore before release; English lookup, inline IPA, possessive normalization and approximate-word progress already have a real-EPUB smoke test.
- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- Extend Reader visual validation beyond the current real-EPUB vertical/horizontal and paginated/continuous checks: cover resized/full-screen windows, image-heavy pages, chapter boundaries, and Sasayaki highlight restore in the exact `moe.shishamo.hoshi` build.
- Design and validate a one-time, non-destructive migration from the legacy `de.manhhao.hoshi` defaults domain to `moe.shishamo.hoshi`; preserve current-domain values, migrate only known keys, and cover Google Drive fallback/folder metadata without clearing tokens.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.
- Manually verify video playback, seek, compact draggable playback chrome pointer-reveal/idle-hide/window-exit-hide behavior, single-click play/pause, double-click fullscreen, sidebar section switching while playback continues, video/subtitle drag-and-drop, window/page lifecycle, subtitle click coordinates, subtitle font/size appearance changes, subtitle mask blur/transparent hover reveal, nested popup, local audio, screenshot/audio mining, mining-history sidebar behavior, and disposable-deck Anki success/duplicate/failure before shipping the Video variant. Primary SRT import, transcript-list performance and bundled-libmpv MKV audio export have focused checks, but drag-and-drop, playback chrome dragging, subtitle appearance/mask hover, auto-hide feel, in-App video media attachments, and Anki state transitions still need a disposable-deck/manual UI pass.
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
./script/verify_video_variant_contract.sh
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
swift script/test_color_hex_codec.swift
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_css_editor_snippets.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc Models/Anki.swift script/test_anki_field_templates.swift -o /tmp/test_anki_field_templates && /tmp/test_anki_field_templates
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift script/test_profile_repository.swift -o /tmp/test_profile_repository && /tmp/test_profile_repository
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
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
- [x] Keep Video media placeholders in normal Anki field mapping and capture current-frame screenshots plus bundled-libmpv subtitle-range audio before AnkiConnect submission.
- [ ] Re-plan secondary/bilingual subtitles after primary subtitle import, transcript navigation, lookup and mining are fully validated.
- [ ] Keep embedded secondary subtitle extraction, ASS layout fidelity, study statistics and sync as later work.
