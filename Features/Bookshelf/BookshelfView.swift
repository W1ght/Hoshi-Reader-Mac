//
//  BookshelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit
import UniformTypeIdentifiers

struct BookshelfView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel = BookshelfViewModel()
    @State private var showDictionaries = false
    @State private var showAnkiSettings = false
    @State private var showAppearance = false
    @State private var showAdvanced = false
    @State private var showAbout = false
    @State private var showShelfManagement = false
    @State private var selectedTab = 0
    @State private var focusDictionarySearch = false
    @State private var setInitialTab = false
    @State private var navigationPath = NavigationPath()
    @State private var dictionaryRoute = DictionaryRoute()
    @State private var isSelecting = false
    @State private var selectedBooks = Set<BookMetadata>()
    @State private var showBulkDeleteConfirmation = false
    @State private var sasayakiBook: BookMetadata?
    @State private var selectedReaderBook: BookMetadata?
    @State private var updateChecker = UpdateChecker()
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?

    private var sepiaInverted: Bool {
        userConfig.theme == .sepia && userConfig.sepiaInvertInDark && systemColorScheme == .dark
    }

    private var readerChromeBackground: Color {
        if sepiaInverted {
            return Color(red: 0.094, green: 0.082, blue: 0.047)
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return Color(red: 0.949, green: 0.886, blue: 0.788)
        }
        return userConfig.theme == .custom ? userConfig.customBackgroundColor : Color(.systemBackground)
    }

    private func switchRootTab(_ tab: Int, leavingReader: Bool = false) {
        if tab == 1 && selectedTab == 1 {
            focusDictionarySearch.toggle()
        }

        if leavingReader || tab != 0 {
            selectedReaderBook = nil
            navigationPath = NavigationPath()
        }

        if leavingReader {
            DispatchQueue.main.async {
                selectedTab = tab
            }
        } else {
            selectedTab = tab
        }
    }

    var body: some View {
        ZStack {
            if selectedTab == 0, let selectedReaderBook {
                ReaderLoader(book: selectedReaderBook)
                    .environment(userConfig)
                    .environment(\.dismissReader) {
                        self.selectedReaderBook = nil
                        selectedTab = 0
                        viewModel.loadBooks()
                    }
                    .environment(\.openReaderTab) { tab in
                        switchRootTab(tab, leavingReader: true)
                    }
                    .transition(.opacity)
            } else {
                TabView(selection: Binding(get: { selectedTab }, set: { newTab in
                    switchRootTab(newTab)
                })) {
                    NavigationStack(path: $navigationPath) {
                        ScrollView {
                            let sections = viewModel.shelfSections(sortedBy: userConfig.bookshelfSortOption, showReading: userConfig.bookshelfShowReading)
                            if viewModel.books.isEmpty {
                                ContentUnavailableView {
                                    Label("No Books", systemImage: "books.vertical")
                                } description: {
                                    Text("Import an EPUB using the \(Image(systemName: "plus")) button to start reading.")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 160)
                            } else {
                                ForEach(sections) { section in
                                    if section.books.count > 0 {
                                        ShelfView(
                                            viewModel: viewModel,
                                            section: section,
                                            showTitle: sections.count > 1,
                                            isSelecting: isSelecting,
                                            selectedBooks: $selectedBooks,
                                            pendingLookup: $pendingLookup,
                                            pendingTab: $pendingTab,
                                            selectedReaderBook: $selectedReaderBook,
                                            onMatch: { sasayakiBook = $0 }
                                        )
                                    }
                                }
                            }
                        }
                        .navigationTitle("Books")
                        .scrollIndicators(.hidden)
                        .toolbar {
                            toolbarContent
                        }
                        .onAppear {
                            viewModel.loadBooks()
                        }
                        .fileImporter(
                            isPresented: $viewModel.isImporting,
                            allowedContentTypes: [.epub],
                            allowsMultipleSelection: true,
                            onCompletion: viewModel.importBooks
                        )
                        .sheet(isPresented: $showShelfManagement) {
                            ShelfManagementView(viewModel: viewModel)
                        }
                        .sheet(item: $sasayakiBook) { book in
                            SasayakiMatchView(book: book, viewModel: viewModel)
                        }
                        .alert(
                            "Delete \(selectedBooks.count) book(s)?",
                            isPresented: $showBulkDeleteConfirmation
                        ) {
                            Button("Delete", role: .destructive) {
                                viewModel.deleteBooks(selectedBooks)
                                clearSelection()
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                    }
                    .tabItem {
                        Label("Books", systemImage: "books.vertical")
                    }
                    .tag(0)
                    .onChange(of: selectedTab) {
                        clearSelection()
                    }

                    NavigationStack {
                        DictionarySearchView(
                            initialQuery: dictionaryRoute.query,
                            initialAutofocus: dictionaryRoute.autofocus,
                            shouldFocus: focusDictionarySearch
                        )
                        .id(dictionaryRoute.id)
                    }
                    .tabItem {
                        Label("Dictionary", systemImage: "character.magnify.ja")
                    }
                    .tag(1)

                    NavigationStack {
                        List {
                            Button {
                                showDictionaries = true
                            } label: {
                                Label("Dictionaries", systemImage: "character.book.closed.ja")
                            }
                            .foregroundStyle(.primary)
                            Button {
                                showAnkiSettings = true
                            } label: {
                                Label("Anki", systemImage: "tray.full")
                            }
                            .foregroundStyle(.primary)
                            Button {
                                showAppearance = true
                            } label: {
                                Label("Appearance", systemImage: "paintpalette")
                            }
                            .foregroundStyle(.primary)
                            Button {
                                showAdvanced = true
                            } label: {
                                Label("Advanced", systemImage: "gearshape.2")
                            }
                            .foregroundStyle(.primary)

                            Section {
                                Link(destination: URL(string: "https://github.com/W1ght/Hoshi-Reader-for-Mac/issues")!) {
                                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                                }
                                Button {
                                    showAbout = true
                                } label: {
                                    Label("About", systemImage: "info.circle")
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        .navigationTitle("Settings")
                        .navigationDestination(isPresented: $showDictionaries) {
                            DictionaryView()
                        }
                        .navigationDestination(isPresented: $showAnkiSettings) {
                            AnkiView()
                        }
                        .navigationDestination(isPresented: $showAdvanced) {
                            AdvancedView()
                        }
                        .navigationDestination(isPresented: $showAbout) {
                            AboutView()
                        }
                        .navigationDestination(isPresented: $showAppearance) {
                            AppearanceView(userConfig: userConfig, showDismiss: false)
                        }
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(2)
                }
            }
        }
        .background {
            if AppPlatform.usesDesktopLayout {
                ReaderChromeBackgroundSync(
                    isActive: selectedReaderBook != nil && selectedTab == 0,
                    backgroundColor: UIColor(readerChromeBackground)
                )
                .frame(width: 0, height: 0)
            }
        }
        .onChange(of: pendingTab) { _, tab in
            if let tab {
                switchRootTab(tab, leavingReader: selectedReaderBook != nil)
                pendingTab = nil
            }
        }
        .onChange(of: pendingLookup) { _, text in
            if let text {
                dictionaryRoute = DictionaryRoute(
                    query: text,
                    autofocus: text.isEmpty
                )
                switchRootTab(1, leavingReader: selectedReaderBook != nil)
                pendingLookup = nil
            }
        }
        .onChange(of: pendingImportURL) { _, url in
            if let url {
                navigationPath = NavigationPath()
                if url.pathExtension == "colpkg" || url.pathExtension == "apkg" {
                    do {
                        try AnkiManager.shared.importAnkiBackup(from: url)
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.shouldShowError = true
                    }
                } else {
                    viewModel.importBook(result: .success(url))
                }
                viewModel.clearInbox()
                pendingImportURL = nil
            }
        }
        .onChange(of: pendingRemoteImportURL) { _, url in
            if let url {
                navigationPath = NavigationPath()
                viewModel.importRemoteBook(from: url)
                pendingRemoteImportURL = nil
            }
        }
        .alert("Error", isPresented: $viewModel.shouldShowError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("", isPresented: $viewModel.shouldShowSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.successMessage)
        }
        .alert(updateAlertTitle, isPresented: updateAlertBinding) {
            if case .available(let release, _) = updateChecker.alert {
                Button("Open Download Page") {
                    UIApplication.shared.open(release.pageURL)
                }
                Button("Later", role: .cancel) { }
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: {
            Text(updateAlertMessage)
        }
        .overlay {
            if viewModel.isSyncing {
                LoadingOverlay(String(localized: "Syncing..."))
            }
            if viewModel.isDownloading {
                LoadingOverlay(String(localized: "Downloading EPUB..."))
            }
            if let importBooksProgress = viewModel.importBooksProgress {
                LoadingOverlay(importBooksProgress)
            }
        }
        .onAppear {
            guard !setInitialTab else {
                return
            }
            selectedTab = userConfig.dictionaryTabDefault ? 1 : 0
            setInitialTab = true
        }
        .task {
            await updateChecker.checkAutomaticallyIfNeeded()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    clearSelection()
                }
                .fontWeight(.semibold)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.moveBooks(selectedBooks, to: nil)
                        clearSelection()
                    } label: {
                        Label("None", systemImage: "tray")
                    }
                    ForEach(viewModel.shelves, id: \.name) { shelf in
                        Button {
                            viewModel.moveBooks(selectedBooks, to: shelf.name)
                            clearSelection()
                        } label: {
                            Label(shelf.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(selectedBooks.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBulkDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedBooks.isEmpty)
            }
        } else {
            if AppPlatform.isMacCatalyst {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await updateChecker.check(manual: true)
                        }
                    } label: {
                        if updateChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: updateChecker.hasAvailableUpdate ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(updateChecker.hasAvailableUpdate ? .blue : .primary)
                        }
                    }
                    .disabled(updateChecker.isChecking)
                    .help(Text("Check for Updates"))
                    .accessibilityLabel(Text("Check for Updates"))
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section {
                        Text("Sorting by...")
                            .foregroundStyle(.secondary)
                        Picker("Sort", selection: Bindable(userConfig).bookshelfSortOption) {
                            ForEach(SortOption.allCases) { option in
                                Label(LocalizedStringKey(option.rawValue), systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.default.speed(2)) {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: "checklist")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShelfManagement = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
            }
            
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var updateAlertBinding: Binding<Bool> {
        Binding {
            updateChecker.alert != nil && selectedReaderBook == nil
        } set: { isPresented in
            if !isPresented {
                updateChecker.alert = nil
            }
        }
    }

    private var updateAlertTitle: String {
        switch updateChecker.alert {
        case .available:
            String(localized: "Update Available")
        case .upToDate:
            String(localized: "You're Up to Date")
        case .failed:
            String(localized: "Update Check Failed")
        case nil:
            ""
        }
    }

    private var updateAlertMessage: String {
        switch updateChecker.alert {
        case .available(let release, let currentVersion):
            String(
                format: String(localized: "Version %@ is available. You are using %@."),
                release.version,
                currentVersion
            )
        case .upToDate(let currentVersion):
            String(
                format: String(localized: "Hoshi Reader %@ is the latest version."),
                currentVersion
            )
        case .failed:
            String(localized: "Unable to check for updates. Please try again later.")
        case nil:
            ""
        }
    }

    private func clearSelection() {
        withAnimation(.default.speed(2)) {
            isSelecting = false
            selectedBooks.removeAll()
        }
    }
}

private struct DictionaryRoute {
    let id = UUID()
    let query: String
    let autofocus: Bool

    init(query: String = "", autofocus: Bool = true) {
        self.query = query
        self.autofocus = autofocus
    }
}

private struct ReaderChromeBackgroundSync: UIViewControllerRepresentable {
    var isActive: Bool
    var backgroundColor: UIColor

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.update(from: controller, isActive: isActive, backgroundColor: backgroundColor)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(from: uiViewController, isActive: isActive, backgroundColor: backgroundColor)
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.restore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: UIWindow?
        private var originalWindowBackground: UIColor?
        private var originalRootBackground: UIColor?

        func update(from controller: UIViewController, isActive: Bool, backgroundColor: UIColor) {
            guard let window = controller.view.window else {
                return
            }

            if self.window !== window {
                restore()
                self.window = window
                originalWindowBackground = window.backgroundColor
                originalRootBackground = window.rootViewController?.view.backgroundColor
            }

            guard isActive else {
                restore()
                return
            }

            window.backgroundColor = backgroundColor
            window.rootViewController?.view.backgroundColor = backgroundColor
        }

        func restore() {
            guard let window else {
                return
            }
            window.backgroundColor = originalWindowBackground
            window.rootViewController?.view.backgroundColor = originalRootBackground
            self.window = nil
            originalWindowBackground = nil
            originalRootBackground = nil
        }
    }
}
