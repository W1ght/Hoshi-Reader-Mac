import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    let isKeyWindow: Bool

    @Environment(UserConfig.self) private var userConfig
    @Environment(ReaderWindowCoordinator.self) private var readerWindowCoordinator
    #if HOSHI_VIDEO
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var dictionaryRequest: NativeDictionaryOpenRequest?
    @State private var pendingEnglishProfileBook: BookMetadata?
    @State private var allowCurrentProfileBookID: UUID?
    @State private var profileRepository = ProfileRepository.shared
    #if HOSHI_VIDEO
    @State private var lastNonVideoSection: NativeMacSection = .bookshelf
    @State private var isSelectingVideoFile = false
    #endif

    var body: some View {
        #if HOSHI_VIDEO
        rootContent
            .fileImporter(
                isPresented: $isSelectingVideoFile,
                allowedContentTypes: VideoMediaTypes.contentTypes,
                allowsMultipleSelection: false,
                onCompletion: handleVideoFileImport
            )
        #else
        rootContent
        #endif
    }

    private var rootContent: some View {
        NavigationSplitView {
            NativeMacSidebarView(selection: $selection)
        } detail: {
            NativeMacDetailView(
                section: selectedSection,
                onOpenBook: openBook,
                pendingImportURL: $pendingImportURL,
                pendingRemoteImportURL: $pendingRemoteImportURL,
                dictionaryRequest: dictionaryRequest
            )
            .id(selectedSection)
        }
        .toolbar(isWindowToolbarVisible ? .visible : .hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(windowToolbarBackgroundVisibility, for: .windowToolbar)
        .onOpenURL(perform: handleOpenURL)
        .onAppear {
            activateCurrentProfileContext()
        }
        .onChange(of: isKeyWindow) { _, isKeyWindow in
            guard isKeyWindow else { return }
            activateCurrentProfileContext()
        }
        .onChange(of: selection) { _, newSelection in
            #if HOSHI_VIDEO
            if newSelection == .video {
                selection = lastNonVideoSection
                isSelectingVideoFile = true
                return
            }
            if let newSelection {
                lastNonVideoSection = newSelection
            }
            #endif
            activateCurrentProfileContext()
        }
        .onChange(of: profileRepository.index.globalActiveProfileId) { _, _ in
            activateCurrentProfileContext()
        }
        .onChange(of: profileRepository.storedVideoProfileID) { _, _ in
            activateCurrentProfileContext()
        }
        .alert(
            "Create an English Profile?",
            isPresented: Binding(
                get: { pendingEnglishProfileBook != nil },
                set: { if !$0 { pendingEnglishProfileBook = nil } }
            )
        ) {
            Button("Create English Profile") {
                createEnglishProfileAndOpen()
            }
            Button("Use Current Profile") {
                guard let book = pendingEnglishProfileBook else { return }
                pendingEnglishProfileBook = nil
                allowCurrentProfileBookID = book.id
                openBook(book)
            }
            Button("Cancel", role: .cancel) {
                pendingEnglishProfileBook = nil
            }
        } message: {
            Text("This book is marked as English. An English Profile keeps its dictionaries, Reader appearance and Anki fields separate.")
        }
    }

    private var selectedSection: NativeMacSection {
        #if HOSHI_VIDEO
        if selection == .video {
            return lastNonVideoSection
        }
        #endif
        return selection ?? .bookshelf
    }

    private var isWindowToolbarVisible: Bool {
        #if HOSHI_VIDEO
        if selectedSection == .video {
            return false
        }
        #endif
        return true
    }

    private var windowToolbarBackgroundVisibility: Visibility {
        return .hidden
    }

    private func activateCurrentProfileContext() {
        guard isKeyWindow else { return }
        #if HOSHI_VIDEO
        if selectedSection == .video {
            ProfileActivationCoordinator.activate(
                .video(profileID: profileRepository.videoProfileID),
                userConfig: userConfig,
                repository: profileRepository
            )
            return
        }
        #endif

        ProfileActivationCoordinator.activate(
            .global,
            userConfig: userConfig,
            repository: profileRepository
        )
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
    private func handleVideoFileImport(_ result: Result<[URL], any Error>) {
        guard let url = try? result.get().first else { return }
        openVideoWindow(with: url)
    }

    private func openVideoWindow(with url: URL) {
        videoWindowCoordinator.requestOpen(url)
        openWindow(id: VideoWindowCoordinator.windowID)
    }
    #endif

    private func openBook(_ originalBook: BookMetadata) {
        let book = BookStorage.backfillBookLanguageIfNeeded(originalBook)
        if book != originalBook {
            openBook(book)
            return
        }

        let repository = profileRepository
        if ContentLanguageProfile.normalize(book.bookLanguage) == .english,
           repository.profiles(for: .english).isEmpty,
           allowCurrentProfileBookID != book.id {
            pendingEnglishProfileBook = book
            return
        }
        allowCurrentProfileBookID = nil
        ReaderWindowPresenter.shared.open(
            book: book,
            coordinator: readerWindowCoordinator,
            userConfig: userConfig
        )
    }

    private func createEnglishProfileAndOpen() {
        guard let book = pendingEnglishProfileBook else { return }
        do {
            let repository = profileRepository
            let profile = try repository.createProfile(
                name: "English",
                language: .english,
                copyFromProfileID: nil
            )
            ProfileSettingsStore.shared.copyReaderSettings(
                from: ProfileSettingsStore.shared.appliedProfileID,
                to: profile.id
            )
            try repository.setPrimaryProfile(profile.id, for: .english)
            pendingEnglishProfileBook = nil
            openBook(book)
        } catch {
            pendingEnglishProfileBook = nil
        }
    }

}
