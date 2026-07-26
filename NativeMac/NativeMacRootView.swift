import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(ReaderWindowCoordinator.self) private var readerWindowCoordinator
    @Environment(MangaWindowCoordinator.self) private var mangaWindowCoordinator
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    @State private var bookshelfViewModel = BookshelfViewModel()
    @State private var mangaLibraryViewModel = MangaLibraryViewModel()
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var dictionaryRequest: NativeDictionaryOpenRequest?

    var body: some View {
        rootContent
    }

    private var rootContent: some View {
        NavigationSplitView {
            NativeMacSidebarView(selection: $selection)
        } detail: {
            Group {
                NativeMacDetailView(
                    section: selectedSection,
                    bookshelfViewModel: bookshelfViewModel,
                    mangaLibraryViewModel: mangaLibraryViewModel,
                    onOpenBook: openBook,
                    onOpenManga: openManga,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL,
                    dictionaryRequest: dictionaryRequest,
                    onOpenVideo: openVideoWindow
                )
            }
        }
        .toolbar(.visible, for: .windowToolbar)
        .toolbarBackgroundVisibility(windowToolbarBackgroundVisibility, for: .windowToolbar)
        .task {
            await bookshelfViewModel.prepareInitialPresentation()
        }
        .task {
            mangaLibraryViewModel.load()
        }
        .onOpenURL(perform: handleOpenURL)
    }

    private var selectedSection: NativeMacSection {
        return selection ?? .bookshelf
    }

    private var windowToolbarBackgroundVisibility: Visibility {
        return .hidden
    }

    private func handleOpenURL(_ url: URL) {
        guard let route = AppOpenURLRoute(url: url) else {
            return
        }

        switch route {
        case .localFile(let url):
            if VideoMediaTypes.isMediaFile(url) {
                openVideoWindow(with: url)
                return
            }
            selection = .bookshelf
            pendingImportURL = url
        case .dictionarySearch(let query):
            selection = .dictionary
            dictionaryRequest = NativeDictionaryOpenRequest(query: query)
        case .remoteBook(let url):
            selection = .bookshelf
            pendingRemoteImportURL = url
        }
    }

    private func openVideoWindow(with url: URL, subtitleURL: URL? = nil) {
        openVideoWindow(source: .localFile(url), subtitleURL: subtitleURL)
    }

    private func openVideoWindow(source: VideoPlaybackSource, subtitleURL: URL? = nil) {
        VideoWindowPresenter.shared.open(
            source: source,
            subtitleURL: subtitleURL,
            coordinator: videoWindowCoordinator,
            userConfig: userConfig
        )
    }

    private func openBook(_ originalBook: BookMetadata) {
        let book = BookStorage.backfillBookLanguageIfNeeded(originalBook)
        if book != originalBook {
            openBook(book)
            return
        }

        ReaderWindowPresenter.shared.open(
            book: book,
            coordinator: readerWindowCoordinator,
            userConfig: userConfig
        )
    }

    private func openManga(
        _ item: MangaLibraryItem,
        _ source: MangaLibrarySource
    ) {
        MangaWindowPresenter.shared.open(
            item: item,
            source: source,
            coordinator: mangaWindowCoordinator,
            userConfig: userConfig
        )
    }

}
