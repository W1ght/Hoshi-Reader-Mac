//
//  ZLibraryViewModel.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum ZLibraryLanguage: String, CaseIterable, Identifiable {
    case any = ""
    case japanese
    case english
    case chinese
    case traditionalChinese = "traditional chinese"
    case korean
    case french
    case german
    case spanish
    case russian

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .any: "Any Language"
        case .japanese: "Japanese"
        case .english: "English"
        case .chinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .russian: "Russian"
        }
    }
}

enum ZLibraryContentMode: String, CaseIterable, Identifiable {
    case search
    case recent
    case history

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .search: "Search"
        case .recent: "Recently Added"
        case .history: "Download History"
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .recent: "sparkles"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum ZLibrarySortOrder: String, CaseIterable, Identifiable {
    case relevance
    case year
    case fileSize

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .relevance: "Relevance"
        case .year: "Year"
        case .fileSize: "File Size"
        }
    }
}

private struct ZLibraryContentCache {
    var books: [ZLibraryBook] = []
    var totalCount: Int?
    var currentPage = 1
    var selectedBookID: String?
    var scrollBookID: String?
    var detailBookID: String?
    var sortOrder: ZLibrarySortOrder = .relevance
    var isGlobalResult = false
}

enum ZLibraryQueueState: Equatable {
    case queued
    case downloading
    case imported
    case duplicate
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .imported, .duplicate, .failed, .cancelled: true
        case .queued, .downloading: false
        }
    }
}

struct ZLibraryQueueItem: Identifiable, Equatable {
    let book: ZLibraryBook
    var state: ZLibraryQueueState
    var progress: Double?
    var id: String { book.id }
}

@Observable
@MainActor
final class ZLibraryViewModel {
    private static let serverKey = "zLibraryServerURL"
    private static let emailKey = "zLibraryEmail"
    private static let queryKey = "zLibrarySearchQuery"
    private static let yearFromKey = "zLibrarySearchYearFrom"
    private static let yearToKey = "zLibrarySearchYearTo"
    private static let languageKey = "zLibrarySearchLanguage"
    private static let exactKey = "zLibrarySearchExact"
    private static let sortKey = "zLibrarySearchSort"
    private static let sortKeyPrefix = "zLibrarySort."
    private static let recentQueriesKey = "zLibraryRecentQueries"
    private static let defaultServer = "https://article.sk"
    private static let blockedLegacyServer = "https://z-library.sk"

    var serverURL: String
    var email: String
    var password = ""
    var query = ""
    var yearFrom = ""
    var yearTo = ""
    var language: ZLibraryLanguage = .japanese
    var exact = false
    var contentMode: ZLibraryContentMode = .search
    var sortOrder: ZLibrarySortOrder = .relevance
    var recentQueries: [String] = []
    var books: [ZLibraryBook] = []
    var totalCount: Int?
    var currentPage = 1
    var isWorking = false
    var downloadingBookID: String?
    var downloadProgress: Double?
    var downloadQueue: [ZLibraryQueueItem] = []
    var downloadQuota: ZLibraryDownloadQuota?
    var isLoadingDownloadQuota = false
    var expandedBookID: String?
    var selectedBookID: String?
    var scrollBookID: String?
    var loadingDetailsBookID: String?
    var bookDetails: [String: ZLibraryBookDetails] = [:]
    var errorMessage = ""
    var showError = false
    var showServerConfirmation = false
    var pendingServerHost = ""
    var session: ZLibrarySession?
    var isGlobalSorting = false
    var globalSortLoadedCount = 0
    var globalSortLimit = 200
    var isGlobalResult = false
    @ObservationIgnored private var activeDownloadTask: Task<Void, Never>?
    @ObservationIgnored private var importEPUBHandler: ((URL, ZLibraryBook, ZLibraryBookDetails?) throws -> BookImportResult)?
    @ObservationIgnored private var activeSearchTask: Task<Void, Never>?
    @ObservationIgnored private var activeDetailsTask: Task<Void, Never>?
    @ObservationIgnored private var activeHistoryCoverTask: Task<Void, Never>?
    @ObservationIgnored private var activeGlobalSortTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var confirmedServerOrigin: String?
    @ObservationIgnored private var savedSearchPage: ZLibrarySearchPage?
    @ObservationIgnored private var quotaRefreshPending = false
    @ObservationIgnored private var contentCaches: [ZLibraryContentMode: ZLibraryContentCache] = [:]
    @ObservationIgnored private var relevanceCaches: [ZLibraryContentMode: ZLibraryContentCache] = [:]
    @ObservationIgnored private var refreshedHistoryCoverBookIDs = Set<String>()

