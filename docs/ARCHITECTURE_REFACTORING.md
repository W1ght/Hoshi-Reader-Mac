# Niratan Mac Architecture Refactoring

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

- Treat the active global Profile as the only runtime configuration choice. `Settings > Profiles` is the sole selector; Bookshelf, Reader, Video, Dictionary, Popup, nested lookup and mining consume that same selection.
- Keep sidebar navigation, Reader/Video window focus, book opening and detected content language Profile-neutral. They may adapt language processing to the content, but must never activate another Profile or trigger an implicit dictionary/Anki reload.
- Preserve legacy `BookMetadata.profileId`, UserDefaults `videoProfileID` and `ProfileIndex.primaryProfileIdsByLanguage` values when reading and writing existing data, but exclude them from runtime resolution. `Japanese` is the sole built-in Profile; merge an equivalent legacy `default-ja-video` configuration into it, while preserving any divergent customized legacy Profile under its original ID as an ordinary non-default global choice.
- Keep physical dictionary data and AnkiConnect transport global. Profile-owned state is limited to dictionary enable/order/display, Reader appearance and Anki mining mappings.
- Carry the active global Profile ID through Reader, Popup, nested lookup and mining so every surface uses one consistent dictionary, appearance and card-mapping configuration.
- Preserve `default-ja` legacy projections and merge profile-aware dictionary backups without overwriting Reader or Anki Profile files.
- Language processors belong at the lookup/selection boundary. Stored bookmarks and statistics remain raw character positions; English only converts those values for approximate-word display and input.

## Video Learning

Long-term direction:

