//
//  ZLibraryView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit
import SwiftUI

struct ZLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ZLibraryViewModel()
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isResultsFocused: Bool
    let isBookAlreadyImported: (ZLibraryBook) -> Bool
    let onImportEPUB: (URL, ZLibraryBook, ZLibraryBookDetails?) throws -> BookImportResult

    var body: some View {
        ZStack(alignment: .topTrailing) {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !model.isSignedIn {
                GlassEffectContainer(spacing: 10) {
                    closeButton
                }
                .padding(18)
            }

            keyboardShortcuts
        }
        .frame(
            minWidth: model.expandedBookID == nil ? 760 : 1_060,
            idealWidth: model.expandedBookID == nil ? 860 : 1_210,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 600,
            maxHeight: .infinity,
            alignment: .top
        )
        .alert("Error", isPresented: $model.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
        .alert("Use this Z-Library server?", isPresented: $model.showServerConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") {
                model.confirmServerAndSignIn()
            }
        } message: {
            Text("Your email and password will be sent to \(model.pendingServerHost) over HTTPS.")
        }
        .onDisappear {
            model.cancelSearch()
            model.cancelAllDownloads()
            model.cancelDetails()
        }
    }

    @ViewBuilder
    private var destination: some View {
        if model.isSignedIn {
            searchContent
        } else {
            signInContent
        }
    }

    private var closeButton: some View {
        Button(role: .cancel) {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .clipShape(Circle())
        .help("Close")
        .accessibilityLabel("Close")
    }

    private var accountMenu: some View {
        Menu {
            Text(model.serverURL)
            if model.isLoadingDownloadQuota {
                Label("Checking download limit...", systemImage: "arrow.clockwise")
            } else if let used = model.downloadQuota?.usedToday,
                      let limit = model.downloadQuota?.dailyLimit {
                Label {
                    Text("Downloads today: \(used) / \(limit)")
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            } else if let remaining = model.downloadQuota?.remaining {
                Label {
                    Text("Downloads remaining: \(remaining)")
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            }
            Button("Refresh Download Limit", systemImage: "arrow.clockwise") {
                Task { await model.refreshDownloadQuota(showError: true) }
            }
            Divider()
            Button("Sign out", role: .destructive) {
                model.signOut()
            }
        } label: {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .frame(width: 18, height: 18)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .controlSize(.large)
        .clipShape(Circle())
        .help("Account")
        .accessibilityLabel("Account")
    }

    private var signedInHeader: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Text("Z-Library")
                    .font(.title2.weight(.semibold))

                ZLibraryModeControl(
                    selection: model.contentMode,
                    onSelect: { model.selectContentMode($0) }
                )

                Spacer(minLength: 12)

                ZLibrarySearchField(
                    text: $model.query,
                    onSubmit: { model.startSearch() },
                    focus: $isSearchFocused,
                    recentQueries: model.recentQueries,
                    onSelectRecent: { model.selectRecentQuery($0) },
                    onRemoveRecent: { model.removeRecentQuery($0) },
                    onClearRecents: { model.clearRecentQueries() },
                    onFocusResults: {
                        isSearchFocused = false
                        isResultsFocused = true
                    }
                )
                .frame(width: 270)

                quotaStatus
                accountMenu
                closeButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var quotaStatus: some View {
        if let used = model.downloadQuota?.usedToday,
           let limit = model.downloadQuota?.dailyLimit {
            Label {
                Text("\(used) / \(limit)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .help("Downloads today: \(used) / \(limit)")
            .accessibilityLabel("Downloads today: \(used) / \(limit)")
        }
    }

    private var signInContent: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 46, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text("Search and import EPUB books")
                        .font(.title2.weight(.semibold))
                    Text("Sign in to search your Z-Library account. Your password is never saved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassEffectContainer(spacing: 18) {
                    VStack(spacing: 0) {
                        ZLibraryLoginField(title: "Server", systemImage: "network") {
                            TextField("https://article.sk", text: $model.serverURL)
                                .textContentType(.URL)
                        }

                        Divider().padding(.leading, 42)

                        ZLibraryLoginField(title: "Email", systemImage: "envelope") {
                            TextField("Email", text: $model.email)
                                .textContentType(.emailAddress)
                        }

                        Divider().padding(.leading, 42)

                        ZLibraryLoginField(title: "Password", systemImage: "lock") {
                            SecureField("Password", text: $model.password)
                                .textContentType(.password)
                                .onSubmit { model.requestSignIn() }
                        }

                        Divider().padding(.leading, 42)

                        HStack {
                            Label("Session tokens are protected by Keychain", systemImage: "key.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if model.isWorking {
                                ProgressView().controlSize(.small)
                            }
                            Button("Sign in") {
                                model.requestSignIn()
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(model.isWorking || model.email.isEmpty || model.password.isEmpty)
                        }
                        .padding(.top, 18)
                    }
                    .padding(24)
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                }
                .frame(maxWidth: 610)

                Label("Use this integration only for books you are legally allowed to access.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 54)
            .padding(.vertical, 52)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            signedInHeader

            Group {
                if model.contentMode == .search {
                    filterBar
                } else {
                    collectionBar
                }
            }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Group {
                if model.isWorking && model.books.isEmpty {
                    ProgressView(workingLabel)
                } else if model.books.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: model.contentMode.systemImage)
                    } description: {
                        Text(emptyDescription)
                    }
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: model.session?.userID) {
            await model.refreshDownloadQuota()
        }
        .onAppear {
            isSearchFocused = true
        }
        .inspector(isPresented: Binding(
            get: { model.expandedBookID != nil },
            set: { if !$0 { model.closeDetails() } }
        )) {
            if let book = model.selectedBook {
                ZLibraryBookDetailPanel(
                    book: book,
                    details: model.bookDetails[book.id],
                    isLoading: model.loadingDetailsBookID == book.id,
                    isAlreadyImported: isBookAlreadyImported(book),
                    queueItem: model.queueItem(for: book.id),
                    quota: model.downloadQuota,
                    onPrevious: { model.selectAdjacentBook(offset: -1) },
                    onNext: { model.selectAdjacentBook(offset: 1) },
                    onImport: { model.enqueueDownload(book, importEPUB: onImportEPUB) },
                    onCancel: { model.cancelDownload(bookID: book.id) }
                )
                .inspectorColumnWidth(min: 300, ideal: 350, max: 430)
            }
        }
    }

    private var workingLabel: LocalizedStringKey {
        switch model.contentMode {
        case .search: "Searching..."
        case .recent: "Loading recently added books..."
        case .history: "Loading download history..."
        }
    }

    private var emptyTitle: LocalizedStringKey {
        switch model.contentMode {
        case .search: "Search Z-Library"
        case .recent: "No Recently Added Books"
        case .history: "No Download History"
        }
    }

    private var emptyDescription: LocalizedStringKey {
        switch model.contentMode {
        case .search: "Search by title, author, ISBN, DOI, publisher, or keyword."
        case .recent: "Z-Library did not return any recently added EPUB books."
        case .history: "Books downloaded with this account will appear here."
        }
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("Focus Search") {
                isResultsFocused = false
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Previous Page") {
                model.goToPage(model.currentPage - 1)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!model.canGoBack || !isResultsFocused)

            Button("Next Page") {
                model.goToPage(model.currentPage + 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!model.canGoForward || !isResultsFocused)

            Button("Cancel") {
                if model.isWorking {
                    model.cancelSearch()
                } else if model.downloadingBookID != nil {
                    model.cancelDownload()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .clipped()
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var filterBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.exact.toggle()
                    model.persistSearchPreferences()
                } label: {
                    Label(
                        "Exact match",
                        systemImage: model.exact ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .contentShape(Capsule())
                    .glassEffect(
                        model.exact
                            ? .regular.tint(Color.accentColor.opacity(0.2)).interactive()
                            : .regular.interactive(),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.exact ? "On" : "Off")

                TextField("From year", text: Binding(
                    get: { model.yearFrom },
                    set: { model.setYearFrom($0) }
                ))
                    .nativeSettingsTextField()
                    .frame(width: 84)
                TextField("To year", text: Binding(
                    get: { model.yearTo },
                    set: { model.setYearTo($0) }
                ))
                    .nativeSettingsTextField()
                    .frame(width: 84)

                Menu {
                    ForEach(ZLibraryLanguage.allCases) { language in
                        Button {
                            model.language = language
                            model.persistSearchPreferences()
                        } label: {
                            if model.language == language {
                                Label {
                                    Text(language.title)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            } else {
                                Text(language.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text(model.language.title)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(.horizontal, 12)
                .frame(width: 140, height: 32)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())

                sortMenu

                if model.activeFilterCount > 0 {
                    Button {
                        model.resetFilters()
                    } label: {
                        Label("Reset Filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .labelStyle(.iconOnly)
                            .overlay(alignment: .topTrailing) {
                                Text("\(model.activeFilterCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(2)
                                    .background(Color.accentColor, in: Circle())
                                    .foregroundStyle(.white)
                                    .offset(x: 5, y: -5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Reset Filters")
                }

                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
                    .help("EPUB only")

                Spacer(minLength: 0)

                Button {
                    if model.isWorking {
                        model.cancelSearch()
                    } else {
                        model.startSearch()
                    }
                } label: {
                    Label(
                        model.isWorking ? "Cancel" : "Search",
                        systemImage: model.isWorking ? "xmark" : "magnifyingglass"
                    )
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                        .glassEffect(
                            .regular.tint(Color.accentColor.opacity(0.22)).interactive(),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.isWorking && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.regular)
        }
    }

    private var collectionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Label(model.contentMode.title, systemImage: model.contentMode.systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                sortMenu
                Button {
                    if model.isWorking {
                        model.cancelSearch()
                    } else {
                        model.refreshCurrentContent()
                    }
                } label: {
                    Label(
                        model.isWorking ? "Cancel" : "Refresh",
                        systemImage: model.isWorking ? "xmark" : "arrow.clockwise"
                    )
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Capsule())
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ZLibrarySortOrder.allCases) { order in
                Button {
                    model.setSortOrder(order)
                } label: {
                    if model.sortOrder == order {
                        Label(order.title, systemImage: "checkmark")
                    } else {
                        Text(order.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down")
                Text(model.sortOrder.title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Sort Results")
    }

    private var results: some View {
        List(selection: Binding(
            get: { model.selectedBookID },
            set: { model.updateSelection($0) }
        )) {
            ForEach(model.displayedBooks) { book in
                ZLibraryBookRow(
                    book: book,
                    isAlreadyImported: isBookAlreadyImported(book),
                    queueItem: model.queueItem(for: book.id),
                    onOpenDetails: { model.toggleDetails(for: book) },
                    onCancel: { model.cancelDownload(bookID: book.id) },
                    onDownload: { model.enqueueDownload(book, importEPUB: onImportEPUB) }
                )
                .tag(book.id)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: Binding(
            get: { model.scrollBookID },
            set: { model.updateScrollPosition($0) }
        ))
        .focused($isResultsFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up:
                if model.selectedBookID == model.displayedBooks.first?.id {
                    isResultsFocused = false
                    isSearchFocused = true
                } else {
                    model.moveSelection(offset: -1)
                }
            case .down: model.moveSelection(offset: 1)
            default: break
            }
        }
        .onKeyPress(.space) {
            model.openSelectedDetails()
            return .handled
        }
        .onKeyPress(.return) {
            guard let book = model.selectedBook else { return .ignored }
            model.enqueueDownload(book, importEPUB: onImportEPUB)
            return .handled
        }
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    if let totalCount = model.totalCount {
                        Text("\(totalCount) result(s)")
                            .foregroundStyle(.secondary)
                    }
                    if model.isGlobalSorting {
                        ProgressView(value: model.globalSortProgress)
                            .frame(width: 72)
                        Text("Loaded \(model.globalSortLoadedCount) / \(model.globalSortLimit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Cancel", role: .cancel) { model.cancelGlobalSort() }
                            .buttonStyle(.glass)
                    }
                    if !model.downloadQueue.isEmpty {
                        Divider().frame(height: 18)
                        ProgressView(value: model.queueProgress)
                            .frame(width: 64)
                        Text(queueSummaryText)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if model.queueSummary.pending == 0 {
                            Button("Clear Finished") { model.clearFinishedDownloads() }
                                .buttonStyle(.glass)
                        }
                    }
                    Spacer()
                    Button {
                        model.goToPage(model.currentPage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.canGoBack)

                    Text("Page \(model.currentPage)")
                        .monospacedDigit()

                    Button {
                        model.goToPage(model.currentPage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.canGoForward)
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private var queueSummaryText: String {
        let summary = model.queueSummary
        return String(
            localized: "Queue: \(summary.pending) pending · \(summary.imported) imported · \(summary.duplicate) duplicate · \(summary.failed) failed"
        )
    }
}

enum ZLibraryViewError: LocalizedError {
    case alreadyImported
    case invalidPublicationYears

    var errorDescription: String? {
        switch self {
        case .alreadyImported:
            String(localized: "This book is already in your bookshelf.")
        case .invalidPublicationYears:
            String(localized: "Enter valid publication years.")
        }
    }
}

private struct ZLibrarySearchField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let focus: FocusState<Bool>.Binding
    let recentQueries: [String]
    let onSelectRecent: (String) -> Void
    let onRemoveRecent: (String) -> Void
    let onClearRecents: () -> Void
    let onFocusResults: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            if !recentQueries.isEmpty {
                Menu {
                    ForEach(recentQueries, id: \.self) { recentQuery in
                        Menu(recentQuery) {
                            Button("Search Again", systemImage: "magnifyingglass") {
                                onSelectRecent(recentQuery)
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                onRemoveRecent(recentQuery)
                            }
                        }
                    }
                    Divider()
                    Button("Clear Recent Searches", role: .destructive) {
                        onClearRecents()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Recent Searches")
                .accessibilityLabel("Recent Searches")
            }

            TextField("Title, author, ISBN, DOI, publisher, or keyword", text: $text)
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(onSubmit)
                .onMoveCommand { direction in
                    if direction == .down { onFocusResults() }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay {
            Capsule()
                .stroke(focus.wrappedValue ? Color.accentColor : .clear, lineWidth: 2)
                .padding(focus.wrappedValue ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: focus.wrappedValue)
    }
}

private struct ZLibraryModeControl: View {
    let selection: ZLibraryContentMode
    let onSelect: (ZLibraryContentMode) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(ZLibraryContentMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                            .labelStyle(.iconOnly)
                            .font(.callout.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                            .glassEffect(
                                selection == mode
                                    ? .regular.tint(Color.accentColor.opacity(0.22)).interactive()
                                    : .regular.interactive(),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .help(mode.title)
                    .accessibilityLabel(mode.title)
                    .accessibilityValue(selection == mode ? "Selected" : "")
                }
            }
        }
    }
}

private struct ZLibraryLoginField<Field: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        LabeledContent {
            field()
                .nativeSettingsTextField()
                .controlSize(.large)
                .frame(maxWidth: 390)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
}

private struct ZLibraryBookRow: View {
    let book: ZLibraryBook
    let isAlreadyImported: Bool
    let queueItem: ZLibraryQueueItem?
    let onOpenDetails: () -> Void
    let onCancel: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZLibraryCoverView(book: book, width: 48, height: 68, onOpenDetails: onOpenDetails)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title.isEmpty ? String(localized: "Untitled") : book.title)
                    .font(.headline)
                    .lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    if !book.year.isEmpty { Text(book.year) }
                    if !book.language.isEmpty { Text(book.localizedLanguage) }
                    Text(book.fileExtension.uppercased())
                    if !book.fileSize.isEmpty { Text(book.formattedFileSize) }
                    if !book.rating.isEmpty { Label(book.rating, systemImage: "star.fill") }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpenDetails) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Show Details")
            .accessibilityLabel("Show Details")
            if isAlreadyImported {
                Label("In Bookshelf", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            } else if let queueItem {
                queueControl(queueItem)
            } else {
                importButton
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func queueControl(_ item: ZLibraryQueueItem) -> some View {
        switch item.state {
        case .queued:
            HStack(spacing: 8) {
                Label("Queued", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.glass)
            }
        case .downloading:
                HStack(spacing: 8) {
                    if let progress = item.progress {
                        ProgressView(value: progress)
                            .frame(width: 72)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(role: .cancel, action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(Capsule())
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
        case .imported:
            Label("Imported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .duplicate:
            Label("Duplicate", systemImage: "doc.on.doc")
                .foregroundStyle(.secondary)
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise", action: onDownload)
                .buttonStyle(.glass)
        case .cancelled:
            importButton
        }
    }

    private var importButton: some View {
        Button(action: onDownload) {
            Label("Import", systemImage: "arrow.down.to.line")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Capsule())
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.2)).interactive(),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!book.isEPUB)
    }
}

private struct ZLibraryCoverView: View {
    let book: ZLibraryBook
    let width: CGFloat
    let height: CGFloat
    let onOpenDetails: () -> Void
    @State private var reloadID = UUID()
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case image(NSImage)
        case noCover
        case networkFailure
    }

    var body: some View {
        Group {
            switch phase {
            case .image(let image):
                Image(nsImage: image).resizable().scaledToFill()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenDetails)
            case .networkFailure:
                Button {
                    reloadID = UUID()
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        coverPlaceholder
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(4)
                    }
                }
                .buttonStyle(.plain)
                .help("Cover failed to load. Retry")
                .accessibilityLabel("Retry Cover")
            case .loading:
                ProgressView().controlSize(.small)
            case .noCover:
                coverPlaceholder
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenDetails)
            }
        }
        .frame(width: width, height: height)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: "\(book.id):\(book.coverURL?.absoluteString ?? "no-cover"):\(reloadID.uuidString)") {
            await loadCover()
        }
    }

    private var coverPlaceholder: some View {
        Image(systemName: "book.closed.fill")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCover() async {
        guard let url = book.coverURL else {
            phase = .noCover
            return
        }
        phase = .loading
        do {
            let data = try await ZLibraryCoverLoader.shared.data(for: url)
            try Task.checkCancellation()
            guard let image = NSImage(data: data) else {
                phase = .networkFailure
                return
            }
            phase = .image(image)
        } catch is CancellationError {
        } catch ZLibraryCoverError.noCover {
            phase = .noCover
        } catch {
            phase = .networkFailure
        }
    }
}

private struct ZLibraryBookDetailPanel: View {
    let book: ZLibraryBook
    let details: ZLibraryBookDetails?
    let isLoading: Bool
    let isAlreadyImported: Bool
    let queueItem: ZLibraryQueueItem?
    let quota: ZLibraryDownloadQuota?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button(action: onPrevious) {
                            Label("Previous Book", systemImage: "chevron.up")
                        }
                        Button(action: onNext) {
                            Label("Next Book", systemImage: "chevron.down")
                        }
                        Spacer()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)

                    ZLibraryCoverView(book: book, width: 150, height: 214, onOpenDetails: {})
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title.isEmpty ? String(localized: "Untitled") : book.title)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        if !book.author.isEmpty {
                            Text(book.author)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        metadata("Year", value: book.year)
                        metadata("Language", value: book.localizedLanguage)
                        metadata("Format", value: book.fileExtension.uppercased())
                        metadata("File Size", value: book.formattedFileSize)
                        metadata("ISBN", value: detailISBN)
                        metadata("Publisher", value: details?.publisher ?? "")
                        metadata("Pages", value: details?.pages ?? "")
                        metadata("Series", value: details?.series ?? "")
                    }

                    Divider()
                    ZLibraryBookDetailsView(details: details, isLoading: isLoading)

                    if let quota {
                        Divider()
                        if let used = quota.usedToday, let limit = quota.dailyLimit {
                            Label("Downloads today: \(used) / \(limit)", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let remaining = quota.remaining {
                            Label("Downloads remaining: \(remaining)", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(18)
            }

            Divider()
            detailAction
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.bar)
        }
        .navigationTitle("Book Details")
    }

    private var detailISBN: String {
        guard let details, !details.isbn.isEmpty else { return book.isbn }
        return details.isbn
    }

    @ViewBuilder
    private var detailAction: some View {
        if isAlreadyImported || queueItem?.state == .imported || queueItem?.state == .duplicate {
            Label("In Bookshelf", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else if queueItem?.state == .downloading || queueItem?.state == .queued {
            HStack {
                if queueItem?.state == .downloading {
                    ProgressView(value: queueItem?.progress)
                } else {
                    Label("Queued", systemImage: "clock")
                }
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.glass)
            }
        } else {
            Button("Import", systemImage: "arrow.down.to.line", action: onImport)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!book.isEPUB)
        }
    }

    @ViewBuilder
    private func metadata(_ title: LocalizedStringKey, value: String) -> some View {
        if !value.isEmpty {
            GridRow {
                Text(title).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

private struct ZLibraryBookDetailsView: View {
    let details: ZLibraryBookDetails?
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading details...")
                        .foregroundStyle(.secondary)
                }
            } else if let details, details.hasAdditionalMetadata {
                VStack(alignment: .leading, spacing: 7) {
                    if !details.description.isEmpty {
                        Text(details.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            detailLabel("Publisher", value: details.publisher)
                            detailLabel("ISBN", value: details.isbn)
                        }
                        GridRow {
                            detailLabel("Pages", value: details.pages)
                            detailLabel("Series", value: details.series)
                        }
                    }
                    if !details.categories.isEmpty {
                        detailLabel("Categories", value: details.categories.joined(separator: " · "))
                    }
                }
            } else {
                Text("No additional details available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func detailLabel(_ title: LocalizedStringKey, value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(title, value: value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension ZLibraryBook {
    var localizedLanguage: String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "japanese": String(localized: "Japanese")
        case "english": String(localized: "English")
        case "chinese", "simplified chinese": String(localized: "Simplified Chinese")
        case "traditional chinese": String(localized: "Traditional Chinese")
        case "korean": String(localized: "Korean")
        case "french": String(localized: "French")
        case "german": String(localized: "German")
        case "spanish": String(localized: "Spanish")
        case "russian": String(localized: "Russian")
        default: language
        }
    }

    var formattedFileSize: String {
        guard let bytes = fileSizeBytes else { return fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