    var isSignedIn: Bool { session != nil }
    var canGoBack: Bool {
        !isGlobalResult && contentMode != .recent && currentPage > 1 && !isWorking
    }
    var canGoForward: Bool {
        guard !isGlobalResult, contentMode != .recent else { return false }
        guard !isWorking, !books.isEmpty else { return false }
        guard let totalCount else { return books.count >= 20 }
        return currentPage * 20 < totalCount
    }

    var displayedBooks: [ZLibraryBook] {
        switch sortOrder {
        case .relevance:
            books
        case .year:
            stableSort { Int($0.year) }
        case .fileSize:
            stableSort { $0.fileSizeBytes }
        }
    }

    var selectedBook: ZLibraryBook? {
        guard let selectedBookID else { return nil }
        return books.first { $0.id == selectedBookID }
    }

    func queueItem(for bookID: String) -> ZLibraryQueueItem? {
        downloadQueue.first { $0.id == bookID }
    }

    var globalSortProgress: Double? {
        let target = min(totalCount ?? globalSortLimit, globalSortLimit)
        guard target > 0 else { return nil }
        return min(Double(globalSortLoadedCount) / Double(target), 1)
    }

    var queueProgress: Double {
        let activeItems = downloadQueue.filter { $0.state != .cancelled }
        guard !activeItems.isEmpty else { return 0 }
        let completed = activeItems.reduce(0.0) { partial, item in
            switch item.state {
            case .queued: partial
            case .downloading: partial + (item.progress ?? 0)
            case .imported, .duplicate, .failed: partial + 1
            case .cancelled: partial
            }
        }
        return completed / Double(activeItems.count)
    }

    var queueSummary: (imported: Int, duplicate: Int, failed: Int, pending: Int) {
        var result = (0, 0, 0, 0)
        for item in downloadQueue {
            switch item.state {
            case .imported: result.0 += 1
            case .duplicate: result.1 += 1
            case .failed: result.2 += 1
            case .queued, .downloading: result.3 += 1
            case .cancelled: break
            }
        }
        return result
    }

    var activeFilterCount: Int {
        var count = 0
        if !yearFrom.isEmpty || !yearTo.isEmpty { count += 1 }
        if language != .any { count += 1 }
        if exact { count += 1 }
        return count
    }

