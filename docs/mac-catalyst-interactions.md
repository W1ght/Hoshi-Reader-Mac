# Hoshi Reader Mac Catalyst Interactions

This document describes the current desktop-oriented behavior for Hoshi Reader when running through Mac Catalyst.

## Scope

The Mac build currently shares the same core reading, lookup, and settings code as iPhone and iPad, but it applies a few desktop-specific interaction rules:

- The main app can be built as a Mac Catalyst target.
- The reader window uses desktop keyboard shortcuts.
- Card creation on Mac is expected to use AnkiConnect.
- The iOS Share Extension flow remains iOS-only.

## Reader Window

When a book is opened from the bookshelf, Hoshi Reader opens it inside the Books navigation stack on Mac so the main `Dictionary` and `Settings` tabs remain reachable.

Current Mac-oriented behavior:

- `Esc`, `Cmd+W`, or the back control closes the reader and returns to the bookshelf.
- The selected book state is cleared when switching to the `Dictionary` or `Settings` tab.

## Keyboard Shortcuts

The following shortcuts are wired for the reader on Mac Catalyst:

- `Left Arrow`: previous page or previous continuous reading step
- `Right Arrow`: next page or next continuous reading step
- `Up Arrow`: previous reading step
- `Down Arrow`: next reading step
- `Esc`: close the reader
- `Cmd+W`: close the reader
- `F`: toggle focus mode

## Lookup Interaction

Lookup behavior differs slightly on Mac compared with touch devices.

### iPhone / iPad

- In the reader, tapping a character triggers a scan starting from the tapped position.
- The scan expands forward until it reaches a boundary or the configured max scan length.
- If a match is found, the popup dictionary is shown.

### Mac Catalyst

- In the reader, a plain click still starts lookup from the clicked position.
- In the reader and dictionary popups, hovering over a word and then pressing `Shift` also starts lookup from the hovered position.
- Holding `Shift` and moving across words continues to trigger hover lookup.
- The hover trigger delay can be adjusted in the dictionary settings through `Mac Hover Delay`.
- The underlying scan logic is the same as iPhone/iPad once lookup is triggered.

### Paged Mode

In paged mode:

- `Left Arrow` and `Right Arrow` move between pages.
- Mouse wheel up/down moves to the previous/next page on Mac.
- If the current page is already at the start or end of the chapter, the reader moves to the previous or next chapter.

### Continuous Mode

In continuous mode:

- Arrow keys move by a large viewport-sized reading step rather than jumping directly by chapter.
- If the current chapter is already at the start or end and the user continues in that direction, the reader moves to the adjacent chapter.

## Layout Adjustments On Mac

The Mac build currently applies a lighter desktop layout treatment:

- Top and bottom reader chrome use smaller insets than the iPhone/iPad layout.
- Dictionary search uses the top-layout presentation rather than a phone-style bottom tab offset.
- Bookshelf grids use a slightly wider minimum card width.

These changes are meant to reduce the “stretched phone app” feel without changing the reading model.

## Anki / Card Creation On Mac

Mac card creation is expected to use AnkiConnect.

Current behavior:

- On Mac, `useAnkiConnect` defaults to `true`.
- The default AnkiConnect address is `http://127.0.0.1:8765`.
- The Anki settings screen fetches decks and note models from AnkiConnect.
- Duplicate checks and note creation on Mac are performed through AnkiConnect.
- The iOS AnkiMobile callback flow is not intended for Mac use.

### Required Setup

To mine cards on Mac:

1. Install the AnkiConnect add-on in Anki.
2. Launch Anki on the same Mac.
3. Confirm AnkiConnect is reachable at `http://127.0.0.1:8765`, or update the configured address in `Advanced > AnkiConnect`.
4. Use `Fetch decks and models from AnkiConnect` in the Anki settings screen.

## iOS-Only Features

The following behavior remains iOS-only for now:

- The Share Extension is embedded only in iOS builds.
- The AnkiMobile callback + pasteboard bridge is not the intended Mac path.

## Build Verification

The current Mac Catalyst target is verified with an unsigned build command such as:

```bash
xcodebuild -quiet -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader' -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Known Gaps

The Mac build still has room to improve:

- The app still uses several UIKit-based interaction layers through Catalyst.
- Continuous mode keyboard behavior is step-based, not yet a fully native desktop scrolling model.
- Reader presentation still uses UIKit/Catalyst navigation rather than a dedicated macOS scene model.
- iOS-only integrations are intentionally reduced instead of fully redesigned for Mac.
