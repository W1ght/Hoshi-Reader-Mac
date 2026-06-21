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
    @State private var pendingEnglishProfileBook: BookMetadata?
    @State private var allowCurrentProfileBookID: UUID?
    @State private var profileRepository = ProfileRepository.shared

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
        .onChange(of: selectedSection) { _, _ in
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

    private func activateCurrentProfileContext() {
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
        ProfileActivationCoordinator.activate(
            .book(profileID: book.profileId, bookLanguage: book.bookLanguage),
            userConfig: userConfig,
            repository: repository
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
            selectedReaderBook = book
        } catch {
            pendingEnglishProfileBook = nil
        }
    }

}
