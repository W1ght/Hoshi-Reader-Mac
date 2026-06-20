# Hoshi Reader Mac Architecture Refactoring

This document records long-term architecture direction. It is not an execution log.

## Principles

- Preserve Mac user-visible behavior before matching iOS implementation details.
- Keep Reader, popup lookup, AnkiConnect, local audio, Sasayaki, and sync boundaries explicit.
- Prefer small, testable state transitions over broad root-view rewrites.
- Treat WKWebView layout, injected CSS, and JavaScript bridge changes as high-risk API changes.
- Keep SwiftUI screens where possible and use narrow AppKit boundaries instead of duplicating screens.

## UIKit To AppKit Migration

The native Mac migration plan is now `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`.

Long-term direction:

- Keep current SwiftUI feature screens, models, and services unless a real Mac behavior gap appears.
- Do not preserve iOS compatibility branches merely for theoretical reuse; this repository is the Mac product.
- Remove iOS-only paths first where doing so does not change Mac behavior.
- Do not reintroduce UIKit or a Catalyst target.
- Keep Reader/WebView, popup coordinate handling, Google Drive sync, AnkiConnect, LocalFileServer, word audio, and Sasayaki behavior stable during native hardening.

## Reader Navigation

The stable target is a root navigation model where Books, Dictionary, and Settings remain predictable while the reader can preserve the current reading session.

Open questions to resolve before another Reader navigation rewrite:

- Whether Reader should remain a Books `NavigationStack` destination or become a Mac-specific scene/overlay.
- How root navigation should remain reachable without Reader owning a duplicate root tab control.
- How full-screen focus mode should enlarge the reading area without causing toolbar or safe-area relayout flicker.

## Reader WebView And Pagination

Long-term direction:

- Keep vertical and horizontal pagination logic close to upstream behavior where it is browser-layout compatible.
- Isolate Mac-only overflow protections so they do not destabilize vertical writing.
- Add small deterministic checks for generated reader CSS and JavaScript bridge invariants.
- Maintain a manual visual test set that includes vertical Japanese EPUBs, long chapters, images, and chapter boundaries.
- Keep Reader visual validation tied to actual EPUB data in the exact native App. Lightweight contracts can guard bridge/static behavior, but generated fixtures, Debug Lab automation, and pixel baselines must not be treated as proof of safe-area or pagination correctness.

## Dictionary And Popup Rendering

Long-term direction:

- Keep dictionary page and popup rendering paths aligned.
- Avoid separate CSS compatibility layers for popup-only fixes.
- Preserve dictionary media handling for hoshidicts/Yomitan data rather than replacing broken content with generic placeholders.
- Treat `PopupPresentationCoordinator` and `PopupView` as reusable lookup presentation boundaries. Reader and Video provide selection geometry and mining context; neither owns a separate dictionary renderer.

## Profiles And Content Language

- Resolve configuration through an explicit `ProfileContext`: book override, language default and global fallback for EPUB; independently remembered Profile for Video.
- Keep physical dictionary data and AnkiConnect transport global. Profile-owned state is limited to dictionary enable/order/display, Reader appearance and Anki mining mappings.
- Carry the resolved Profile ID through Reader, Popup, nested lookup and mining so multiple windows cannot change one another by mutating an implicit lookup language.
- Preserve `default-ja` legacy projections and merge profile-aware dictionary backups without overwriting Reader or Anki Profile files.
- Language processors belong at the lookup/selection boundary. Stored bookmarks and statistics remain raw character positions; English only converts those values for approximate-word display and input.

## Video Learning

Long-term direction:

