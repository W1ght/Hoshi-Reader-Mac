import Foundation

private let shelfView = try String(contentsOfFile: "Features/Bookshelf/ShelfView.swift", encoding: .utf8)
private let bookView = try String(contentsOfFile: "Features/Bookshelf/BookView.swift", encoding: .utf8)
private let bookCell = try String(contentsOfFile: "Features/Bookshelf/BookCell.swift", encoding: .utf8)
private let bookshelfModel = try String(contentsOfFile: "Features/Bookshelf/BookshelfViewModel.swift", encoding: .utf8)
private let nativeBookshelf = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)
private let bookshelfDropSupport = (try? String(contentsOfFile: "Features/Bookshelf/BookshelfDropSupport.swift", encoding: .utf8)) ?? ""
private let project = try String(contentsOfFile: "Hoshi Reader.xcodeproj/project.pbxproj", encoding: .utf8)

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
    "var width: CGFloat = BookshelfLayout.v050CoverWidth",
    "Book covers should default to the v0.5.0 visual width before material/background is applied"
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

assertNotContains(
    bookCell,
    "ShareLink(item:",
    "Local book export should not present the macOS share picker from a transient context-menu item"
)

assertNotContains(
    bookCell,
    "@State private var pendingExportURL: URL?",
    "Local book export should not keep presentation state inside BookCell because context-menu state can drift away from the current grid cell"
)

assertContains(
    bookCell,
    "var onExport: (URL) -> Void",
    "Local book export should route the selected file URL to the owning ShelfView"
)

assertContains(
    bookCell,
    "@Binding var presentedExportURL: URL?",
    "BookCell should receive export presentation state from ShelfView instead of owning context-menu state"
)

assertContains(
    bookCell,
    "onExport(exportURL)",
    "Local book export should ask ShelfView to present from the current book frame"
)

assertContains(
    bookCell,
    "BookExportShareAnchor(fileURL: $presentedExportURL)",
    "Local book export should keep the AppKit share anchor inside the current BookCell card"
)

assertContains(
    bookCell,
    "BookRenameDraft(book: book, title: book.displayTitle)",
    "Book rename should create a fresh draft from the current display title each time the rename action opens"
)

assertContains(
    bookCell,
    ".sheet(item: $renameDraft)",
    "Book rename should use item-driven sheet presentation so Cancel/Esc resets presentation state before reopening"
)

assertNotContains(
    bookCell,
    "@State private var showRenameAlert = false",
    "Book rename should not key the alert only by a Bool because macOS SwiftUI alert text fields can reuse stale field state"
)

assertNotContains(
    bookCell,
    ".alert(\"Rename\", isPresented:",
    "Book rename should not use a context-menu-triggered alert because it can fail to re-present after Cancel/Esc on macOS"
)

assertContains(
    bookCell,
    ".buttonStyle(.plain)\n        .overlay(alignment: .bottom) {\n            BookExportShareAnchor(fileURL: $presentedExportURL)\n                .frame(width: 1, height: 1)\n                .allowsHitTesting(false)\n        }\n        .contextMenu",
    "Local book export should attach a deterministic 1x1 AppKit share anchor to the bottom center of the current BookCell root"
)

assertContains(
    shelfView,
    "@State private var pendingExport: BookExportPresentation?",
    "ShelfView should own local export presentation state for the exact grid cell that invoked export"
)

assertContains(
    shelfView,
    "pendingExport = BookExportPresentation(bookID: book.id, fileURL: url)",
    "ShelfView should remember the exact book id whose context menu requested export"
)

assertContains(
    shelfView,
    "presentedExportURL: exportBinding(for: book.id),",
    "ShelfView should pass export presentation state only to the BookCell for the current book id"
)

assertContains(
    shelfView,
    "private func exportBinding(for bookID: UUID) -> Binding<URL?>",
    "ShelfView should clear the pending export when the current cell's share picker has opened"
)

assertContains(
    bookCell,
    "context.coordinator.presentedURL = fileURL\n        let coordinator = context.coordinator\n        DispatchQueue.main.async {",
    "Local book export should defer NSSharingServicePicker presentation until after the context menu action has unwound"
)

assertContains(
    shelfView,
    "private struct BookExportPresentation: Identifiable",
    "Local book export should carry a stable presentation id while the share picker opens"
)

