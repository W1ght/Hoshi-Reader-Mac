import Foundation

private let shelfView = try String(contentsOfFile: "Features/Bookshelf/ShelfView.swift", encoding: .utf8)
private let bookView = try String(contentsOfFile: "Features/Bookshelf/BookView.swift", encoding: .utf8)
private let bookCell = try String(contentsOfFile: "Features/Bookshelf/BookCell.swift", encoding: .utf8)
private let bookshelfModel = try String(contentsOfFile: "Features/Bookshelf/BookshelfViewModel.swift", encoding: .utf8)
private let nativeBookshelf = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)

private func assertContains(_ source: String, _ needle: String, _ message: String) {
    guard source.contains(needle) else {
        fatalError("FAIL: \(message)\nMissing: \(needle)")
    }
}

private func assertNotContains(_ source: String, _ needle: String, _ message: String) {
    guard !source.contains(needle) else {
        fatalError("FAIL: \(message)\nUnexpected: \(needle)")
    }
}

assertContains(
    bookView,
    "static let v050CoverWidth: CGFloat = 160",
    "Bookshelf should keep the v0.5.0 Catalyst visual card width as an explicit layout token"
)

assertContains(
    shelfView,
    "minimum: BookshelfLayout.v050CoverWidth,\n                maximum: BookshelfLayout.v050CoverWidth",
    "Shelf grid should pin adaptive columns to the v0.5.0 Bookshelf width instead of letting SwiftUI stretch them"
)

assertContains(
    bookView,
    ".frame(width: BookshelfLayout.v050CoverWidth)",
    "Book cards should pin the cover/title stack to the v0.5.0 visual width instead of stretching with the grid cell"
)

assertContains(
    bookView,
    ".padding(3)\n            .frame(width: BookshelfLayout.v050CoverWidth)",
    "Book covers should also be pinned to the v0.5.0 visual width before material/background is applied"
)

assertContains(
    bookView,
    "static let progressTrackHeight: CGFloat = 3",
    "Bookshelf progress should use the compact v0.5.0-style track height instead of the native macOS ProgressView size"
)

assertContains(
    bookView,
    "BookProgressStrip(progress: progress)",
    "Book covers should render the compact Bookshelf progress strip"
)

assertNotContains(
    bookView,
    "ProgressView(value: progress)",
    "Bookshelf covers should not use the oversized native macOS ProgressView"
)

assertContains(
    bookCell,
    "Label(\"Profile\", systemImage: \"person.crop.circle\")",
    "Every local book must expose an in-place Profile menu"
)

assertContains(
    bookshelfModel,
    "func setProfile(_ profileID: String?, for book: BookMetadata)",
    "Per-book Profile overrides must be persisted through the bookshelf model"
)

assertNotContains(
    shelfView,
    "GridItem(.adaptive(minimum: 190)",
    "Bookshelf should not keep the oversized native-only adaptive minimum"
)

assertContains(
    nativeBookshelf,
    "if userConfig.enableSync && GoogleDriveAuth.shared.isAuthenticated",
    "Native Bookshelf should expose Google Drive refresh only when sync is enabled and authenticated"
)

assertContains(
    nativeBookshelf,
    "await viewModel.loadGoogleDriveBooks()",
    "Native Bookshelf Google Drive refresh should reuse the existing remote book loader"
)

assertContains(
    nativeBookshelf,
    "Label(\"Refresh Google Drive Books\", systemImage: \"icloud.and.arrow.down\")",
    "Native Bookshelf toolbar should include a visible Google Drive refresh action"
)

assertContains(
    nativeBookshelf,
    ".disabled(viewModel.isLoadingGoogleDriveBooks)",
    "Native Bookshelf should prevent duplicate Google Drive refresh requests"
)

assertNotContains(
    nativeBookshelf,
    "if !viewModel.downloadingBooks.isEmpty",
    "Google Drive book downloads should not place a blocking overlay over the native Bookshelf"
)

assertContains(
    bookshelfModel,
    "var downloadingBooks: [UUID: Double] = [:]",
    "Google Drive downloads should track progress independently for multiple books"
)

assertContains(
    bookshelfModel,
    "downloadingBooks[book.id] = 0\n        Task {",
    "Each Google Drive book download should launch its own asynchronous task"
)

print("Bookshelf layout contract passed")
