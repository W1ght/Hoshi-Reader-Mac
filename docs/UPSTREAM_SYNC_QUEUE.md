# Niratan Mac Upstream Sync Queue

Use this queue to decide what to evaluate from `upstream/develop`. Upstream code is a behavior reference; Mac implementation must be adapted deliberately.

## Intake Checklist

Before applying upstream changes:

- Fetch and inspect upstream commits.
- Identify whether the diff touches Reader, WebView JS/CSS, Popup, Dictionary rendering, Settings, Sasayaki, Sync, Anki, or persistence.
- Compare user-visible behavior against current Mac behavior.
- Decide whether to port, adapt, defer, or reject the change.
- Record durable follow-up here only if it remains relevant after the task.

## High-Priority Watch Areas

### Reader / WebView

- Pagination, vertical writing, image sizing, safe-area, and focus-mode changes.
- JavaScript bridge changes in `reader.js` and `scrollreader.js`.
- Toolbar or root navigation changes that can affect native macOS window behavior.

### Dictionary / Popup

- Dictionary rendering templates and media handling.
- Popup layout CSS and nested popup behavior.
- Lookup shortcut and entry navigation behavior.

### Sync

- Google Drive token refresh, callback handling, conflict resolution, and progress timestamp logic.

### Audio

- Sasayaki cue handling and local dictionary audio changes.
- Any upstream fallback that could mix word audio with whole-book audio.

## Current Queue

- `ede999c6`: evaluate pause-on-image playback separately from cross-chapter restore correctness. A Mac adaptation must share the existing Reader/Gallery image index and lyrics/statistics pipeline instead of copying the iOS settings and bridge state.
- `4940ab7e`: evaluate the sentence trailing-character change independently against Japanese and English context mining. The native selection script serves both Profile languages, so do not apply the upstream Japanese punctuation rule globally.
- Reader navigation architecture: compare future upstream navigation changes against the Mac-stable requirement that Books, Dictionary, and Settings remain predictable.
- Reader pagination: keep monitoring upstream vertical writing fixes, but test them in the native macOS WKWebView before adopting.
- Dictionary rendering: evaluate upstream dictionary media and popup rendering changes together, not independently.

## Adapted

