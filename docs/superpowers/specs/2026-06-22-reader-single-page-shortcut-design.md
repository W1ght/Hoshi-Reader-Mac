# Reader Single-Page Shortcut Design

## Goal

A physical Previous Page or Next Page key press must produce exactly one Reader page-navigation request. Two separate key presses must continue to produce two requests.

## Root Cause

Reader keyboard events can enter `ShortcutManager` through both the application-local `NSEvent` monitor and `NativeReaderWKWebView.keyDown`. The current event-signature deduplication assumes WebKit's rewrapped event preserves an exact microsecond timestamp. A light key press can therefore be dispatched twice when that signature differs.

Duplicate Reader registrations are not the cause: dispatch returns immediately after the first handler reports success.

## Design

Give each event exactly one dispatcher owner:

- When a focused AppKit responder explicitly owns shortcut dispatch, the local monitor passes the event through without invoking handlers.
- `NativeReaderWKWebView` declares that ownership and invokes the shared `ShortcutManager` once from `keyDown`.
- All other eligible controls continue to use the local monitor.
- Keep existing scope priority, text-input exclusions, key-repeat handling, and Reader pagination JavaScript unchanged.
- Remove cross-entry event-signature deduplication once the two entry paths are mutually exclusive.

## Verification

- Add a focused shortcut-dispatch regression test that fails against the current dual-entry behavior.
- Verify a WebView-owned event is not dispatched by the monitor path and is dispatched once by `keyDown`.
- Verify two independent non-repeat key presses remain distinct.
- Run the focused Reader shortcut regression contract.
- Build and launch the Light variant with `./script/build_and_run.sh --verify`.
- Manually verify Previous Page and Next Page with a real EPUB if an appropriate existing book is available without changing user data.
