# Hoshi Reader Mac Upstream Sync Queue

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

- Reader navigation architecture: compare future upstream navigation changes against the Mac-stable requirement that Books, Dictionary, and Settings remain predictable.
- Reader pagination: keep monitoring upstream vertical writing fixes, but test them in the native macOS WKWebView before adopting.
- Dictionary rendering: evaluate upstream dictionary media and popup rendering changes together, not independently.

## Adapted

- `8ffca617204c357e69573741c70c8d57a463bfd5` (`feat: autofill lapis, kiku, senren`): ported the upstream template mappings with native Mac safe-merge semantics. Missing current-model fields are filled during config load, AnkiConnect refresh, and model selection; existing non-empty mappings are not overwritten automatically. Native Settings offers confirmed novel/anime restores, while built-in `Japanese EPUB` and `Japanese Video` Profiles select the corresponding safe-fill preset. Lapis `DefinitionPicture` remains cleared because the retired heuristic preset once misclassified it as glossary content.
- Android `v1.2.0`: adapted named Japanese/English Profiles and English lookup behavior to native macOS. Mac keeps a shared AnkiConnect transport and physical dictionary store, uses explicit Reader/Video Profile contexts, and pins the multilingual hoshidicts fork at `c60de40bf5f000a28bd6d309383761cd881b196b`; Android input-method switching was intentionally not copied.

## Deferred By Default

- iOS-only share extension behavior.
- AnkiMobile callback changes that do not apply to Mac AnkiConnect.
- Touch gesture changes that reintroduce accidental macOS navigation conflicts.
