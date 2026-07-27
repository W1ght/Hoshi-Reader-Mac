# Manga

Load this reference only for the Manga library, native Manga Reader, local media, Mokuro, OCR, Suwayomi, or manga mining.

## Required Context

- Read the `Manga Learning` section of `docs/ARCHITECTURE_REFACTORING.md`.
- Read the Manga and external-source sections of `docs/READER_REGRESSION_TESTING.md` when behavior or validation changes.
- Inspect the current `MangaReadingSession` and `MangaPageContentProvider` boundaries before adding source-specific behavior.

## Invariants

- Local folders, CBZ/ZIP, EPUB, Mokuro data, and custom covers are read-only user media plus App-owned metadata. Library actions must not move, rename, rewrite, or delete source files.
- Local and Suwayomi pages adapt to the same native Reader, page processing, lookup, nested Popup, progress, and `MiningContext.manga` pipeline. Do not create a second Reader, lookup renderer, or Anki client.
- Suwayomi is an external service managed by the user. Niratan does not install or execute source extensions, Shinsou JavaScript, Java runtimes, APKs, or Suwayomi Server. Keep its configuration Profile-scoped, secrets in Keychain, and the local catalog separate from the server library.
- Prefer embedded Mokuro text. Google Lens is an unofficial network OCR path that uploads a reduced page image; preserve disclosure and explicit user initiation. Requests, prefetch, OCR, and remote bootstrap work must be cancellable and discard stale session results.
- Cache identity and invalidation must separate source, server, Profile, chapter, page, and source modification state as applicable. Bounds and retries remain finite.

## Verification

- Use the focused `script/test_manga_*` or Suwayomi contract selected by the changed boundary, then build and open the exact App for runtime work.
- UI validation uses a disposable local source, Profile, and Suwayomi library. Cover only the affected layout, direction, zoom, processing, OCR, Popup, mining, progress, window, or remote lifecycle rows from the regression document.
- If no safe fixture or external server is available, report that limitation. Never repurpose the user's catalog, progress, OCR cache, source files, credentials, or server library.
- If shared Popup, audio, shortcuts, Anki, Profile, or build packaging changes, also load the corresponding reference.