assertContains(
    bookCell,
    "struct BookExportShareAnchor: NSViewRepresentable",
    "Local book export should use an AppKit NSViewRepresentable anchor for reliable macOS popover placement"
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
    shelfView,
    "private static let compactCoverWidth: CGFloat = 80",
    "Collapsed shelves should use the upstream compact cover preview width"
)

assertContains(
    shelfView,
    "self._isCollapsed = State(initialValue: !section.isReading)",
    "Regular bookshelf folders should start collapsed while the Reading shelf stays expanded"
)

assertContains(
    shelfView,
    "if isCollapsed && section.shelf != nil",
    "Collapsed folders should render compact previews instead of the full book grid"
)

assertContains(
    shelfView,
    "BookCover(book: book, width: Self.compactCoverWidth)",
    "Collapsed folder previews should render compact covers"
)

assertContains(
    shelfView,
    "isCollapsed = false",
    "Clicking a collapsed folder preview should expand the shelf"
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

assertContains(
    bookshelfModel,
    "func moveBook(_ sourceID: UUID, in section: ShelfSection, before targetID: UUID)",
    "Bookshelf view model should expose a section-scoped drag reorder command"
)

assertContains(
    bookshelfModel,
    "BookStorage.saveBookOrder(manualBookOrder)",
    "Unshelved manual order should be persisted outside shelf membership"
)

assertContains(
    project,
    "Bookshelf/BookshelfDropSupport.swift",
    "Bookshelf AppKit file drop bridge must be included in the Xcode synchronized root target membership"
)

assertContains(
    shelfView,
    "BookshelfBookFramePreferenceKey",
    "Shelf should record book card frames for direct drag-reorder gestures"
)

assertContains(
    bookCell,
    "DragGesture(minimumDistance: 8, coordinateSpace: .named(dragCoordinateSpaceName))",
    "Book sorting should include a direct drag gesture on the book button label"
)

assertContains(
    bookCell,
    ".highPriorityGesture(",
    "Book sorting drag should take priority over the book button tap gesture once movement starts"
)

assertContains(
    bookCell,
    ".onChanged { value in\n                            onDragChanged(value.location)",
    "Book drag gestures should reorder while dragging, not only on mouse-up"
)

assertContains(
    shelfView,
    "dragCoordinateSpaceName: section.isReading ? nil : coordinateSpaceName",
    "Shelf should pass its named coordinate space into local book card drag gestures"
)

assertContains(
    shelfView,
    "onDragChanged: section.isReading ? nil : { location in\n                                reorderBook(book.id, draggedTo: location)",
    "Book drag gestures should route reorder drops through the same view-model command"
)

assertContains(
    bookshelfDropSupport,
    "struct BookshelfFileDropTarget<Content: View>: NSViewRepresentable",
    "Bookshelf file drops should use AppKit pasteboard file URLs from Finder"
)

assertContains(
    bookshelfDropSupport,
    "registerForDraggedTypes([.fileURL])",
    "Bookshelf file drop targets should register Finder file URL pasteboard types"
)

assertContains(
    bookshelfDropSupport,
    "URL(dataRepresentation: data, relativeTo: nil)",
    "Finder file drops should decode file-url pasteboard data into URLs"
)

assertContains(
    nativeBookshelf,
    "BookshelfFileDropTarget(",
    "Native Bookshelf should accept dropped EPUB file URLs through the AppKit file drop bridge"
)

assertContains(
    shelfView,
    "viewModel.moveBook(sourceID, in: section, before: targetID)",
    "Shelf drag gestures should route reorders through the view model"
)

assertContains(
    bookshelfModel,
    "case .manual:",
    "Bookshelf sorting should include a manual order path"
)

assertNotContains(
    nativeBookshelf,
    "if !viewModel.downloadingBooks.isEmpty",
    "Google Drive book downloads should not place a blocking overlay over the native Bookshelf"
)

assertContains(
    nativeBookshelf,
    ".onChange(of: selectedReaderBook) { oldBook, newBook in\n            guard oldBook != nil, newBook == nil else { return }\n            viewModel.loadBooks()\n        }",
    "Native Bookshelf should reload saved reading progress as the Reader closes"
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