    init() {
        let defaults = UserDefaults.standard
        let storedSession = ZLibrarySessionStorage.load()
        session = storedSession
        let storedServer = defaults.string(forKey: Self.serverKey)
        serverURL = storedSession?.baseOrigin
            ?? (storedServer == Self.blockedLegacyServer ? Self.defaultServer : storedServer)
            ?? Self.defaultServer
        email = defaults.string(forKey: Self.emailKey) ?? ""
        query = defaults.string(forKey: Self.queryKey) ?? ""
        yearFrom = defaults.string(forKey: Self.yearFromKey) ?? ""
        yearTo = defaults.string(forKey: Self.yearToKey) ?? ""
        language = ZLibraryLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "japanese") ?? .japanese
        exact = defaults.object(forKey: Self.exactKey) as? Bool ?? false
        sortOrder = Self.storedSortOrder(for: .search, defaults: defaults)
        recentQueries = defaults.stringArray(forKey: Self.recentQueriesKey) ?? []
    }

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try makeClient(credentials: nil)
            let newSession = try await client.login(email: email, password: password)
            guard ZLibrarySessionStorage.save(newSession) else {
                throw ZLibraryClientError.invalidSession
            }
            session = newSession
            password = ""
            serverURL = newSession.baseOrigin
            UserDefaults.standard.set(newSession.baseOrigin, forKey: Self.serverKey)
            UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.emailKey)
        } catch {
            present(error)
        }
    }

    func requestSignIn() {
        do {
            guard let inputURL = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ZLibraryClientError.invalidBaseURL
            }
            let normalized = try ZLibraryClient.normalizedBaseURL(inputURL)
            if normalized.absoluteString != Self.defaultServer,
               confirmedServerOrigin != normalized.absoluteString {
                pendingServerHost = normalized.host ?? normalized.absoluteString
                showServerConfirmation = true
                return
            }
            Task { await signIn() }
        } catch {
            present(error)
        }
    }

    func confirmServerAndSignIn() {
        guard let inputURL = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let normalized = try? ZLibraryClient.normalizedBaseURL(inputURL) else {
            present(ZLibraryClientError.invalidBaseURL)
            return
        }
        confirmedServerOrigin = normalized.absoluteString
        Task { await signIn() }
    }

    func signOut() {
        cancelSearch()
        cancelDetails()
        cancelGlobalSort()
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        ZLibrarySessionStorage.clear()
        session = nil
        password = ""
        books = []
        bookDetails = [:]
        savedSearchPage = nil
        totalCount = nil
        downloadQuota = nil
        currentPage = 1
        contentMode = .search
        contentCaches = [:]
        relevanceCaches = [:]
        refreshedHistoryCoverBookIDs = []
        selectedBookID = nil
        scrollBookID = nil
        isGlobalResult = false
        downloadQueue = []
        downloadingBookID = nil
        downloadProgress = nil
    }

    func selectContentMode(_ mode: ZLibraryContentMode) {
        guard mode != contentMode else { return }
        saveCurrentCache()
        cancelSearch()
        cancelGlobalSort()
        expandedBookID = nil
        cancelDetails()
        contentMode = mode
        if let cache = contentCaches[mode], !cache.books.isEmpty {
            restore(cache)
            if mode == .history {
                startHistoryCoverRefresh(for: cache.books, generation: searchGeneration)
            }
            if let detailID = cache.detailBookID,
               let book = cache.books.first(where: { $0.id == detailID }),
               bookDetails[detailID] == nil {
                showDetails(for: book)
            }
        } else {
            sortOrder = Self.storedSortOrder(for: mode)
            switch mode {
            case .search:
                if let savedSearchPage {
                    apply(savedSearchPage)
                } else {
                    books = []
                    totalCount = nil
                    currentPage = 1
                }
            case .recent, .history:
                startCollection(mode: mode)
            }
        }
    }

    func refreshCurrentContent() {
        switch contentMode {
        case .search:
            startSearch(page: currentPage)
        case .recent:
            startCollection(mode: .recent)
        case .history:
            startCollection(mode: .history, page: currentPage)
        }
    }

    func toggleDetails(for book: ZLibraryBook) {
        if expandedBookID == book.id {
            expandedBookID = nil
            cancelDetails()
            saveCurrentCache()
            return
        }
        showDetails(for: book)
    }

    private func showDetails(for book: ZLibraryBook) {
        expandedBookID = book.id
        selectedBookID = book.id
        scrollBookID = book.id
        saveCurrentCache()
        cancelDetails()
        guard bookDetails[book.id] == nil else { return }
        loadingDetailsBookID = book.id
        activeDetailsTask = Task { [weak self] in
            await self?.loadDetails(for: book)
        }
    }

    func cancelDetails() {
        activeDetailsTask?.cancel()
        activeDetailsTask = nil
        loadingDetailsBookID = nil
    }

    func closeDetails() {
        expandedBookID = nil
        cancelDetails()
        saveCurrentCache()
    }

    func selectAdjacentBook(offset: Int) {
        moveSelection(offset: offset)
        guard let selectedBook else { return }
        showDetails(for: selectedBook)
    }

    func moveSelection(offset: Int) {
        guard !displayedBooks.isEmpty else { return }
        let index = selectedBookID.flatMap { id in displayedBooks.firstIndex { $0.id == id } }
            ?? (offset > 0 ? -1 : displayedBooks.count)
        let target = min(max(index + offset, 0), displayedBooks.count - 1)
        let book = displayedBooks[target]
        selectedBookID = book.id
        scrollBookID = book.id
        saveCurrentCache()
    }

    func openSelectedDetails() {
        guard let selectedBook else { return }
        if expandedBookID != selectedBook.id {
            toggleDetails(for: selectedBook)
        }
    }

    func updateSelection(_ id: String?) {
        selectedBookID = id
        if let id { scrollBookID = id }
        if expandedBookID != nil,
           let id,
           expandedBookID != id,
           let book = books.first(where: { $0.id == id }) {
            showDetails(for: book)
            return
        }
        saveCurrentCache()
    }

    func updateScrollPosition(_ id: String?) {
        scrollBookID = id
        saveCurrentCache()
    }

    private func loadDetails(for book: ZLibraryBook) async {
        defer {
            if loadingDetailsBookID == book.id {
                loadingDetailsBookID = nil
                activeDetailsTask = nil
            }
        }
        do {
            let client = try makeClient(credentials: session)
            let details = try await client.bookDetails(for: book)
            try Task.checkCancellation()
            guard expandedBookID == book.id else { return }
            bookDetails[book.id] = details
        } catch ZLibraryClientError.invalidSession {
            signOut()
            present(ZLibraryClientError.invalidSession)
        } catch is CancellationError {
        } catch {
            guard expandedBookID == book.id else { return }
            present(error)
        }
    }

    func refreshDownloadQuota(showError: Bool = false, force: Bool = false) async {
        guard session != nil else { return }
        if isLoadingDownloadQuota {
            quotaRefreshPending = quotaRefreshPending || force
            return
        }
        isLoadingDownloadQuota = true
        defer {
            isLoadingDownloadQuota = false
            if quotaRefreshPending {
                quotaRefreshPending = false
                Task { [weak self] in
                    await self?.refreshDownloadQuota(showError: showError)
                }
            }
        }
        do {
            let client = try makeClient(credentials: session)
            downloadQuota = try await client.downloadQuota()
        } catch ZLibraryClientError.invalidSession {
            signOut()
            present(ZLibraryClientError.invalidSession)
        } catch is CancellationError {
        } catch {
            if showError { present(error) }
        }
    }

    func startSearch(page: Int = 1) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        guard validatedYears else {
            present(ZLibraryViewError.invalidPublicationYears)
            return
        }
        expandedBookID = nil
        cancelDetails()
        cancelGlobalSort()
        activeSearchTask?.cancel()
        contentMode = .search
        rememberSearch(trimmedQuery)
        searchGeneration &+= 1
        let generation = searchGeneration
        let request = ZLibrarySearchRequest(
            query: trimmedQuery,
            page: page,
            limit: 20,
            yearFrom: Int(yearFrom),
            yearTo: Int(yearTo),
            languages: language == .any ? [] : [language.rawValue],
            extensions: ["EPUB"],
            exact: exact
        )
        isWorking = true
        activeSearchTask = Task { [weak self] in
            await self?.performSearch(request, generation: generation)
        }
    }

    func cancelSearch() {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        activeHistoryCoverTask?.cancel()
        activeHistoryCoverTask = nil
        searchGeneration &+= 1
        isWorking = false
    }

    private func performSearch(_ request: ZLibrarySearchRequest, generation: Int) async {
        defer {
            if generation == searchGeneration {
                activeSearchTask = nil
                isWorking = false
            }
        }
        do {
            let client = try makeClient(credentials: session)
            let result = try await client.search(request)
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }
            savedSearchPage = result
            apply(result)
            relevanceCaches[.search] = currentCache()
            if sortOrder != .relevance, (result.totalCount ?? result.books.count) > result.books.count {
                startGlobalSort()
            }
        } catch ZLibraryClientError.invalidSession {
            if generation == searchGeneration {
                signOut()
                present(ZLibraryClientError.invalidSession)
            }
        } catch is CancellationError {
        } catch {
            if generation == searchGeneration {
                present(error)
            }
        }
    }

    func goToPage(_ page: Int) {
        switch contentMode {
        case .search:
            startSearch(page: page)
        case .recent:
            break
        case .history:
            startCollection(mode: .history, page: page)
        }
    }

    func setSortOrder(_ order: ZLibrarySortOrder) {
        guard order != sortOrder else { return }
        cancelGlobalSort()
        sortOrder = order
        persistSortOrder()
        if order == .relevance {
            if let baseline = relevanceCaches[contentMode] {
                restore(baseline)
                sortOrder = .relevance
            }
            saveCurrentCache()
            return
        }
        guard contentMode != .recent,
              (totalCount ?? books.count) > books.count else {
            saveCurrentCache()
            return
        }
        startGlobalSort()
    }

    func cancelGlobalSort() {
        activeGlobalSortTask?.cancel()
        activeGlobalSortTask = nil
        isGlobalSorting = false
    }

    func selectRecentQuery(_ recentQuery: String) {
        query = recentQuery
        startSearch()
    }

    func clearRecentQueries() {
        recentQueries = []
        UserDefaults.standard.removeObject(forKey: Self.recentQueriesKey)
    }

    func removeRecentQuery(_ query: String) {
        recentQueries.removeAll { $0 == query }
        UserDefaults.standard.set(recentQueries, forKey: Self.recentQueriesKey)
    }

    func setYearFrom(_ value: String) {
        yearFrom = sanitizedYear(value)
    }

    func setYearTo(_ value: String) {
        yearTo = sanitizedYear(value)
    }

    func resetFilters() {
        yearFrom = ""
        yearTo = ""
        language = .japanese
        exact = false
        persistSearchPreferences()
    }

    func persistSearchPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(query, forKey: Self.queryKey)
        defaults.set(yearFrom, forKey: Self.yearFromKey)
        defaults.set(yearTo, forKey: Self.yearToKey)
        defaults.set(language.rawValue, forKey: Self.languageKey)
        defaults.set(exact, forKey: Self.exactKey)
        persistSortOrder(defaults: defaults)
    }

    private func startCollection(mode: ZLibraryContentMode, page: Int = 1) {
        activeSearchTask?.cancel()
        activeHistoryCoverTask?.cancel()
        activeHistoryCoverTask = nil
        searchGeneration &+= 1
        let generation = searchGeneration
        contentMode = mode
        sortOrder = Self.storedSortOrder(for: mode)
        expandedBookID = nil
        cancelDetails()
        books = []
        totalCount = nil
        currentPage = max(page, 1)
        isWorking = true
        activeSearchTask = Task { [weak self] in
            await self?.performCollection(mode: mode, page: page, generation: generation)
        }
    }

    private func performCollection(
        mode: ZLibraryContentMode,
        page: Int,
        generation: Int
    ) async {
        defer {
            if generation == searchGeneration {
                activeSearchTask = nil
                isWorking = false
            }
        }
        do {
            let client = try makeClient(credentials: session)
            let result: ZLibrarySearchPage
            switch mode {
            case .search:
                return
            case .recent:
                result = try await client.recentlyAdded(limit: 20)
            case .history:
                result = try await client.downloadHistory(page: page, limit: 20)
            }
            try Task.checkCancellation()
            guard generation == searchGeneration, contentMode == mode else { return }
            apply(result)
            relevanceCaches[mode] = currentCache()
            if mode == .history {
                startHistoryCoverRefresh(for: result.books, generation: generation)
            }
            if sortOrder != .relevance,
               mode != .recent,
               (result.totalCount ?? result.books.count) > result.books.count {
                startGlobalSort()
            }
        } catch ZLibraryClientError.invalidSession {
            if generation == searchGeneration {
                signOut()
                present(ZLibraryClientError.invalidSession)
            }
        } catch is CancellationError {
        } catch {
            if generation == searchGeneration { present(error) }
        }
    }

    private func startHistoryCoverRefresh(
        for sourceBooks: [ZLibraryBook],
        generation: Int
    ) {
        let pendingBooks = sourceBooks.filter { !refreshedHistoryCoverBookIDs.contains($0.id) }
        guard !pendingBooks.isEmpty else { return }
        activeHistoryCoverTask?.cancel()
        activeHistoryCoverTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try makeClient(credentials: session)
                await refreshHistoryCovers(
                    pendingBooks,
                    client: client,
                    generation: generation
                )
            } catch {
                // Keep the history results usable when background cover refresh is unavailable.
            }
        }
    }

    private func refreshHistoryCovers(
        _ sourceBooks: [ZLibraryBook],
        client: ZLibraryClient,
        generation: Int
    ) async {
        await withTaskGroup(of: ZLibraryBook?.self) { group in
            var nextIndex = 0
            let initialRequestCount = min(4, sourceBooks.count)
            for _ in 0..<initialRequestCount {
                let book = sourceBooks[nextIndex]
                nextIndex += 1
                group.addTask {
                    try? await client.refreshedBook(for: book)
                }
            }

            while let refreshedBook = await group.next() {
                guard !Task.isCancelled,
                      generation == searchGeneration,
                      contentMode == .history else {
                    group.cancelAll()
                    return
                }

                if let refreshedBook,
                   let coverURL = refreshedBook.coverURL,
                   let index = books.firstIndex(where: { $0.id == refreshedBook.id }) {
                    books[index] = books[index].replacingCoverURL(coverURL)
                    refreshedHistoryCoverBookIDs.insert(refreshedBook.id)
                }

                if nextIndex < sourceBooks.count {
                    let book = sourceBooks[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try? await client.refreshedBook(for: book)
                    }
                }
            }
        }

        guard !Task.isCancelled,
              generation == searchGeneration,
              contentMode == .history else { return }
        saveCurrentCache()
        relevanceCaches[.history] = currentCache()
        activeHistoryCoverTask = nil
    }

    private func apply(_ page: ZLibrarySearchPage) {
        books = page.books
        totalCount = page.totalCount
        currentPage = page.page
        selectedBookID = page.books.first?.id
        scrollBookID = page.books.first?.id
        isGlobalResult = false
        saveCurrentCache()
    }

    private func startGlobalSort() {
        guard !isGlobalSorting else { return }
        isGlobalSorting = true
        globalSortLoadedCount = 0
        activeGlobalSortTask = Task { [weak self] in
            await self?.performGlobalSort()
        }
    }

    private func performGlobalSort() async {
        defer {
            isGlobalSorting = false
            activeGlobalSortTask = nil
        }
        do {
            let client = try makeClient(credentials: session)
            var combined: [ZLibraryBook] = []
            var seen = Set<String>()
            var page = 1
            var knownTotal = totalCount
            let pageSize = 50
            while combined.count < globalSortLimit {
                try Task.checkCancellation()
                let result: ZLibrarySearchPage
                switch contentMode {
                case .search:
                    result = try await client.search(searchRequest(page: page, limit: pageSize))
                case .recent:
                    return
                case .history:
                    result = try await client.downloadHistory(page: page, limit: pageSize)
                }
                knownTotal = result.totalCount ?? knownTotal
                for book in result.books where seen.insert("\(book.id):\(book.hash)").inserted {
                    combined.append(book)
                    if combined.count == globalSortLimit { break }
                }
                books = combined
                totalCount = knownTotal
                currentPage = 1
                globalSortLoadedCount = combined.count
                isGlobalResult = true
                saveCurrentCache()
                let target = min(knownTotal ?? globalSortLimit, globalSortLimit)
                if result.books.isEmpty || combined.count >= target { break }
                page += 1
            }
        } catch is CancellationError {
        } catch ZLibraryClientError.invalidSession {
            signOut()
            present(ZLibraryClientError.invalidSession)
        } catch {
            present(error)
        }
    }

    private func searchRequest(page: Int, limit: Int) -> ZLibrarySearchRequest {
        ZLibrarySearchRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            page: page,
            limit: limit,
            yearFrom: Int(yearFrom),
            yearTo: Int(yearTo),
            languages: language == .any ? [] : [language.rawValue],
            extensions: ["EPUB"],
            exact: exact
        )
    }

    private func currentCache() -> ZLibraryContentCache {
        ZLibraryContentCache(
            books: books,
            totalCount: totalCount,
            currentPage: currentPage,
            selectedBookID: selectedBookID,
            scrollBookID: scrollBookID,
            detailBookID: expandedBookID,
            sortOrder: sortOrder,
            isGlobalResult: isGlobalResult
        )
    }

    private func saveCurrentCache() {
        contentCaches[contentMode] = currentCache()
    }

    private func restore(_ cache: ZLibraryContentCache) {
        books = cache.books
        totalCount = cache.totalCount
        currentPage = cache.currentPage
        selectedBookID = cache.selectedBookID
        scrollBookID = cache.scrollBookID
        expandedBookID = cache.detailBookID
        sortOrder = cache.sortOrder
        isGlobalResult = cache.isGlobalResult
    }

    private static func storedSortOrder(
        for mode: ZLibraryContentMode,
        defaults: UserDefaults = .standard
    ) -> ZLibrarySortOrder {
        let key = sortKeyPrefix + mode.rawValue
        let fallback = mode == .search ? defaults.string(forKey: sortKey) : nil
        return ZLibrarySortOrder(rawValue: defaults.string(forKey: key) ?? fallback ?? "relevance")
            ?? .relevance
    }

    private func persistSortOrder(defaults: UserDefaults = .standard) {
        defaults.set(sortOrder.rawValue, forKey: Self.sortKeyPrefix + contentMode.rawValue)
        if contentMode == .search {
            defaults.set(sortOrder.rawValue, forKey: Self.sortKey)
        }
    }

    private func rememberSearch(_ trimmedQuery: String) {
        query = trimmedQuery
        persistSearchPreferences()
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
        recentQueries.insert(trimmedQuery, at: 0)
        recentQueries = Array(recentQueries.prefix(8))
        UserDefaults.standard.set(recentQueries, forKey: Self.recentQueriesKey)
    }

    private func sanitizedYear(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(4))
    }

    private func stableSort(
        value: (ZLibraryBook) -> Int64?
    ) -> [ZLibraryBook] {
        books.enumerated().sorted { lhs, rhs in
            let left = value(lhs.element)
            let right = value(rhs.element)
            switch (left, right) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private func stableSort(
        value: (ZLibraryBook) -> Int?
    ) -> [ZLibraryBook] {
        stableSort { book in value(book).map(Int64.init) }
    }

    func enqueueDownload(
        _ book: ZLibraryBook,
        importEPUB: @escaping (URL, ZLibraryBook, ZLibraryBookDetails?) throws -> BookImportResult
    ) {
        guard !downloadQueue.contains(where: { $0.id == book.id && !$0.state.isFinished }) else {
            return
        }
        importEPUBHandler = importEPUB
        if let index = downloadQueue.firstIndex(where: { $0.id == book.id }) {
            downloadQueue[index] = ZLibraryQueueItem(book: book, state: .queued, progress: nil)
        } else {
            downloadQueue.append(ZLibraryQueueItem(book: book, state: .queued, progress: nil))
        }
        startNextQueuedDownload()
    }

    private func startNextQueuedDownload() {
        guard activeDownloadTask == nil,
              let index = downloadQueue.firstIndex(where: { $0.state == .queued }),
              let importEPUBHandler else { return }
        let book = downloadQueue[index].book
        downloadingBookID = book.id
        downloadProgress = nil
        downloadQueue[index].state = .downloading
        downloadQueue[index].progress = nil
        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.download(book, importEPUB: importEPUBHandler)
            if let queueIndex = self.downloadQueue.firstIndex(where: { $0.id == book.id }) {
                self.downloadQueue[queueIndex].state = outcome
                self.downloadQueue[queueIndex].progress = outcome == .imported ? 1 : nil
            }
            self.activeDownloadTask = nil
            self.downloadingBookID = nil
            self.downloadProgress = nil
            self.startNextQueuedDownload()
        }
    }

    func cancelDownload(bookID: String? = nil) {
        let targetID = bookID ?? downloadingBookID
        guard let targetID,
              let index = downloadQueue.firstIndex(where: { $0.id == targetID }) else { return }
        switch downloadQueue[index].state {
        case .queued:
            downloadQueue[index].state = .cancelled
            startNextQueuedDownload()
        case .downloading:
            downloadQueue[index].state = .cancelled
            activeDownloadTask?.cancel()
        default:
            break
        }
    }

    func cancelAllDownloads() {
        importEPUBHandler = nil
        for index in downloadQueue.indices where !downloadQueue[index].state.isFinished {
            downloadQueue[index].state = .cancelled
            downloadQueue[index].progress = nil
        }
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadingBookID = nil
        downloadProgress = nil
    }

    func clearFinishedDownloads() {
        downloadQueue.removeAll { $0.state.isFinished }
    }

    private func download(
        _ book: ZLibraryBook,
        importEPUB: @escaping (URL, ZLibraryBook, ZLibraryBookDetails?) throws -> BookImportResult
    ) async -> ZLibraryQueueState {
        do {
            let client = try makeClient(credentials: session)
            let url = try await client.downloadEPUB(book) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.downloadProgress = progress
                    if let index = self.downloadQueue.firstIndex(where: { $0.id == book.id }),
                       self.downloadQueue[index].state == .downloading {
                        self.downloadQueue[index].progress = progress
                    }
                }
            }
            Task { [weak self] in
                await self?.refreshDownloadQuota(force: true)
            }
            defer { try? FileManager.default.removeItem(at: url) }
            try Task.checkCancellation()
            switch try importEPUB(url, book, bookDetails[book.id]) {
            case .imported:
                return .imported
            case .alreadyExists:
                return .duplicate
            }
        } catch ZLibraryClientError.invalidSession {
            signOut()
            present(ZLibraryClientError.invalidSession)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        return .failed(String(localized: "The download could not be completed."))
    }

    private var validatedYears: Bool {
        let from = yearFrom.isEmpty ? nil : Int(yearFrom)
        let to = yearTo.isEmpty ? nil : Int(yearTo)
        guard yearFrom.isEmpty || from != nil, yearTo.isEmpty || to != nil else { return false }
        if let from, let to { return from <= to }
        return true
    }

    private func makeClient(credentials: ZLibrarySession?) throws -> ZLibraryClient {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ZLibraryClientError.invalidBaseURL
        }
        return try ZLibraryClient(baseURL: url, credentials: credentials)
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
