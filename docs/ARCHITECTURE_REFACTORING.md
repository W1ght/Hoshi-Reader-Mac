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
- Build a Debug-only Reader Regression Lab that can open deterministic fixtures, toggle Reader settings without mutating user preferences, expose geometry facts, and drive visual screenshot capture.
- Grow screenshot regression from manual artifacts to baseline comparison only after the fixture set and lab entry are stable.

## Dictionary And Popup Rendering

Long-term direction:

- Keep dictionary page and popup rendering paths aligned.
- Avoid separate CSS compatibility layers for popup-only fixes.
- Preserve dictionary media handling for hoshidicts/Yomitan data rather than replacing broken content with generic placeholders.
- Treat `PopupPresentationCoordinator` and `PopupView` as reusable lookup presentation boundaries. Reader and Video provide selection geometry and mining context; neither owns a separate dictionary renderer.

## Video Learning

Long-term direction:

- Ship Light and Video variants from one native target. Keep `HOSHI_VIDEO` at the feature/dependency boundary so Light never links or bundles libmpv.
- Keep `PlaybackEngine` independent from SwiftUI and isolate libmpv C/Objective-C++ integration in `Features/Video/Playback/`.
- Parse subtitle documents into Hoshi-owned cues and render an interactive overlay. mpv subtitle rendering is not a lookup surface.
- Keep media opening and subtitle import non-blocking on the main actor. Folder playlist discovery, large subtitle parsing, and transcript construction are background work; the UI should first load the selected media and show a bounded current-time transcript window.
- Treat mpv subtitle loading as a best-effort renderer/track alignment path. Hoshi-owned parsed subtitles remain the source for overlay lookup, transcript navigation, and mining even when mpv rejects a path or format.
- Keep subtitle masking as a Hoshi-owned text overlay effect: blur/opacity can hide subtitles until pointer hover, but it must not add background frames, depend on mpv-rendered subtitles, or become a draggable rectangular blur overlay.
- Reuse shared lookup, popup, nested lookup, word audio, AnkiConnect and duplicate-check behavior.
- Carry video-only mining data through `MiningContext.video`; do not make EPUB models depend on video playback state.
- Keep Video mining history video-only for now: it records attempts from `MiningContext.video`, persists bounded recent rows, and remains outside Reader/Dictionary mining until a separate global-history design is chosen.
- Keep secondary/bilingual subtitles, full ASS layout fidelity, viewing statistics and sync as later phases.

## AnkiConnect

Long-term direction:

- Keep AnkiConnect as the Mac mining path.
- Separate connection state, deck/model fetching, field mapping, and note creation enough that each can fail with clear UI state.
- Preserve existing mappings when refreshing decks and models.

## Local Audio And Sasayaki

Long-term direction:

- Keep dictionary word audio and Sasayaki whole-book audio as separate services.
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
