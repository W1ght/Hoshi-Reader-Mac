# Bookshelf Reader Progress Refresh Design

## Problem

The native Reader saves `bookmark.json` as page progress changes, but the native bookshelf only reloads its cached progress in `onAppear`. Because the Reader is presented as an overlay, closing it with Escape or the lower-left close button reveals the already-mounted bookshelf without triggering `onAppear`. Navigating to another section and back recreates the bookshelf and exposes the saved progress.

## Design

Keep bookmark persistence and Reader dismissal unchanged. In `NativeBookshelfReuseView`, observe the existing `selectedReaderBook` binding. When it changes from a book to `nil`, call the existing `BookshelfViewModel.loadBooks()` method so the cached progress and metadata are refreshed as the Reader closes.

This keeps ownership of bookshelf state inside the bookshelf view, covers every Reader close path that clears the binding, and avoids global notifications or rebuilding the entire navigation detail.

## Verification

- Add a source contract proving the native bookshelf reloads when `selectedReaderBook` transitions from non-`nil` to `nil`.
- Run the contract before implementation and confirm it fails for the missing refresh.
- Apply the minimal view change and confirm the contract passes.
- Run the Reader regression contract and launch the exact Light build with `--verify`.
- If safe test EPUB interaction is unavailable, report that the final Escape/button visual check remains manual.
