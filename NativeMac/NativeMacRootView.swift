import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(ReaderWindowCoordinator.self) private var readerWindowCoordinator
    #if HOSHI_VIDEO
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    #endif
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
                #if HOSHI_VIDEO
                NativeMacDetailView(
                    section: selectedSection,
                    onOpenBook: openBook,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL,
                    dictionaryRequest: dictionaryRequest,
                    onOpenVideo: openVideoWindow
                )
                #else
                NativeMacDetailView(
                    section: selectedSection,
                    onOpenBook: openBook,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL,
                    dictionaryRequest: dictionaryRequest
                )
                #endif
            }
        }
        .toolbar(.visible, for: .windowToolbar)
        .toolbarBackgroundVisibility(windowToolbarBackgroundVisibility, for: .windowToolbar)
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
            #if HOSHI_VIDEO
            if VideoMediaTypes.isMediaFile(url) {
                openVideoWindow(with: url)
                return
            }
            #endif
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

    #if HOSHI_VIDEO
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
    #endif

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

}
