# Reader, Popup, Audio, and Shortcuts

Load this reference only when the task touches novel reading, WKWebView, shared lookup surfaces, Sasayaki, dictionary audio, or configurable shortcuts.

## Required Context

- For Reader layout, navigation, popup, statistics, highlight, or Sasayaki behavior, read the relevant part of `docs/READER_REGRESSION_TESTING.md`.
- For sidecar or final-position persistence failures, also read `docs/READER_PERSISTENCE_DEBUGGING.md`.
- Inspect the nearest Swift, JavaScript, and injected CSS together; pagination, safe area, window chrome, viewport state, restore timing, and popup coordinates are coupled.

## Invariants

- Real macOS WKWebView behavior is authoritative. Do not repair clipping or pagination with an unexplained constant before locating the responsible geometry or restore boundary.
- Do not restore trackpad swipe page turning. Discrete mouse-wheel page turns and precise trackpad scrolling are separate input paths.
- Popup and Dictionary use the same rendering, nested lookup, media, and custom-CSS semantics. Do not add a feature-local lookup renderer.
- Treat user CSS as CSS; do not rewrite it into a compatibility dialect.
- `WordAudioPlayer` and local audio sources pronounce dictionary terms. Sasayaki plays whole-book audio; neither is a fallback for the other.
- Configurable shortcuts belong to `ShortcutRegistry`, `ShortcutManager`, and scope-aware handlers. Do not add feature-private persistence, hidden shortcut buttons, or a permanent `NSEvent` monitor.

## Verification

- Run only the focused contracts matching the changed boundary; the command index and actual-data matrix live in `docs/READER_REGRESSION_TESTING.md`.
- Reader visual claims require the exact built App and suitable real EPUB data covering the affected writing mode, layout, window state, and interaction.
- Do not import, replace, delete, or rewrite user books, bookmarks, sidecars, settings, statistics, or Sasayaki state for validation. If safe actual data is unavailable, report the missing matrix rows.
- If the change reaches Anki, Profile, token, or sync behavior, also load `data-integrations.md`.
