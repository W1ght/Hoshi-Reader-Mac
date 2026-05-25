# Hoshi Reader Mac Architecture Refactoring

This document records long-term architecture direction. It is not an execution log.

## Principles

- Preserve Mac user-visible behavior before matching iOS implementation details.
- Keep Reader, popup lookup, AnkiConnect, local audio, Sasayaki, and sync boundaries explicit.
- Prefer small, testable state transitions over broad root-view rewrites.
- Treat WKWebView layout, injected CSS, and JavaScript bridge changes as high-risk API changes.

## Reader Navigation

The stable target is a root navigation model where Books, Dictionary, and Settings remain predictable while the reader can preserve the current reading session.

Open questions to resolve before another Reader navigation rewrite:

- Whether Reader should remain a Books `NavigationStack` destination or become a Mac-specific scene/overlay.
- How root navigation should remain reachable without Reader owning a duplicate root tab control.
- How full-screen focus mode should enlarge the reading area without causing toolbar or safe-area relayout flicker.
- How to validate behavior on older Catalyst runtimes without compromising current Mac behavior.

## Reader WebView And Pagination

Long-term direction:

- Keep vertical and horizontal pagination logic close to upstream behavior where it is browser-layout compatible.
- Isolate Mac-only overflow protections so they do not destabilize vertical writing.
- Add small deterministic checks for generated reader CSS and JavaScript bridge invariants.
- Maintain a manual visual test set that includes vertical Japanese EPUBs, long chapters, images, and chapter boundaries.

## Dictionary And Popup Rendering

Long-term direction:

- Keep dictionary page and popup rendering paths aligned.
- Avoid separate CSS compatibility layers for popup-only fixes.
- Preserve dictionary media handling for hoshidicts/Yomitan data rather than replacing broken content with generic placeholders.

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
- Keep release notes user-facing and Chinese-first unless the user requests otherwise.
