# Native Reader Text Selection and Highlights Design

## Problem

The native macOS Reader clears a browser text selection immediately after a drag finishes. Its capture-phase `click` listener always runs the click-to-lookup path, whose `selectText` implementation clears the browser selection before creating Hoshi's lookup highlight.

The native migration also retained highlight rendering and deletion but omitted the macOS context-menu bridge that creates and persists highlights from a browser selection.

## Desired Behavior

- A normal click on Reader text keeps the existing click-to-lookup behavior.
- Dragging across text preserves WebKit's native selection.
- The standard macOS context menu remains available for a real selection and includes a Highlight submenu with the existing highlight colors.
- Choosing a color creates the highlight through `window.hoshiHighlights.createHighlight`, persists it in the current book, and keeps the existing highlight list and deletion behavior working.
- Links, images, lookup popups, paging, continuous scrolling, vertical writing, copy, and Shift-hover lookup retain their current behavior.

## Design

### Selection Arbitration

Before the Reader's click-to-lookup listener calls `selectText`, it will inspect `window.getSelection()`. When WebKit reports a non-collapsed selection, the listener returns without clearing the selection, opening a lookup popup, or sending `tapOutside`.

The browser selection itself is the source of truth. No mouse-distance threshold or custom drag recognizer is introduced.

### Native Context Menu

`NativeReaderWKWebView` will extend WebKit's existing AppKit context menu instead of replacing it. It will track whether JavaScript reports an active selection through the existing `selectionState` message and add a Highlight submenu only while a selection exists.

Each color item invokes the existing JavaScript highlight creator. Successful creation is returned as `HighlightData` and forwarded through `NativeReaderWebView` to `NativeReaderModel`, which appends and saves the highlight using the current book storage path.

The implementation will preserve WebKit's standard menu items such as Copy.

### Failure Handling

If there is no selection, JavaScript returns invalid data, or highlight creation fails, no highlight is persisted. Existing content and highlight data remain untouched.

## Testing

Add a regression contract before production changes and confirm it fails for the missing behavior. The contract will require:

- the click listener to leave a non-collapsed browser selection untouched;
- `selectionState` registration, handling, and teardown;
- native context-menu highlight creation to forward successful `HighlightData`;
- the Reader model callback to persist the new highlight.

After the test turns green, run the Reader regression contract and the exact native Light build with `--verify`. Manual verification should cover:

- normal click lookup;
- drag selection and Copy;
- right-click highlight creation and deletion;
- highlight persistence after reopening the book;
- horizontal and vertical writing;
- paginated and continuous modes.

Actual EPUB scenarios that cannot be safely exercised without changing user reading data will be reported as unverified.

## Scope

This change restores existing highlight behavior on native macOS. It does not add notes, custom floating selection UI, multi-range annotations, or Catalyst compatibility.
