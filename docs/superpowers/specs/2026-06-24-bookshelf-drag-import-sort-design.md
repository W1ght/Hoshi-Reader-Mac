# Bookshelf Drag Import And Sort Design

## Goal

Support two native macOS bookshelf gestures: dropping EPUB files onto the bookshelf to import them, and dragging local book cards to create a persistent manual order.

## Scope

- Local EPUB file drops on the bookshelf reuse the existing multi-book `importBooks` path.
- Local book cards can be dragged onto another local book card in the same visible section to reorder books.
- Reordering switches the bookshelf sort option to `Manual`, preserving existing `Recent` and `Title` sorting until the user drags.
- Shelved books persist order through the existing `BookShelf.bookIds` list.
- Unshelved books persist order in a lightweight bookshelf-level order file under the Books directory.
- Reading and Google Drive sections are read-only for ordering because they are derived or remote views.

## Architecture

`SortOption` gains `manual`. `BookshelfViewModel` owns reorder commands and persistence: shelf sections are sorted by shelf `bookIds`, unshelved sections use a new manual order list, and all manual lists append missing imported books so old data remains compatible. `ShelfView` owns card-level geometry tracking and drag gestures, then calls the view model rather than mutating arrays directly.

Finder file-drop commits use a narrow AppKit pasteboard bridge instead of SwiftUI `.dropDestination`, matching the existing Settings reorder workaround for macOS 26. The file-drop target lives on the bookshelf scroll/content area in both the tab-based and native reuse bookshelf shells. Dropped file URLs are filtered to `.epub` and passed to `importBooks(result:)`, so existing progress, security-scoped import handling, duplicate behavior, and error reporting remain unchanged.

## UI

The Sort menu gains a localized `Manual` option. Dragging a local book card over another local book card reorders within that section and switches the sort option to `Manual`. Finder EPUB drops use file-url pasteboard data. No separate edit mode is required. Existing selection mode, Google Drive cards, context menus, and shelf management remain unchanged.

## Testing

Add a source contract for the drag/drop hooks and a pure Swift test for reorder payloads and destination offsets. Run those tests, the existing bookshelf layout contract, catalog JSON validation, `git diff --check`, and the native Light build/launch verification.
