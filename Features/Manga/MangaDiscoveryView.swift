import AidokuRuntime
import AppKit
import SwiftUI

extension MangaDiscoveryProviderID {
    var localizedName: String {
        switch self {
        case .aniList: String(localized: "AniList")
        case .myAnimeList: String(localized: "MyAnimeList")
        }
    }

    var attribution: String {
        switch self {
        case .aniList: String(localized: "Discovery data from AniList.")
        case .myAnimeList: String(localized: "MyAnimeList data via Jikan (unofficial).")
        }
    }
}

@MainActor
@Observable
final class MangaDiscoveryViewModel {
    private struct SurfaceState {
        var query = ""
        var submittedQuery = ""
        var homeSections: [MangaDiscoverySection] = []
        var searchResults: [MangaDiscoveryWork] = []
        var searchPage = 1
        var hasNextPage = false
        var errorMessage: String?
        var didLoadHome = false
    }

    private static let providerPreferenceKey = "mangaDiscoveryProvider"

    var selectedProvider: MangaDiscoveryProviderID
    var query = ""
    var submittedQuery = ""
    var homeSections: [MangaDiscoverySection] = []
    var searchResults: [MangaDiscoveryWork] = []
    var searchPage = 1
    var hasNextPage = false
    var errorMessage: String?
    var isLoading = false
    var isLoadingNextPage = false
    var detail: MangaDiscoveryWork?
    var detailErrorMessage: String?
    var isDetailLoading = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let aniListProvider: AniListMangaDiscoveryProvider
    @ObservationIgnored private let jikanProvider: JikanMangaDiscoveryProvider
    @ObservationIgnored private var states: [MangaDiscoveryProviderID: SurfaceState] = [:]
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var didLoadHome = false
    @ObservationIgnored private var currentAllowsAdult: Bool?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        selectedProvider = defaults.string(forKey: Self.providerPreferenceKey)
            .flatMap(MangaDiscoveryProviderID.init(rawValue:)) ?? .aniList
        aniListProvider = AniListMangaDiscoveryProvider(session: session)
        jikanProvider = JikanMangaDiscoveryProvider(session: session)
    }

    func load(allowsAdult: Bool) {
        if currentAllowsAdult != allowsAdult {
            requestTask?.cancel()
            states.removeAll()
            query = ""
            submittedQuery = ""
            homeSections = []
            searchResults = []
            searchPage = 1
            hasNextPage = false
            errorMessage = nil
            didLoadHome = false
            currentAllowsAdult = allowsAdult
        }
        guard !didLoadHome, submittedQuery.isEmpty else { return }
        loadHome()
    }

    func selectProvider(_ provider: MangaDiscoveryProviderID, allowsAdult: Bool) {
        guard provider != selectedProvider else { return }
        saveCurrentState()
        requestTask?.cancel()
        detailTask?.cancel()
        selectedProvider = provider
        defaults.set(provider.rawValue, forKey: Self.providerPreferenceKey)
        restoreState(states[provider] ?? SurfaceState())
        detail = nil
        detailErrorMessage = nil
        currentAllowsAdult = allowsAdult
        if !didLoadHome, submittedQuery.isEmpty {
            loadHome()
        }
    }

    func submitSearch() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            clearSearch()
            return
        }
        requestTask?.cancel()
        submittedQuery = value
        searchResults = []
        searchPage = 1
        hasNextPage = false
        errorMessage = nil
        isLoading = true
        saveCurrentState()
        let providerID = selectedProvider
        let allowsAdult = currentAllowsAdult ?? false
        requestTask = Task {
            defer {
                if self.selectedProvider == providerID {
                    self.isLoading = false
                }
            }
            do {
                let page = try await self.provider(for: providerID).search(
                    query: value,
                    page: 1,
                    allowsAdult: allowsAdult
                )
                try Task.checkCancellation()
                guard self.selectedProvider == providerID,
                      self.submittedQuery == value else { return }
                self.searchResults = page.entries
                self.searchPage = 1
                self.hasNextPage = page.hasNextPage
                self.errorMessage = nil
                self.saveCurrentState()
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedProvider == providerID else { return }
                self.errorMessage = error.localizedDescription
                self.saveCurrentState()
            }
        }
    }

    func clearSearch() {
        requestTask?.cancel()
        query = ""
        submittedQuery = ""
        searchResults = []
        searchPage = 1
        hasNextPage = false
        errorMessage = nil
        saveCurrentState()
        if !didLoadHome { loadHome() }
    }

    func loadNextPageIfNeeded(current work: MangaDiscoveryWork) {
        guard submittedQuery.isEmpty == false,
              work.id == searchResults.last?.id,
              hasNextPage,
              !isLoadingNextPage else { return }
        isLoadingNextPage = true
        let providerID = selectedProvider
        let value = submittedQuery
        let nextPage = searchPage + 1
        let allowsAdult = currentAllowsAdult ?? false
        requestTask = Task {
            defer {
                if self.selectedProvider == providerID {
                    self.isLoadingNextPage = false
                }
            }
            do {
                let page = try await self.provider(for: providerID).search(
                    query: value,
                    page: nextPage,
                    allowsAdult: allowsAdult
                )
                try Task.checkCancellation()
                guard self.selectedProvider == providerID,
                      self.submittedQuery == value else { return }
                var known = Set(self.searchResults.map(\.id))
                self.searchResults.append(contentsOf: page.entries.filter {
                    known.insert($0.id).inserted
                })
                self.searchPage = nextPage
                self.hasNextPage = page.hasNextPage
                self.errorMessage = nil
                self.saveCurrentState()
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedProvider == providerID else { return }
                self.errorMessage = error.localizedDescription
                self.saveCurrentState()
            }
        }
    }

    func showDetails(_ work: MangaDiscoveryWork) {
        detailTask?.cancel()
        detail = work
        detailErrorMessage = nil
        isDetailLoading = true
        let identity = work.identity
        detailTask = Task {
            defer {
                if self.detail?.identity == identity {
                    self.isDetailLoading = false
                }
            }
            do {
                let loaded = try await self.provider(for: identity.provider)
                    .details(identity: identity)
                try Task.checkCancellation()
                guard self.detail?.identity == identity else { return }
                self.detail = loaded
            } catch is CancellationError {
                return
            } catch {
                guard self.detail?.identity == identity else { return }
                self.detailErrorMessage = error.localizedDescription
            }
        }
    }

    func retryDetails() {
        guard let detail else { return }
        showDetails(detail)
    }

    func dismissDetails() {
        detailTask?.cancel()
        detailTask = nil
        detail = nil
        detailErrorMessage = nil
        isDetailLoading = false
    }

    func cancel() {
        saveCurrentState()
        requestTask?.cancel()
        detailTask?.cancel()
    }

    private func loadHome() {
        requestTask?.cancel()
        isLoading = true
        errorMessage = nil
        let providerID = selectedProvider
        let allowsAdult = currentAllowsAdult ?? false
        requestTask = Task {
            defer {
                if self.selectedProvider == providerID {
                    self.isLoading = false
                }
            }
            do {
                let sections = try await self.provider(for: providerID)
                    .homeSections(allowsAdult: allowsAdult)
                try Task.checkCancellation()
                guard self.selectedProvider == providerID,
                      self.submittedQuery.isEmpty else { return }
                self.homeSections = sections
                self.didLoadHome = true
                self.errorMessage = sections.allSatisfy { $0.entries.isEmpty }
                    ? sections.compactMap(\.errorMessage).first
                    : nil
                self.saveCurrentState()
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedProvider == providerID else { return }
                self.errorMessage = error.localizedDescription
                self.saveCurrentState()
            }
        }
    }

    private func provider(
        for id: MangaDiscoveryProviderID
    ) -> any MangaDiscoveryProvider {
        switch id {
        case .aniList: aniListProvider
        case .myAnimeList: jikanProvider
        }
    }

    private func saveCurrentState() {
        states[selectedProvider] = SurfaceState(
            query: query,
            submittedQuery: submittedQuery,
            homeSections: homeSections,
            searchResults: searchResults,
            searchPage: searchPage,
            hasNextPage: hasNextPage,
            errorMessage: errorMessage,
            didLoadHome: didLoadHome
        )
    }

    private func restoreState(_ state: SurfaceState) {
        query = state.query
        submittedQuery = state.submittedQuery
        homeSections = state.homeSections
        searchResults = state.searchResults
        searchPage = state.searchPage
        hasNextPage = state.hasNextPage
        errorMessage = state.errorMessage
        didLoadHome = state.didLoadHome
        isLoading = false
        isLoadingNextPage = false
    }
}