- Ship Light and Video variants from one native target. Keep `HOSHI_VIDEO` at the feature/dependency boundary so Light never links or bundles libmpv.
- Keep `PlaybackEngine` independent from SwiftUI and isolate libmpv C/Objective-C++ integration in `Features/Video/Playback/`.
- Parse subtitle documents into Hoshi-owned cues and render an interactive overlay. mpv subtitle rendering is not a lookup surface.
- Keep media opening and subtitle import non-blocking on the main actor. Folder playlist discovery, large subtitle parsing, and transcript construction are background work; the UI should first load the selected media and show a bounded current-time transcript window.
- Keep Video import entry points aligned: picker imports and drag-and-drop must route through the same media/subtitle loading functions so mpv sidecar behavior, Hoshi overlay parsing, transcript construction, and mining context stay consistent.
- Keep Video playback state owned by a persistent Video detail surface rather than by transient sidebar selection. Switching to Bookshelf, Dictionary, or Settings may hide the Video surface and unregister Video shortcuts, but it should not tear down mpv or release the current media URL until the window/app actually closes.
- Treat mpv subtitle loading as a best-effort renderer/track alignment path. Hoshi-owned parsed subtitles remain the source for overlay lookup, transcript navigation, and mining even when mpv rejects a path or format.
- Keep playback chrome lightweight and video-local: the compact draggable OSC and top buttons may auto-hide after pointer idle, pointer exit, or app deactivation and reappear on video pointer movement, while single-click remains play/pause, double-click remains fullscreen, and inspector/mining history keep their separate overlay/sidebar roles. Default subtitle placement must clear the default OSC position; dragging the OSC is an adjustment affordance, not a requirement for reading captions.
- Keep subtitle appearance and masking as Hoshi-owned text overlay effects: font/size controls, blur and opacity can change text rendering, but they must not add background frames, depend on mpv-rendered subtitles, or become a draggable rectangular blur overlay.
- Reuse shared lookup, popup, nested lookup, word audio, AnkiConnect and duplicate-check behavior.
- Keep Video shortcut editing in the unified Keyboard Shortcuts surface. Video Settings may summarize the current Video bindings, but it must not add a second recorder or shortcut store.
- Carry video-only mining data through `MiningContext.video`; do not make EPUB models depend on video playback state. Video media capture stays on this path: subtitle mining may capture the current frame and bundled-libmpv subtitle-range audio, but normal AnkiConnect field mappings still decide whether `{video-screenshot}` and `{video-audio-clip}` become note attachments. Required mapped audio failure must stop the note before submission.
- Keep Video Mining History video-only for now: it is a bounded, chronological subtitle capture queue independent of Anki results. Continuing from history must reopen the saved media/subtitle context and return to the shared Video lookup/Popup path rather than adding a second card editor or Anki client.
- Keep secondary/bilingual subtitles, full ASS layout fidelity, viewing statistics and sync as later phases.

## AnkiConnect

Long-term direction:

- Keep AnkiConnect as the Mac mining path.
- Separate connection state, deck/model fetching, field mapping, and note creation enough that each can fail with clear UI state.
- Preserve existing mappings when refreshing decks and models.
- Keep known note-type defaults in the Anki model boundary and let `AnkiManager` merge only missing current-model fields during load, refresh, and model selection; explicit user mappings remain authoritative. A separately confirmed settings action may overwrite only fields defined by the selected known template while preserving other available fields.
- Keep AnkiConnect URL, timeout, reconnect, sync options and server metadata global; deck, model, mappings, tags, duplicate/media and glossary choices are selected by explicit Profile ID.

## Local Audio And Sasayaki

Long-term direction:

- Keep dictionary word audio and Sasayaki whole-book audio as separate services.
- Keep Sasayaki matching logic and sidecar persistence in the existing Bookshelf/Sasayaki service boundary; the native Bookshelf owns only the selected-book state and match-sheet presentation.
- Make fallback behavior explicit and visible in code, not implicit through shared player utilities.
- Keep `LocalFileServer` ownership narrow: serving local assets, not deciding audio semantics.

## Google Drive Sync

Long-term direction:

- Model sync as user-progress protection, not just file upload/download.
- Preserve timestamps and sidecar metadata carefully when progress does not numerically change.
- Make conflict behavior auditable before changing token, actor, or callback flows.

## Release

Long-term direction:

- Keep `main` as the release branch.
- Keep DMG and checksum as primary release artifacts.
- Publish Light and Video DMGs with the same bundle identity and data paths. A release is complete only when both bundle contracts pass.
- Keep release notes user-facing and Chinese-first unless the user requests otherwise.

## Build And Runtime Identity

- Treat `moe.shishamo.hoshi` as the only active Light/Video bundle identity. Keep the legacy `de.manhhao.hoshi.google-drive` Keychain service string only for token continuity.
- Treat the bundle-id change as a persistence migration boundary: file-based Application Support compatibility does not imply `UserDefaults.standard` continuity. Any legacy defaults import must be explicit, one-time, known-key-only, and must never overwrite values already present in the current domain.
- Resolve local UI validation from the exact Xcode build product, then verify both its `CFBundleIdentifier` and the running process executable path.
- Do not use process name, window title, or an unqualified app name as runtime identity; an old `/Applications/Hoshi Reader.app` can share all three while running obsolete code.
