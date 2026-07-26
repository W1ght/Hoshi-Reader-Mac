import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    let bookshelfViewModel: BookshelfViewModel
    let mangaLibraryViewModel: MangaLibraryViewModel
    let onOpenBook: (BookMetadata) -> Void
    let onOpenManga: (MangaLibraryItem, MangaLibrarySource) -> Void
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?
    let onOpenVideo: (VideoPlaybackSource, URL?) -> Void

    var body: some View {
        selectedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                switch section {
                case .bookshelf, .manga:
                    NativeShelfPageBackground()
                case .dictionary, .video, .settings:
                    NativeGlassPageBackground()
                }
            }
            .navigationTitle(section.title)
    }

    @ViewBuilder
    private var selectedContent: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(
                    viewModel: bookshelfViewModel,
                    onOpenBook: onOpenBook,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL
                )
            case .manga:
                MangaLibraryView(
                    onOpenManga: onOpenManga,
                    viewModel: mangaLibraryViewModel
                )
            case .dictionary:
                NativeDictionaryPlaceholderView(request: dictionaryRequest)
            case .video:
                VideoLibraryView(onOpenVideo: onOpenVideo)
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
    }
}
