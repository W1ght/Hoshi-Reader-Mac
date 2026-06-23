# Sasayaki Page-Turn Statistics Design

## Problem

The `Page Turn` statistics autostart mode is invoked by manual Reader navigation, but Sasayaki auto-scroll uses separate paths. Same-chapter page changes return a new progress value from the WebView without signaling a page turn, while cross-chapter cue transitions call `loadChapterForSasayaki` directly.

## Design

Store the configured `StatisticsAutostartMode` in `NativeReaderModel` and make the existing page-turn starter use that model state. All manual navigation continues through the same helper.

For same-chapter Sasayaki auto-scroll, invoke `onPageTurn` only when the JavaScript highlight command returns a progress value, which means it actually moved the page or scroll position. For cross-chapter Sasayaki navigation, invoke the model helper at the chapter-load boundary. Cue highlighting that does not move the viewport must not start statistics.

## Verification

- Extend the focused Reader contract to require the shared model mode, the cross-chapter trigger, and the WebView trigger only inside the non-null progress result path.
- Confirm failure before implementation and success afterward.
- Re-run bookshelf and Reader regression contracts and exact Light build/launch verification.
- Do not alter user Reader settings or progress for automated UI validation.