struct MangaDiscoveryView: View {
    @Bindable var viewModel: MangaDiscoveryViewModel
    @Bindable var aidokuViewModel: AidokuSourceViewModel
    let activeProfileID: String
    let onOpen: (MangaRemoteReadingRequest) -> Void
    let onOpenAidokuSources: () -> Void

    private let columns = [GridItem(
        .adaptive(
            minimum: BookshelfLayout.v050CoverWidth,
            maximum: BookshelfLayout.v050CoverWidth
        ),
        spacing: BookshelfLayout.columnSpacing
    )]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search Manga", text: $viewModel.query)
                    .nativeSettingsTextField()
                    .onSubmit { viewModel.submitSearch() }
                if !viewModel.submittedQuery.isEmpty {
                    Button("Clear Search") { viewModel.clearSearch() }
                        .buttonStyle(.glass)
                }
                Button("Search") { viewModel.submitSearch() }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.regular)
            .buttonBorderShape(.capsule)
            .padding(14)

            Divider()

            Group {
                if !viewModel.submittedQuery.isEmpty {
                    searchContent
                } else {
                    homeContent
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: "\(viewModel.selectedProvider.rawValue):\(aidokuViewModel.catalog.allowsAdultContent)") {
            viewModel.load(allowsAdult: aidokuViewModel.catalog.allowsAdultContent)
        }
        .onDisappear { viewModel.cancel() }
        .sheet(item: $viewModel.detail) { work in
            MangaDiscoveryDetailView(
                work: work,
                metadataErrorMessage: viewModel.detailErrorMessage,
                isMetadataLoading: viewModel.isDetailLoading,
                activeProfileID: activeProfileID,
                onClose: { viewModel.dismissDetails() },
                onRetryMetadata: { viewModel.retryDetails() },
                onOpen: onOpen,
                onOpenAidokuSources: onOpenAidokuSources
            )
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if viewModel.homeSections.isEmpty, let message = viewModel.errorMessage,
           !viewModel.isLoading {
            ContentUnavailableView {
                Label("Discovery Unavailable", systemImage: "network.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    viewModel.load(allowsAdult: aidokuViewModel.catalog.allowsAdultContent)
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.homeSections) { section in
                        MangaDiscoverySectionView(
                            section: section,
                            onOpen: viewModel.showDetails
                        )
                    }
                    Text(viewModel.selectedProvider.attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 18)
                }
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.searchResults.isEmpty, !viewModel.isLoading {
            ContentUnavailableView {
                Label(
                    viewModel.errorMessage == nil ? "No Results" : "Search Unavailable",
                    systemImage: viewModel.errorMessage == nil ? "magnifyingglass" : "network.slash"
                )
            } description: {
                Text(viewModel.errorMessage ?? String(localized: "Try another title or provider."))
            } actions: {
                if viewModel.errorMessage != nil {
                    Button("Retry") { viewModel.submitSearch() }
                        .buttonStyle(.glassProminent)
                }
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: BookshelfLayout.rowSpacing
                ) {
                    ForEach(viewModel.searchResults) { work in
                        MangaDiscoveryCard(work: work) {
                            viewModel.showDetails(work)
                        }
                        .onAppear { viewModel.loadNextPageIfNeeded(current: work) }
                    }
                    if viewModel.isLoadingNextPage {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}

private struct MangaDiscoverySectionView: View {
    let section: MangaDiscoverySection
    let onOpen: (MangaDiscoveryWork) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(section.title))
                .font(.title2.bold())
                .padding(.horizontal, 22)
            if section.entries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(section.errorMessage ?? String(localized: "No manga are available in this section."))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .frame(minHeight: 80)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: BookshelfLayout.columnSpacing) {
                        ForEach(section.entries) { work in
                            MangaDiscoveryCard(work: work) { onOpen(work) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct MangaDiscoveryCard: View {
    let work: MangaDiscoveryWork
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShelfBookCard(title: work.title, progress: nil) {
                MangaDiscoveryCoverView(url: work.coverURL)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct MangaDiscoveryCoverView: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.09)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: didFail ? "book.closed.fill" : "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(0.709, contentMode: .fit)
        .clipped()
        .task(id: url) {
            image = nil
            didFail = false
            guard let url else { return }
            do {
                let data = try await MangaDiscoveryCoverLoader.shared.data(for: url)
                try Task.checkCancellation()
                image = NSImage(data: data)
                didFail = image == nil
            } catch is CancellationError {
                return
            } catch {
                didFail = true
            }
        }
    }
}

private actor MangaDiscoveryCoverLoader {
    static let shared = MangaDiscoveryCoverLoader()
    private static let maximumBytes = 16 * 1_024 * 1_024

    private let cache = NSCache<NSURL, NSData>()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        cache.totalCostLimit = 64 * 1_024 * 1_024
        cache.countLimit = 128
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw MangaDiscoveryError.invalidRequest
        }
        if let cached = cache.object(forKey: url as NSURL) { return cached as Data }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme?.lowercased() == "https",
              (200..<300).contains(response.statusCode),
              data.count <= Self.maximumBytes else {
            throw MangaDiscoveryError.invalidResponse
        }
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }
}

@MainActor
@Observable
private final class MangaDiscoveryAidokuViewModel {
    var work: MangaDiscoveryWork
    var catalog = AidokuGlobalCatalog()
    var selectedSourceID: String?
    var candidates: [AidokuManga] = []
    var mappedManga: AidokuManga?
    var detail: AidokuManga?
    var customSearchQuery = ""
    var isResolving = false
    var isDetailLoading = false
    var errorMessage: String?
    var pendingWebsiteVerification: AidokuWebsiteVerificationRequest?
    var verificationRequest: AidokuWebsiteVerificationSheetRequest?
    var showReplaceLibraryConfirmation = false
    var coverRevision = UUID()

    @ObservationIgnored private let store = AidokuGlobalStore.shared
    @ObservationIgnored private var task: Task<Void, Never>?

    private var matchTitles: [String] {
        Array(work.mappingTitles.prefix(4))
    }

    init(work: MangaDiscoveryWork) {
        self.work = work
    }

    var visibleSources: [AidokuInstalledSourceRecord] {
        catalog.installedSources
            .filter { catalog.allowsAdultContent || $0.contentRating == .safe }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedSource: AidokuInstalledSourceRecord? {
        visibleSources.first { $0.sourceID == selectedSourceID }
    }

    var linkedLibraryEntry: AidokuLibraryEntry? {
        catalog.library.first { $0.discoveryWorkID == work.identity.canonicalWorkID }
    }

    var selectedMappingIsInLibrary: Bool {
        guard let source = selectedSource,
              let manga = detail ?? mappedManga else { return false }
        return catalog.library.contains {
            $0.sourceID == source.sourceID && $0.manga.key == manga.key
        }
    }

    func updateWork(_ work: MangaDiscoveryWork) {
        guard self.work.identity == work.identity else { return }
        self.work = work
    }

    func load() {
        task?.cancel()
        task = Task {
            catalog = await store.snapshot()
            let workID = work.identity.canonicalWorkID
            if let mapping = catalog.discoverySourceMappings?[workID] {
                selectedSourceID = mapping.sourceID
                mappedManga = mapping.manga
                if selectedSource != nil {
                    await loadDetails(mapping.manga, sourceID: mapping.sourceID)
                } else {
                    errorMessage = String(localized: "The saved Aidoku source is not installed.")
                }
                return
            }
            await resolveInstalledSources()
        }
    }

    func selectSource(_ sourceID: String?) {
        task?.cancel()
        selectedSourceID = sourceID
        candidates = []
        mappedManga = nil
        detail = nil
        errorMessage = nil
        pendingWebsiteVerification = nil
        verificationRequest = nil
        guard let sourceID else { return }
        customSearchQuery = work.title
        resolve(sourceID: sourceID, queries: matchTitles)
    }

    func searchCustomTitle() {
        guard let sourceID = selectedSourceID else { return }
        let query = customSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        resolve(sourceID: sourceID, queries: [query])
    }

    func chooseCandidate(_ manga: AidokuManga) {
        guard let sourceID = selectedSourceID else { return }
        task?.cancel()
        candidates = []
        errorMessage = nil
        task = Task { await apply(manga: manga, sourceID: sourceID) }
    }

    func retry() {
        if let manga = mappedManga, let sourceID = selectedSourceID {
            task?.cancel()
            task = Task { await loadDetails(manga, sourceID: sourceID) }
        } else if let sourceID = selectedSourceID {
            searchCustomTitle()
            if customSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolve(sourceID: sourceID, queries: matchTitles)
            }
        }
    }

    func addOrRemoveLibraryEntry() {
        guard let source = selectedSource,
              let manga = detail ?? mappedManga else { return }
        if let linked = linkedLibraryEntry,
           linked.sourceID != source.sourceID || linked.manga.key != manga.key {
            showReplaceLibraryConfirmation = true
            return
        }
        task = Task {
            do {
                if selectedMappingIsInLibrary {
                    try await store.removeFromLibrary(
                        sourceID: source.sourceID,
                        mangaKey: manga.key
                    )
                } else {
                    try await store.addToLibrary(
                        sourceID: source.sourceID,
                        sourceName: source.name,
                        manga: manga,
                        discoveryWorkID: work.identity.canonicalWorkID
                    )
                }
                catalog = await store.snapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func replaceLibrarySource() {
        guard let source = selectedSource,
              let manga = detail ?? mappedManga else { return }
        showReplaceLibraryConfirmation = false
        task = Task {
            do {
                try await store.replaceDiscoveryLibraryEntry(
                    workID: work.identity.canonicalWorkID,
                    sourceID: source.sourceID,
                    sourceName: source.name,
                    manga: manga
                )
                catalog = await store.snapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func readingRequest(
        profileID: String,
        initialChapterKey: String? = nil
    ) -> MangaRemoteReadingRequest? {
        guard let source = selectedSource,
              let manga = detail ?? mappedManga else { return nil }
        return AidokuReadingRequestFactory.make(
            source: source,
            manga: manga,
            initialChapterKey: initialChapterKey,
            profileID: profileID,
            catalog: catalog
        )
    }

    func requestWebsiteVerification(using accessViewModel: AidokuSourceViewModel) {
        guard let runtimeRequest = pendingWebsiteVerification,
              let source = selectedSource else { return }
        task = Task {
            let cookies = await store.storedCookies(sourceID: source.sourceID)
            guard selectedSourceID == source.sourceID else { return }
            let request = AidokuWebsiteVerificationSheetRequest(
                source: source,
                runtimeRequest: runtimeRequest,
                existingCookies: cookies,
                retryTarget: .discovery(workID: work.identity.canonicalWorkID)
            )
            accessViewModel.catalog = await store.snapshot()
            accessViewModel.selectedSourceID = source.sourceID
            accessViewModel.websiteVerificationRequest = request
            accessViewModel.activeWebsiteVerificationRequest = request
            verificationRequest = request
        }
    }

    func verificationDismissed(using accessViewModel: AidokuSourceViewModel) {
        verificationRequest = nil
        accessViewModel.selectedSourceID = nil
        retry()
    }

    func cancel() {
        task?.cancel()
    }

    private func resolveInstalledSources() async {
        let sources = visibleSources
        guard !sources.isEmpty else { return }

        isResolving = true
        isDetailLoading = false
        candidates = []
        mappedManga = nil
        detail = nil
        errorMessage = nil
        pendingWebsiteVerification = nil

        let workID = work.identity.canonicalWorkID
        var fallback: (sourceID: String, candidates: [AidokuManga], score: Double)?
        var firstFailure: (
            sourceID: String,
            message: String,
            verification: AidokuWebsiteVerificationRequest?
        )?

        defer { isResolving = false }
        for source in sources {
            do {
                try Task.checkCancellation()
                guard work.identity.canonicalWorkID == workID else { return }
                selectedSourceID = source.sourceID
                let collected = try await searchCandidates(
                    sourceID: source.sourceID,
                    queries: matchTitles
                )
                let ranked = rankedManga(collected)
                if let automatic = automaticManga(collected) {
                    isResolving = false
                    await apply(manga: automatic, sourceID: source.sourceID)
                    return
                }
                if let score = ranked.first?.score,
                   score > (fallback?.score ?? -Double.infinity) {
                    fallback = (
                        sourceID: source.sourceID,
                        candidates: ranked.map { $0.manga },
                        score: score
                    )
                }
            } catch is CancellationError {
                return
            } catch AidokuRuntimeError.cancelled {
                return
            } catch AidokuRuntimeError.websiteVerificationRequired(let request) {
                if firstFailure == nil {
                    firstFailure = (
                        sourceID: source.sourceID,
                        message: String(localized: "Complete the website check before searching this source."),
                        verification: request
                    )
                }
            } catch {
                if firstFailure == nil {
                    firstFailure = (
                        sourceID: source.sourceID,
                        message: error.localizedDescription,
                        verification: nil
                    )
                }
            }
        }

        guard work.identity.canonicalWorkID == workID else { return }
        if let fallback {
            selectedSourceID = fallback.sourceID
            candidates = fallback.candidates
        } else if let firstFailure {
            selectedSourceID = firstFailure.sourceID
            errorMessage = firstFailure.message
            pendingWebsiteVerification = firstFailure.verification
        } else {
            selectedSourceID = nil
        }
    }

    private func resolve(sourceID: String, queries: [String]) {
        task?.cancel()
        isResolving = true
        isDetailLoading = false
        candidates = []
        mappedManga = nil
        detail = nil
        errorMessage = nil
        pendingWebsiteVerification = nil
        let workID = work.identity.canonicalWorkID
        task = Task {
            defer {
                if self.selectedSourceID == sourceID {
                    self.isResolving = false
                }
            }
            do {
                let collected = try await searchCandidates(sourceID: sourceID, queries: queries)
                try Task.checkCancellation()
                guard selectedSourceID == sourceID,
                      self.work.identity.canonicalWorkID == workID else { return }
                candidates = rankedManga(collected).map { $0.manga }
                if let manga = automaticManga(collected) {
                    await apply(manga: manga, sourceID: sourceID)
                } else if candidates.isEmpty {
                    errorMessage = String(localized: "No matching manga was found in this Aidoku source.")
                }
            } catch is CancellationError {
                return
            } catch AidokuRuntimeError.cancelled {
                return
            } catch AidokuRuntimeError.websiteVerificationRequired(let request) {
                guard selectedSourceID == sourceID else { return }
                pendingWebsiteVerification = request
                errorMessage = String(localized: "Complete the website check before searching this source.")
            } catch {
                guard selectedSourceID == sourceID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func searchCandidates(
        sourceID: String,
        queries: [String]
    ) async throws -> [AidokuManga] {
        let runtime = try await store.runtime(sourceID: sourceID)
        var collected: [AidokuManga] = []
        var seen = Set<String>()
        for query in queries {
            try Task.checkCancellation()
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let page = try await runtime.search(query: value, page: 1)
            for manga in page.entries where seen.insert(manga.key).inserted {
                guard catalog.allowsAdultContent || manga.contentRating != .adult else {
                    continue
                }
                collected.append(manga)
                if collected.count == 40 { break }
            }
            if automaticManga(collected).flatMap({ manga in
                rankedManga([manga]).first?.score
            }) == 1 || collected.count == 40 {
                break
            }
        }
        return collected
    }

    private func automaticManga(_ manga: [AidokuManga]) -> AidokuManga? {
        let byKey = Dictionary(uniqueKeysWithValues: manga.map { ($0.key, $0) })
        let key = MangaDiscoveryTitleMatcher.automaticMatch(
            titles: matchTitles,
            candidates: manga.map {
                MangaDiscoveryMatchCandidate(id: $0.key, title: $0.title)
            }
        )
        return key.flatMap { byKey[$0] }
    }

    private func rankedManga(
        _ manga: [AidokuManga]
    ) -> [(manga: AidokuManga, score: Double)] {
        let byKey = Dictionary(uniqueKeysWithValues: manga.map { ($0.key, $0) })
        return MangaDiscoveryTitleMatcher.ranked(
            titles: matchTitles,
            candidates: manga.map {
                MangaDiscoveryMatchCandidate(id: $0.key, title: $0.title)
            }
        ).compactMap { match in
            byKey[match.candidateID].map { ($0, match.score) }
        }
    }

    private func apply(manga: AidokuManga, sourceID: String) async {
        guard selectedSourceID == sourceID else { return }
        mappedManga = manga
        candidates = []
        do {
            try await store.setDiscoveryMapping(
                workID: work.identity.canonicalWorkID,
                sourceID: sourceID,
                manga: manga
            )
            catalog = await store.snapshot()
            await loadDetails(manga, sourceID: sourceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetails(_ manga: AidokuManga, sourceID: String) async {
        isDetailLoading = true
        errorMessage = nil
        pendingWebsiteVerification = nil
        defer {
            if selectedSourceID == sourceID { isDetailLoading = false }
        }
        do {
            let runtime = try await store.runtime(sourceID: sourceID)
            let summary = try await runtime.mangaDetails(manga, chapters: false)
            try Task.checkCancellation()
            guard selectedSourceID == sourceID,
                  mappedManga?.key == manga.key else { return }
            detail = summary
            let loaded = try await runtime.mangaDetails(summary, chapters: true)
            try Task.checkCancellation()
            guard selectedSourceID == sourceID,
                  mappedManga?.key == manga.key else { return }
            detail = loaded
            mappedManga = loaded
            try await store.setDiscoveryMapping(
                workID: work.identity.canonicalWorkID,
                sourceID: sourceID,
                manga: loaded
            )
            catalog = await store.snapshot()
        } catch is CancellationError {
            return
        } catch AidokuRuntimeError.cancelled {
            return
        } catch AidokuRuntimeError.websiteVerificationRequired(let request) {
            guard selectedSourceID == sourceID else { return }
            pendingWebsiteVerification = request
            errorMessage = String(localized: "Complete the website check before loading chapters.")
        } catch {
            guard selectedSourceID == sourceID else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct MangaDiscoveryDetailView: View {
    let work: MangaDiscoveryWork
    let metadataErrorMessage: String?
    let isMetadataLoading: Bool
    let activeProfileID: String
    let onClose: () -> Void
    let onRetryMetadata: () -> Void
    let onOpen: (MangaRemoteReadingRequest) -> Void
    let onOpenAidokuSources: () -> Void

    @State private var sourceViewModel: MangaDiscoveryAidokuViewModel
    @State private var accessViewModel = AidokuSourceViewModel()

    init(
        work: MangaDiscoveryWork,
        metadataErrorMessage: String?,
        isMetadataLoading: Bool,
        activeProfileID: String,
        onClose: @escaping () -> Void,
        onRetryMetadata: @escaping () -> Void,
        onOpen: @escaping (MangaRemoteReadingRequest) -> Void,
        onOpenAidokuSources: @escaping () -> Void
    ) {
        self.work = work
        self.metadataErrorMessage = metadataErrorMessage
        self.isMetadataLoading = isMetadataLoading
        self.activeProfileID = activeProfileID
        self.onClose = onClose
        self.onRetryMetadata = onRetryMetadata
        self.onOpen = onOpen
        self.onOpenAidokuSources = onOpenAidokuSources
        _sourceViewModel = State(initialValue: MangaDiscoveryAidokuViewModel(work: work))
    }

    var body: some View {
        @Bindable var sourceViewModel = sourceViewModel
        @Bindable var accessViewModel = accessViewModel
        VStack(spacing: 0) {
            ZStack {
                Text(work.title).font(.headline).lineLimit(1)
                HStack {
                    Spacer()
                    NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
                        onClose()
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .frame(height: 58)
            .padding(.horizontal, 20)

            Divider()

            HSplitView {
                metadataColumn
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                    .frame(maxHeight: .infinity)
                sourceColumn(sourceViewModel: sourceViewModel, accessViewModel: accessViewModel)
                    .frame(minWidth: 520)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1_020, minHeight: 720)
        .background { NativeShelfPageBackground() }
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .task {
            accessViewModel.sourceAccessCompletionHandler = { [weak sourceViewModel] sourceID in
                guard sourceViewModel?.selectedSourceID == sourceID else { return }
                sourceViewModel?.retry()
            }
            accessViewModel.loadCatalogOnly()
            sourceViewModel.load()
        }
        .onChange(of: work) { _, value in sourceViewModel.updateWork(value) }
        .onDisappear {
            accessViewModel.sourceAccessCompletionHandler = nil
            sourceViewModel.cancel()
        }
        .aidokuSourceAccessSheets(accessViewModel)
        .sheet(item: $sourceViewModel.verificationRequest, onDismiss: {
            sourceViewModel.verificationDismissed(using: accessViewModel)
        }) { request in
            AidokuWebsiteVerificationSheet(request: request, viewModel: accessViewModel)
        }
        .alert(
            "Replace Library Source?",
            isPresented: $sourceViewModel.showReplaceLibraryConfirmation
        ) {
            Button("Replace Source") { sourceViewModel.replaceLibrarySource() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new Aidoku source uses separate chapter progress. Existing progress for the previous source will be preserved but not copied.")
        }
    }

    private var metadataColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MangaDiscoveryCoverView(url: work.coverURL)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isMetadataLoading {
                    ProgressView("Loading Details")
                }
                if let metadataErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(metadataErrorMessage).foregroundStyle(.secondary)
                        Button("Retry") { onRetryMetadata() }.buttonStyle(.glass)
                    }
                }
                if !work.authors.isEmpty {
                    LabeledContent("Author", value: work.authors.joined(separator: ", "))
                }
                if let format = work.format {
                    LabeledContent("Format", value: format.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                }
                if let status = work.status {
                    LabeledContent("Status", value: status.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                }
                if let score = work.score {
                    LabeledContent("Score", value: String(format: "%.0f%%", score))
                }
                if let chapterCount = work.chapterCount {
                    LabeledContent("Chapters", value: String(chapterCount))
                }
                if let volumeCount = work.volumeCount {
                    LabeledContent("Volumes", value: String(volumeCount))
                }
                if let summary = work.summary, !summary.isEmpty {
                    Text(summary).textSelection(.enabled)
                }
                if !work.tags.isEmpty {
                    Text(work.tags.prefix(12).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let siteURL = work.siteURL {
                    Button("Open Provider Page") { NSWorkspace.shared.open(siteURL) }
                        .buttonStyle(.glass)
                }
                Text(work.identity.provider.attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func sourceColumn(
        sourceViewModel: MangaDiscoveryAidokuViewModel,
        accessViewModel: AidokuSourceViewModel
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NativeGlassMenuPicker(
                    selection: Binding(
                        get: { sourceViewModel.selectedSourceID },
                        set: { sourceViewModel.selectSource($0) }
                    ),
                    values: [nil] + sourceViewModel.visibleSources.map { Optional($0.sourceID) },
                    minWidth: 210
                ) { sourceID in
                    Text(sourceViewModel.visibleSources.first {
                        $0.sourceID == sourceID
                    }?.name ?? String(localized: "Select Aidoku Source"))
                }
                if let source = sourceViewModel.selectedSource {
                    Button("Source Settings") { accessViewModel.showSettings(source) }
                        .buttonStyle(.glass)
                }
                Spacer()
                if sourceViewModel.detail != nil {
                    Button(sourceViewModel.selectedMappingIsInLibrary ? "Remove from Library" : "Add to Library") {
                        sourceViewModel.addOrRemoveLibraryEntry()
                    }
                    .buttonStyle(.glass)
                    Button("Read") {
                        if let request = sourceViewModel.readingRequest(profileID: activeProfileID) {
                            onOpen(request)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(sourceViewModel.detail?.chapters?.contains(where: { !$0.locked }) != true)
                }
            }
            .padding(14)

            Divider()

            sourceContent(sourceViewModel: sourceViewModel, accessViewModel: accessViewModel)
        }
    }

    @ViewBuilder
    private func sourceContent(
        sourceViewModel: MangaDiscoveryAidokuViewModel,
        accessViewModel: AidokuSourceViewModel
    ) -> some View {
        if sourceViewModel.visibleSources.isEmpty {
            ContentUnavailableView {
                Label("No Aidoku Sources", systemImage: "puzzlepiece.extension")
            } description: {
                Text("Install an Aidoku source in Manga Sources before matching this manga.")
            } actions: {
                Button("Open Manga Sources") {
                    onClose()
                    onOpenAidokuSources()
                }
                .buttonStyle(.glassProminent)
            }
        } else if sourceViewModel.selectedSource == nil {
            ContentUnavailableView(
                "Choose an Aidoku Source",
                systemImage: "books.vertical",
                description: Text("The selected source will be searched for this manga and remembered across providers.")
            )
        } else if sourceViewModel.isResolving || sourceViewModel.isDetailLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(sourceViewModel.isResolving ? "Searching Aidoku Source" : "Loading Chapters")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !sourceViewModel.candidates.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Search This Source", text: Binding(
                        get: { sourceViewModel.customSearchQuery },
                        set: { sourceViewModel.customSearchQuery = $0 }
                    ))
                    .nativeSettingsTextField()
                    .onSubmit { sourceViewModel.searchCustomTitle() }
                    Button("Search") { sourceViewModel.searchCustomTitle() }
                        .buttonStyle(.glassProminent)
                }
                .padding(14)
                Divider()
                List(sourceViewModel.candidates) { manga in
                    Button { sourceViewModel.chooseCandidate(manga) } label: {
                        HStack(spacing: 12) {
                            if let source = sourceViewModel.selectedSource {
                                AidokuCoverView(
                                    manga: manga,
                                    sourceID: source.sourceID,
                                    sourceVersion: source.version,
                                    revision: sourceViewModel.coverRevision
                                )
                                .frame(width: 44, height: 62)
                                .clipShape(.rect(cornerRadius: 6))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manga.title)
                                Text(manga.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let message = sourceViewModel.errorMessage {
            ContentUnavailableView {
                Label("Aidoku Source Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if sourceViewModel.pendingWebsiteVerification != nil {
                    Button("Verify Website") {
                        sourceViewModel.requestWebsiteVerification(using: accessViewModel)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button("Retry") { sourceViewModel.retry() }.buttonStyle(.glass)
                if let source = sourceViewModel.selectedSource {
                    Button("Source Settings") { accessViewModel.showSettings(source) }
                        .buttonStyle(.glass)
                }
            }
        } else if let detail = sourceViewModel.detail {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.title).font(.headline)
                        if let source = sourceViewModel.selectedSource {
                            Text(source.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                List(detail.chapters ?? []) { chapter in
                    Button {
                        if let request = sourceViewModel.readingRequest(
                            profileID: activeProfileID,
                            initialChapterKey: chapter.key
                        ) {
                            onOpen(request)
                        }
                    } label: {
                        HStack {
                            if let title = chapter.title, !title.isEmpty {
                                Text(title)
                            } else if let number = chapter.chapterNumber {
                                Text(
                                    "Chapter \(number, format: .number.precision(.fractionLength(0...3)))"
                                )
                            } else {
                                Text(chapter.key)
                            }
                            Spacer()
                            if chapter.locked {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(chapter.locked)
                }
            }
        }
    }
}

nonisolated enum AidokuReadingRequestFactory {
    static func make(
        source: AidokuInstalledSourceRecord,
        manga: AidokuManga,
        initialChapterKey: String?,
        profileID: String,
        catalog: AidokuGlobalCatalog
    ) -> MangaRemoteReadingRequest {
        let progress = catalog.progress
        let usesSystemProxy = catalog.sourceDirectMediaConnections?[source.sourceID] != true
        return MangaRemoteReadingRequest(
            provider: .aidoku,
            sourceID: source.sourceID,
            mangaID: manga.key,
            title: manga.title,
            profileID: profileID
        ) {
            let runtime = try await AidokuGlobalStore.shared.runtime(sourceID: source.sourceID)
            return try await MangaReadingSession.aidoku(
                source: source,
                manga: manga,
                initialChapterKey: initialChapterKey,
                profileID: profileID,
                runtime: runtime,
                progress: progress,
                usesSystemProxy: usesSystemProxy
            )
        }
    }
}
