import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var selectedReaderBook: BookMetadata?
    @State private var showReaderRegressionLab = false
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var dictionaryRequest: NativeDictionaryOpenRequest?
    #if DEBUG
    @State private var showReaderRegressionLaunchOverlay = ReaderRegressionLabAvailability.shouldShowLaunchOverlay
    @State private var didOpenReaderRegressionLaunchScenario = false
    @State private var readerRegressionViewModel = BookshelfViewModel()
    @State private var readerRegressionSettingsSnapshot: NativeReaderRegressionSettingsSnapshot?
    @State private var readerRegressionBookmarkSnapshot: NativeReaderRegressionBookmarkSnapshot?
    #endif

    var body: some View {
        ZStack {
            NavigationSplitView {
                NativeMacSidebarView(selection: $selection)
            } detail: {
                NativeMacDetailView(
                    section: selectedSection,
                    selectedReaderBook: $selectedReaderBook,
                    showReaderRegressionLab: $showReaderRegressionLab,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL,
                    dictionaryRequest: dictionaryRequest
                )
            }

            if let book = selectedReaderBook {
                NativeReaderLoader(book: book) {
                    selectedReaderBook = nil
                    #if DEBUG
                    restoreNativeReaderRegressionStateIfNeeded()
                    #endif
                }
                .transition(.opacity)
                .zIndex(100)
            }

            #if DEBUG
            if showReaderRegressionLaunchOverlay {
                ReaderRegressionLabView {
                    importNativeReaderRegressionFixture()
                } onOpenScenario: { scenario in
                    showReaderRegressionLaunchOverlay = false
                    openNativeReaderRegressionScenario(scenario)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(200)
            }
            #endif
        }
        .toolbar(selectedReaderBook == nil ? .visible : .hidden, for: .windowToolbar)
        .onOpenURL(perform: handleOpenURL)
        #if DEBUG
        .sheet(isPresented: $showReaderRegressionLab) {
            ReaderRegressionLabView {
                showReaderRegressionLab = false
                importNativeReaderRegressionFixture()
            } onOpenScenario: { scenario in
                showReaderRegressionLab = false
                openNativeReaderRegressionScenario(scenario)
            }
            .frame(minWidth: 760, minHeight: 620)
        }
        .onAppear {
            openNativeReaderRegressionLaunchScenarioIfNeeded()
        }
        #endif
    }

    private var selectedSection: NativeMacSection {
        selection ?? .bookshelf
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

    #if DEBUG
    private func openNativeReaderRegressionLaunchScenarioIfNeeded() {
        guard !didOpenReaderRegressionLaunchScenario,
              let scenario = ReaderRegressionLabAvailability.requestedScenario else {
            return
        }
        didOpenReaderRegressionLaunchScenario = true
        showReaderRegressionLaunchOverlay = false
        openNativeReaderRegressionScenario(scenario)
    }

    private func openNativeReaderRegressionScenario(_ scenario: ReaderRegressionScenarioPlan) {
        restoreNativeReaderRegressionStateIfNeeded()
        guard let book = readerRegressionViewModel.importReaderRegressionFixture(from: scenario.fixtureURL) else {
            return
        }

        readerRegressionSettingsSnapshot = NativeReaderRegressionSettingsSnapshot(userConfig: userConfig)
        readerRegressionBookmarkSnapshot = NativeReaderRegressionBookmarkSnapshot(book: book)
        scenario.apply(to: userConfig)
        scenario.writeInitialBookmark(for: book)
        selection = .bookshelf
        selectedReaderBook = book
    }

    private func importNativeReaderRegressionFixture() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.epub]
        if panel.runModal() == .OK {
            readerRegressionViewModel.importBooks(result: .success(panel.urls))
        }
    }

    private func restoreNativeReaderRegressionStateIfNeeded() {
        readerRegressionSettingsSnapshot?.restore(userConfig)
        readerRegressionSettingsSnapshot = nil
        readerRegressionBookmarkSnapshot?.restore()
        readerRegressionBookmarkSnapshot = nil
    }
    #endif
}

#if DEBUG
private struct NativeReaderRegressionSettingsSnapshot {
    let theme: Themes
    let verticalWriting: Bool
    let continuousMode: Bool
    let readerShowTitle: Bool
    let readerShowCharacters: Bool
    let readerShowPercentage: Bool
    let readerShowProgressTop: Bool

    init(userConfig: UserConfig) {
        theme = userConfig.theme
        verticalWriting = userConfig.verticalWriting
        continuousMode = userConfig.continuousMode
        readerShowTitle = userConfig.readerShowTitle
        readerShowCharacters = userConfig.readerShowCharacters
        readerShowPercentage = userConfig.readerShowPercentage
        readerShowProgressTop = userConfig.readerShowProgressTop
    }

    func restore(_ userConfig: UserConfig) {
        userConfig.theme = theme
        userConfig.verticalWriting = verticalWriting
        userConfig.continuousMode = continuousMode
        userConfig.readerShowTitle = readerShowTitle
        userConfig.readerShowCharacters = readerShowCharacters
        userConfig.readerShowPercentage = readerShowPercentage
        userConfig.readerShowProgressTop = readerShowProgressTop
    }
}

private struct NativeReaderRegressionBookmarkSnapshot {
    let url: URL
    let existed: Bool
    let data: Data?

    init?(book: BookMetadata) {
        guard let booksDirectory = try? BookStorage.getBooksDirectory() else {
            return nil
        }
        url = booksDirectory
            .appendingPathComponent(book.folder)
            .appendingPathComponent(FileNames.bookmark)
        existed = FileManager.default.fileExists(atPath: url.path)
        data = existed ? try? Data(contentsOf: url) : nil
    }

    func restore() {
        if existed {
            guard let data else { return }
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private extension ReaderRegressionScenarioPlan {
    func apply(to userConfig: UserConfig) {
        userConfig.theme = theme
        userConfig.verticalWriting = verticalWriting
        userConfig.continuousMode = continuousMode
        userConfig.readerShowTitle = true
        userConfig.readerShowCharacters = true
        userConfig.readerShowPercentage = true
        userConfig.readerShowProgressTop = progressTop
    }

    func writeInitialBookmark(for book: BookMetadata) {
        guard let booksDirectory = try? BookStorage.getBooksDirectory() else {
            return
        }
        let root = booksDirectory.appendingPathComponent(book.folder)
        let bookmark = Bookmark(
            chapterIndex: chapterIndex,
            progress: min(max(chapterProgress, 0), 0.98),
            characterCount: 0,
            lastModified: Date()
        )
        try? BookStorage.save(bookmark, inside: root, as: FileNames.bookmark)
    }
}
#endif
