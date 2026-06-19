import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var selectedReaderBook: BookMetadata?
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var dictionaryRequest: NativeDictionaryOpenRequest?

    var body: some View {
        ZStack {
            NavigationSplitView {
                NativeMacSidebarView(selection: $selection)
            } detail: {
                NativeMacDetailView(
                    section: selectedSection,
                    selectedReaderBook: $selectedReaderBook,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL,
                    dictionaryRequest: dictionaryRequest
                )
            }

            if let book = selectedReaderBook {
                NativeReaderLoader(book: book) {
                    selectedReaderBook = nil
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .toolbar(isWindowToolbarVisible ? .visible : .hidden, for: .windowToolbar)
        .onOpenURL(perform: handleOpenURL)
    }

    private var selectedSection: NativeMacSection {
        selection ?? .bookshelf
    }

    private var isWindowToolbarVisible: Bool {
        guard selectedReaderBook == nil else { return false }
        #if HOSHI_VIDEO
        if selectedSection == .video {
            return false
        }
        #endif
        return true
    }

    private func handleOpenURL(_ url: URL) {
        guard let route = AppOpenURLRoute(url: url) else {
            return
        }

        selectedReaderBook = nil
        switch route {
        case .localFile(let url):
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

}