- Ship Light and Video variants from one native target. Keep `HOSHI_VIDEO` at the feature/dependency boundary so Light never links or bundles libmpv.
- Keep `PlaybackEngine` independent from SwiftUI and isolate libmpv C/Objective-C++ integration in `Features/Video/Playback/`.
- Keep display correctness inside that native render boundary: render `CAOpenGLLayer` surfaces at the active screen's backing-pixel scale, prefer half-float precision with accelerated 8-bit fallback, supply SDR ICC through the libmpv render API, promote compatible opt-in HDR to macOS EDR/PQ, and bind swap reporting to the active display with an immediate fallback. These correctness paths must not introduce SwiftUI-owned OpenGL state or subjective sharpening profiles.
- Parse subtitle documents into Niratan-owned cues for lookup, transcript navigation and mining. Ordinary text subtitles render through the interactive Niratan overlay. For ASS/SSA, classify ordinary bottom dialogue as Niratan-owned primary cues and remove those events from the temporary effects-only document sent to bundled libass; explicitly positioned text, lyric/OP/ED events, animation, karaoke, drawings and duplicate effects remain libass-owned. While asynchronous ASS ownership preparation is incomplete, keep the original native track and interactive overlay hidden; reveal only the final split result, or atomically fall back to the complete native track after failure. A visible TextKit glyph is always its own selection, lookup-hit and popup-anchor source; mpv-rendered effects do not receive a mismatched transparent lookup plane.
- Keep playback history out of the shared preferences hot path. Legacy `UserDefaults` dictionaries are migration inputs only; periodic progress, resume options and subtitle selections live in a small dedicated Application Support file behind one process-shared memory snapshot, and library updates use media-identity-scoped notifications rather than broad defaults observation.
- Keep media opening and subtitle import non-blocking on the main actor. Folder playlist discovery, large subtitle parsing, and transcript construction are background work; the UI should first load the selected media and show a bounded current-time transcript window.
- Keep Video import entry points aligned: picker imports and drag-and-drop must route through the same media/subtitle loading functions so mpv sidecar behavior, Niratan overlay parsing, transcript construction, and mining context stay consistent.
- Keep Anime4K as an optional Video-only enhancement behind `PlaybackEngine`: Settings owns the persistent default and the player Video inspector applies the same strong-typed Off/Fast/High Quality preference live. Only pinned Anime4K v4.0.1 files may be downloaded into Application Support after size, UTF-8 hook and SHA-256 validation; mpv receives manager-owned file URLs through ordered `change-list glsl-shaders` commands. Light must never bundle, link or search for these shaders.
- Keep Video playback state owned by a persistent Video detail surface rather than by transient sidebar selection. Switching to Bookshelf, Dictionary, or Settings may hide the Video surface and unregister Video shortcuts, but it should not tear down mpv or release the current media URL until the window/app actually closes.
- Treat mpv subtitle loading as a best-effort renderer/track alignment path. Niratan-owned parsed subtitles remain the source for overlay lookup, transcript navigation, and mining even when mpv rejects a path or format.
- Keep playback chrome lightweight and video-local: the compact draggable OSC and pointer hide through the same idle callback and restore on video pointer movement, while AppKit mouse-button handling may reapply cursor hiding only when the OSC is still hidden. Player exit, app deactivation, popup/inspector/sidebar presentation, full-screen transitions and teardown must explicitly restore the cursor; single-click remains play/pause, double-click remains fullscreen, and inspector/mining history keep their separate overlay/sidebar roles. Default subtitle placement must clear the default OSC position; dragging the OSC is an adjustment affordance, not a requirement for reading captions.
- Keep subtitle appearance and masking as Niratan-owned effects for ordinary text tracks and ASS/SSA primary dialogue: font/size controls, glyph-level shadow/outline, blur, opacity and normalized height all operate on the same visible TextKit layout used for lookup. Authored ASS/SSA positioning and effects remain libass-owned in the filtered effects track, with no duplicate primary dialogue or invisible hit surface.
- Reuse shared lookup, popup, nested lookup, word audio, AnkiConnect and duplicate-check behavior.
- Keep Video shortcut browsing and editing in the unified Keyboard Shortcuts and Game Controller surfaces under Shortcuts & Controls. Both input surfaces consume the same application shortcut registry, scope-aware handler pipeline and action identifiers, so Video Settings must not duplicate the shortcut inventory, navigation entry, recorder, dispatch logic or store. Controller bindings use their own action-id configuration and preserve the legacy Reader/Sasayaki defaults through migration.
- Carry video-only mining data through `MiningContext.video`; do not make EPUB models depend on video playback state. Video media capture stays on this path: subtitle mining may capture the current frame and bundled-libmpv subtitle-range audio, but normal AnkiConnect field mappings still decide whether `{video-screenshot}` and `{video-audio-clip}` become note attachments. Required mapped audio failure must stop the note before submission.
- Keep Video Mining History video-only for now: it is a bounded, chronological subtitle capture queue independent of Anki results. Continuing from history must reopen the saved media/subtitle context and return to the shared Video lookup/Popup path rather than adding a second card editor or Anki client.
- Keep secondary/bilingual subtitles, arbitrary positioned-ASS glyph hit geometry, viewing statistics and sync as later phases.

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

- Treat `moe.shishamo.hoshi` as the only active Light/Video bundle identity. Google Drive credentials live in one account-only Keychain item (`googleDriveCredentials`), and render-time auth state must use cached/presence checks instead of reading token secret data. Legacy split accounts (`accessToken`, `refreshToken`, `clientId`) are migration inputs only when a real sync/auth operation needs credentials. Do not add a Mac-only Google Drive service namespace unless a future migration plan handles Keychain prompts and token continuity explicitly.
- Treat the bundle-id change as a persistence migration boundary: file-based Application Support compatibility does not imply `UserDefaults.standard` continuity. Any legacy defaults import must be explicit, one-time, known-key-only, and must never overwrite values already present in the current domain.
- Resolve local UI validation from the exact Xcode build product, then verify both its `CFBundleIdentifier` and the running process executable path.
- Do not use process name, window title, or an unqualified app name as runtime identity; an old `/Applications/Niratan.app` can share all three while running obsolete code.
