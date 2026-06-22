import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeMacRootView: View {
    let isKeyWindow: Bool

    @Environment(UserConfig.self) private var userConfig
    #if HOSHI_VIDEO
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var selectedReaderBook: BookMetadata?
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
                .id(selectedSection)
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
        .onChange(of: selectedReaderBook) { _, book in
            if let book {
                prepareReader(for: book)
            } else if pendingEnglishProfileBook == nil {
                activateCurrentProfileContext()
            }
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
                selectedReaderBook = book
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
        guard selectedReaderBook == nil else { return false }
        #if HOSHI_VIDEO
        if selectedSection == .video {
            return false
        }
        #endif
        return true
    }

    private func activateCurrentProfileContext() {
        guard isKeyWindow else { return }
        if let book = selectedReaderBook {
            ProfileActivationCoordinator.activate(
                .book(profileID: book.profileId, bookLanguage: book.bookLanguage),
                userConfig: userConfig,
                repository: profileRepository
            )
            return
        }

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

        selectedReaderBook = nil
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

    private func prepareReader(for originalBook: BookMetadata) {
        let book = BookStorage.backfillBookLanguageIfNeeded(originalBook)
        if book != originalBook {
            selectedReaderBook = book
            return
        }

        let repository = profileRepository
        if ContentLanguageProfile.normalize(book.bookLanguage) == .english,
           repository.profiles(for: .english).isEmpty,
           allowCurrentProfileBookID != book.id {
            selectedReaderBook = nil
            pendingEnglishProfileBook = book
            return
        }
        allowCurrentProfileBookID = nil
        if isKeyWindow {
            ProfileActivationCoordinator.activate(
                .book(profileID: book.profileId, bookLanguage: book.bookLanguage),
                userConfig: userConfig,
                repository: repository
            )
        }
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
            selectedReaderBook = book
        } catch {
            pendingEnglishProfileBook = nil
        }
    }

}
