# Bookshelf Drag Import And Sort Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native bookshelf EPUB file drops and persistent manual drag sorting for local books.

**Architecture:** Add a manual sort option plus a small reorder helper in `Models/Book.swift`, persist unshelved manual order through `BookStorage`, and route all reorder mutations through `BookshelfViewModel`. Book cards use a direct SwiftUI geometry drag gesture for in-app sorting, while a narrow AppKit pasteboard drop target commits Finder file drops reliably on macOS.

**Tech Stack:** Swift 6, SwiftUI drag sources, AppKit pasteboard drop targets, existing source-contract scripts, native macOS build scripts.

---

### Task 1: Failing Contracts

**Files:**
- Create: `script/test_bookshelf_drag_sort.swift`
- Modify: `script/test_bookshelf_layout_contract.swift`

- [ ] Add a pure Swift test for `BookReorder.payload`, `BookReorder.bookID(from:)`, and `BookReorder.destinationOffset(sourceIndex:targetIndex:)`.
- [ ] Extend the bookshelf source contract to require `SortOption.manual`, `book_order.json`, `moveBook(_:in:before:)`, card `.onDrag`, `BookshelfBookDropTarget`, `BookshelfFileDropTarget`, and Xcode target membership for the bridge.
- [ ] Run both tests and confirm they fail because the feature is absent.

### Task 2: Reorder Model And Persistence

**Files:**
- Modify: `Models/Book.swift`
- Modify: `Core/BookStorage.swift`

- [ ] Add `SortOption.manual` with the existing raw-value storage pattern.
- [ ] Add `BookReorder` with scoped string payload parsing and destination-offset logic.
- [ ] Add `FileNames.bookOrder = "book_order.json"`.
- [ ] Add `BookStorage.loadBookOrder()` and `BookStorage.saveBookOrder(_:)`.
- [ ] Run `swift script/test_bookshelf_drag_sort.swift` and confirm it passes.

### Task 3: View Model Ordering

**Files:**
- Modify: `Features/Bookshelf/BookshelfViewModel.swift`

- [ ] Load and normalize manual order alongside books and shelves.
- [ ] Sort shelf sections manually from `BookShelf.bookIds` and unshelved sections from the new order file.
- [ ] Add `moveBook(_:in:before:)` to reorder only within the target section and persist the right backing store.
- [ ] Keep imported and deleted books synchronized with the manual order.
- [ ] Run `swift script/test_bookshelf_layout_contract.swift`.

### Task 4: Book Drag And AppKit File Drop

**Files:**
- Create: `Features/Bookshelf/BookshelfDropSupport.swift`
- Modify: `Features/Bookshelf/ShelfView.swift`
- Modify: `Features/Bookshelf/BookshelfView.swift`
- Modify: `NativeMac/NativeReuseViews.swift`
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj`
- Modify: `Localizable.xcstrings`
- Modify: `docs/CHANGELOG.md`

- [ ] Add localized Manual sort labels in both bookshelf shells.
- [ ] Add card frame tracking and a high-priority `DragGesture` to local `BookCell` cards, then commit reorders through `BookshelfViewModel`.
- [ ] Add `BookshelfFileDropTarget` using `NSViewRepresentable`, `.fileURL`, and `URL(dataRepresentation:relativeTo:)`.
- [ ] Wrap bookshelf content in `BookshelfFileDropTarget` in both shells and pass EPUB URLs to `viewModel.importBooks`.
- [ ] Add `Bookshelf/BookshelfDropSupport.swift` to the Xcode synchronized root membership exceptions for the app target.
- [ ] Add the user-visible changelog entry.
- [ ] Run the source contracts and JSON validation.

### Task 5: Verification

**Files:**
- Verify all changed files.

- [ ] Run `swift script/test_bookshelf_drag_sort.swift`.
- [ ] Run `swift script/test_bookshelf_layout_contract.swift`.
- [ ] Run `jq empty Localizable.xcstrings`.
- [ ] Run `git diff --check`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Report any UI drag/drop scenarios not manually exercised with the exact built app.