- `cfc1e509` (`fix: build query off main thread`): adapted with a generation-tagged native query bundle. Dictionary construction leaves the main actor, stale builds cannot replace the requested Profile, unchanged configurations skip rebuilding, and lookups return no obsolete Profile data while a replacement is pending.
- `61a8c9db` (`fix: resolve relative paths manually`): adapted with EPUB-root-bounded component normalization for TTU image paths, including `.`/`..` handling and query/fragment removal, without resolving paths against the Mac host filesystem.
- `f54b55f4` (`fix: rank term and reading match first in local audio`), `8d1442e8` (`fix: add danger/success accent colors from yomitan to css`) and `5764c5c6` (`fix: use bindings instead of using indices for audio sources`): adapted to the native shared lookup/settings surfaces. Local audio ranks exact expression+reading pairs first, structured dictionary content receives light/dark semantic colors, and reordered sources mutate through stable bindings/IDs.
- The safe startup portion of `3f174c3a` (`fix: attempt to reduce startup pressure`): adapted without copying the iOS launch flow. Native local-media listener creation now logs and performs bounded retries instead of trapping, and shelf persistence safely handles an unavailable Application Support directory. Moving book migrations off the main actor remains intentionally unported because it needs a separate Mac data-safety launch gate.
- `078d59f4` (`fix: override publisher column-count in paginated mode`) and `bdf71a62` (`fix: remove webkit line-box property`): adapted in the native shared Reader injection. Nested publisher columns are neutralized only for paginated rendering so continuous layouts retain their authored structure; the WebKit line-box override is removed from both modes while Mac's explicit two-column body layout remains authoritative.
- `b717c575` (`fix: reuse highlight object`): adapted with one reusable CSS Highlight per Reader document while preserving Niratan's DOM-span fallback for WebKit environments without the CSS Highlights API. The related punctuation change remains queued for language-aware validation.
- `bcbef648` (`fix: calc chars for same-file entries in toc`) plus the statistics calculation from `2e1c958f`: adapted through a shared native chapter index. New imports persist fragment offsets using the Reader's normalized character rules; legacy `bookinfo.json` files receive a cancellable utility-priority backfill that reloads the latest sidecar and only merges missing offsets. Chapter highlighting and time-to-finish now use true TOC ranges, including multiple chapters in one XHTML file. The upstream progress-display settings were intentionally not copied.
- `be88af18` (`fix: restore to actual cue progress instead of 0 when seeking across chapters`) and `e1d4b3b7` (`fix: load failed images`): adapted together for the native Reader. Cross-chapter Sasayaki navigation resolves the pending cue through the Mac bookmark/statistics boundary, flushes only the old reading position, persists the destination without counting the jump distance, and treats already-failed images as completed restore work instead of leaving cue setup pending.
- `76177841` (`fix: keep cross-node Sasayaki punctuation highlighted`), `e9690569` (`fix: prevent scrolling to cue in chapter when audio is paused`) and `83eb3193` (`fix: scroll to active cue in when unpausing in same chapter`): adapted to the shared paginated/continuous JavaScript and the native playback lifecycle.
- `6655ffdd` (`fix: filter numerically encoded chars`): adapted without deleting represented text. Niratan decodes decimal and hexadecimal HTML character references before Reader, Sasayaki and Gallery character filtering so persisted offsets continue to match rendered text.
- `98b65340` (`fix: strip whitespaces in ruby nodes`) and `3bff3908` (`fix: prevent scanning across expression tags`): adapted to the native Reader injection and shared selection boundary so ruby mutations use a stable node snapshot and lookup does not cross expression blocks.
- `54fab150` (`fix: pause stats when any sheet or fullscreenimageviewer is open`): adapted to the native Reader focus/coverage model. The live Statistics sheet remains an approved counting surface; other Reader sheets and the full-screen image overlay pause tracking.
- `fd124d4366009c4e2ee5d969f7f9b8907a0d4121` (`feat: image gallery`): adapted as a native macOS Reader menu and resizable image-grid sheet. Image paths are cached in backward-compatible `bookinfo.json` metadata, constrained to real JPG/PNG resources inside the extracted EPUB, and opened through the existing native Reader full-screen image viewer; the iOS sheet layout was not copied.
- `8ffca617204c357e69573741c70c8d57a463bfd5` (`feat: autofill lapis, kiku, senren`): ported the upstream template mappings with native Mac safe-merge semantics. Missing current-model fields are filled during config load, AnkiConnect refresh, and model selection; existing non-empty mappings are not overwritten automatically. Native Settings offers one confirmed restore for the shared EPUB/Video mapping, with `{book-cover}` and `{sasayaki-audio}` resolved by mining context. Lapis `DefinitionPicture` remains cleared because the retired heuristic preset once misclassified it as glossary content.
- Android `v1.2.0`: adapted named Japanese/English Profiles and English lookup behavior to native macOS. Mac keeps a shared AnkiConnect transport and physical dictionary store, uses explicit Reader/Video Profile contexts, and pins the multilingual hoshidicts fork at `c60de40bf5f000a28bd6d309383761cd881b196b`; Android input-method switching was intentionally not copied.

## Deferred By Default

- `2702e31d` (`fix: disable mine buttons if first field unconfigured, handle disconnected ankiconnect`): do not port its Anki mining gate to Mac. Both the direct port and a native preflight adaptation regressed the established Popup/Dictionary workflow, so Niratan retains its previous AnkiConnect behavior.
- iOS-only share extension behavior.
- AnkiMobile callback changes that do not apply to Mac AnkiConnect.
- Touch gesture changes that reintroduce accidental macOS navigation conflicts.
