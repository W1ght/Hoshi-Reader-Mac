import AppKit
import SwiftUI

nonisolated enum MangaSourceBrowseMode:
    String,
    CaseIterable,
    Identifiable
{
    case popular
    case latest

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .popular: "Popular"
        case .latest: "Latest"
        }
    }
}

enum SuwayomiConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@Observable
@MainActor
final class MangaSourceViewModel {
    var serverURLDraft = SuwayomiConstants.defaultServerURL
    var authMode = SuwayomiAuthMode.none
    var usernameDraft = ""
    var secretDraft = ""
    var connectionState = SuwayomiConnectionState.disconnected

    var sources: [SuwayomiSource] = []
    var selectedSourceID: String?
    var browseMode = MangaSourceBrowseMode.popular
    var query = ""
    var browseItems: [SuwayomiManga] = []
    var browsePage = 1
    var hasNextPage = false
    var library: [SuwayomiManga] = []
    var detail: SuwayomiManga?
    var detailChapters: [SuwayomiChapter] = []
    var isLoading = false
    var isLoadingDetails = false
    var errorMessage: String?

    @ObservationIgnored private let store =
        SuwayomiConnectionStore.shared
    @ObservationIgnored private var client: SuwayomiClient?
    @ObservationIgnored private var profileID =
        HoshiProfile.defaultJapanese.id
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activeSearchQuery: String?

    var selectedSource: SuwayomiSource? {
        sources.first { $0.id == selectedSourceID }
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var showsInsecureCredentialWarning: Bool {
        guard authMode != .none,
              let url = try? SuwayomiClient.normalizedServerURL(
                  serverURLDraft
              ),
              url.scheme == "http" else {
            return false
        }
        return !["localhost", "127.0.0.1", "::1", "[::1]"].contains(
            url.host?.lowercased() ?? ""
        )
    }

    var connectionStatusText: String {
        switch connectionState {
        case .disconnected:
            String(localized: "Not connected")
        case .connecting:
            String(localized: "Connecting…")
        case .connected:
            String(localized: "Connected to Suwayomi Server")
        case .failed(let message):
            message
        }
    }

    func load(profileID: String) {
        self.profileID = profileID
        task?.cancel()
        task = Task {
            let configuration = await store.configuration(
                profileID: profileID
            )
            serverURLDraft = configuration.serverURL
            authMode = configuration.authMode
            usernameDraft = configuration.username
            secretDraft = ""
            await connect(using: configuration)
        }
    }

    func saveAndConnect() {
        task?.cancel()
        task = Task {
            do {
                let configuration = currentConfiguration
                try await store.save(
                    profileID: profileID,
                    configuration: configuration,
                    secret: secretDraft.isEmpty ? nil : secretDraft
                )
                secretDraft = ""
                await connect(using: configuration)
            } catch {
                show(error)
            }
        }
    }

    func forgetConnection() {
        task?.cancel()
        task = Task {
            do {
                try await store.clear(profileID: profileID)
            } catch {
                show(error)
            }
            client = nil
            sources = []
            library = []
            browseItems = []
            selectedSourceID = nil
            connectionState = .disconnected
            serverURLDraft = SuwayomiConstants.defaultServerURL
            authMode = .none
            usernameDraft = ""
            secretDraft = ""
        }
    }

    func reconnect() {
        task?.cancel()
        task = Task {
            await connect(using: currentConfiguration)
        }
    }

    func selectSource(_ sourceID: String?) {
        guard selectedSourceID != sourceID else { return }
        selectedSourceID = sourceID
        query = ""
        activeSearchQuery = nil
        if selectedSource?.supportsLatest != true {
            browseMode = .popular
        }
        task?.cancel()
        task = Task { await browse(reset: true) }
    }

    func changeBrowseMode(_ mode: MangaSourceBrowseMode) {
        guard mode != .latest || selectedSource?.supportsLatest == true else {
            browseMode = .popular
            return
        }
        browseMode = mode
        query = ""
        activeSearchQuery = nil
        task?.cancel()
        task = Task { await browse(reset: true) }
    }

    func search() {
        let submittedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        query = submittedQuery
        activeSearchQuery = submittedQuery.isEmpty
            ? nil
            : submittedQuery
        task?.cancel()
        task = Task { await browse(reset: true) }
    }

    func refreshLibrary() {
        task?.cancel()
        task = Task { await loadLibrary() }
    }

    func loadNextPageIfNeeded(current manga: SuwayomiManga) {
        guard hasNextPage,
              !isLoading,
              browseItems.suffix(6).contains(manga) else {
            return
        }
        task = Task {
            await browse(reset: false)
        }
    }

    func showDetails(_ manga: SuwayomiManga) {
        detail = manga
        detailChapters = []
        task?.cancel()
        task = Task { await loadDetails(manga) }
    }

    func dismissDetails() {
        detail = nil
        detailChapters = []
    }

    func setLibrary(
        _ manga: SuwayomiManga,
        isInLibrary: Bool
    ) {
        task?.cancel()
        task = Task {
            guard let client else { return }
            do {
                try await client.setLibrary(
                    mangaID: manga.id,
                    isInLibrary: isInLibrary
                )
                if detail?.id == manga.id {
                    detail?.inLibrary = isInLibrary
                }
                await loadLibrary()
            } catch {
                show(error)
            }
        }
    }

    func prepareReading(
        manga: SuwayomiManga,
        initialChapterID: Int? = nil
    ) throws -> MangaRemoteReadingRequest {
        guard let client else {
            throw SuwayomiConnectorError.serverUnavailable
        }
        let hasCachedDetails =
            detail?.id == manga.id && !detailChapters.isEmpty
        return MangaRemoteReadingRequest(
            manga: manga,
            initialChapterID: initialChapterID,
            profileID: profileID,
            client: client,
            cachedManga: hasCachedDetails ? detail : nil,
            cachedChapters: hasCachedDetails ? detailChapters : []
        )
    }

    func coverData(for manga: SuwayomiManga) async -> Data? {
        guard let client else { return nil }
        return try? await client.thumbnailData(mangaID: manga.id)
    }

    private var currentConfiguration: SuwayomiServerConfiguration {
        SuwayomiServerConfiguration(
            serverURL: serverURLDraft,
            authMode: authMode,
            username: usernameDraft.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    private func connect(
        using configuration: SuwayomiServerConfiguration
    ) async {
        connectionState = .connecting
        errorMessage = nil
        do {
            let credentials = await store.credentials(
                profileID: profileID
            )
            let client = try SuwayomiClient(
                configuration: configuration,
                credentials: credentials
            )
            let sources = try await client.connect()
            try Task.checkCancellation()
            self.client = client
            self.sources = sources
            if selectedSourceID == nil
                || !sources.contains(where: {
                    $0.id == selectedSourceID
                }) {
                selectedSourceID = sources.first?.id
            }
            query = ""
            activeSearchQuery = nil
            if selectedSource?.supportsLatest != true {
                browseMode = .popular
            }
            connectionState = .connected
            await loadLibrary()
            await browse(reset: true)
        } catch is CancellationError {
            return
        } catch {
            client = nil
            sources = []
            library = []
            browseItems = []
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func loadLibrary() async {
        guard let client else { return }
        isLoading = true
        do {
            library = try await client.library()
            isLoading = false
        } catch is CancellationError {
            isLoading = false
        } catch {
            isLoading = false
            show(error)
        }
    }

    private func browse(reset: Bool) async {
        guard let client, let sourceID = selectedSourceID else {
            browseItems = []
            return
        }
        if reset {
            browsePage = 1
            browseItems = []
            hasNextPage = false
        }
        isLoading = true
        do {
            let page: SuwayomiPagedManga
            if let activeSearchQuery {
                page = try await client.search(
                    sourceID: sourceID,
                    query: activeSearchQuery,
                    page: browsePage
                )
            } else {
                switch browseMode {
                case .popular:
                    page = try await client.popular(
                        sourceID: sourceID,
                        page: browsePage
                    )
                case .latest:
                    page = try await client.latest(
                        sourceID: sourceID,
                        page: browsePage
                    )
                }
            }
            try Task.checkCancellation()
            let existingIDs = Set(browseItems.map(\.id))
            let additions = page.mangaList.filter {
                !existingIDs.contains($0.id)
            }
            browseItems.append(contentsOf: additions)
            hasNextPage = page.hasNextPage && !additions.isEmpty
            if hasNextPage { browsePage += 1 }
            isLoading = false
        } catch is CancellationError {
            isLoading = false
        } catch {
            isLoading = false
            show(error)
        }
    }

    private func loadDetails(_ manga: SuwayomiManga) async {
        guard let client else { return }
        isLoadingDetails = true
        do {
            async let loadedManga = client.manga(
                id: manga.id,
                onlineFetch: true
            )
            async let chapters = client.chapters(
                mangaID: manga.id,
                onlineFetch: true
            )
            let (resolvedManga, resolvedChapters) = try await (
                loadedManga,
                chapters
            )
            try Task.checkCancellation()
            guard detail?.id == manga.id else { return }
            detail = resolvedManga
            detailChapters = resolvedChapters
            isLoadingDetails = false
        } catch is CancellationError {
            isLoadingDetails = false
        } catch {
            isLoadingDetails = false
            show(error)
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        if !isConnected {
            connectionState = .failed(error.localizedDescription)
        }
    }
}

struct MangaSourcesView: View {
    @Bindable var viewModel: MangaSourceViewModel

    var body: some View {
        NativeSettingsForm {
            NativeSettingsSectionCard(
                "Suwayomi Server",
                footer:
                    "Niratan connects to an existing Suwayomi Server. It does not install or bundle Suwayomi, Java, or Mihon extensions."
            ) {
                NativeSettingsRow {
                    Text("Server Address")
                } accessory: {
                    TextField(
                        "Server Address",
                        text: $viewModel.serverURLDraft,
                        prompt: Text(
                            SuwayomiConstants.defaultServerURL
                        )
                    )
                    .nativeSettingsTextField()
                    .frame(maxWidth: 420)
                }

                NativeSettingsSeparator()

                NativeSettingsRow {
                    Text("Authentication")
                } accessory: {
                    NativeGlassMenuPicker(
                        selection: $viewModel.authMode,
                        values: SuwayomiAuthMode.allCases,
                        minWidth: 150
                    ) { mode in
                        Text(authenticationTitle(for: mode))
                    }
                }

                if viewModel.authMode == .basic
                    || viewModel.authMode == .uiLogin {
                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Username")
                    } accessory: {
                        TextField(
                            "Username",
                            text: $viewModel.usernameDraft
                        )
                        .nativeSettingsTextField()
                        .frame(maxWidth: 420)
                    }
                }

                if viewModel.authMode != .none {
                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text(
                            viewModel.authMode == .bearer
                                ? String(localized: "Token")
                                : String(localized: "Password")
                        )
                    } accessory: {
                        SecureField(
                            viewModel.authMode == .bearer
                                ? String(localized: "Token")
                                : String(localized: "Password"),
                            text: $viewModel.secretDraft
                        )
                        .nativeSettingsTextField()
                        .frame(maxWidth: 420)
                    }
                }

                if viewModel.showsInsecureCredentialWarning {
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        Label(
                            "Credentials sent over HTTP are not encrypted.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                NativeSettingsSeparator()

                NativeSettingsButtonRow {
                    connectionLabel
                    Spacer()
                    Button("Forget", role: .destructive) {
                        viewModel.forgetConnection()
                    }
                    .buttonStyle(.glass)
                    Button("Save & Connect") {
                        viewModel.saveAndConnect()
                    }
                    .buttonStyle(.glassProminent)
                }
            }

            NativeSettingsSectionCard("Available Sources") {
                if !viewModel.isConnected {
                    NativeSettingsButtonRow {
                        Text(
                            "Connect to Suwayomi Server to view its installed sources."
                        )
                        .foregroundStyle(.secondary)
                    }
                } else if viewModel.sources.isEmpty {
                    NativeSettingsButtonRow {
                        Text(
                            "No installed Suwayomi sources were found."
                        )
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(
                        Array(viewModel.sources.enumerated()),
                        id: \.element.id
                    ) { index, source in
                        if index > 0 {
                            NativeSettingsSeparator()
                        }
                        NativeSettingsButtonRow {
                            Button {
                                viewModel.selectSource(source.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.displayName)
                                    Text(source.lang)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if source.isNsfw {
                                    Text("18+")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                }
                                if source.id == viewModel.selectedSourceID {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }
        }
        .suwayomiErrorBanner(viewModel)
    }

    @ViewBuilder
    private var connectionLabel: some View {
        switch viewModel.connectionState {
        case .connecting:
            Label(
                viewModel.connectionStatusText,
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .connected:
            Label(
                viewModel.connectionStatusText,
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .failed:
            Label(
                viewModel.connectionStatusText,
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        case .disconnected:
            Label(
                viewModel.connectionStatusText,
                systemImage: "bolt.horizontal.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func authenticationTitle(
        for mode: SuwayomiAuthMode
    ) -> LocalizedStringKey {
        switch mode {
        case .none:
            "None"
        case .basic:
            "Basic Auth"
        case .uiLogin:
            "UI Login"
        case .bearer:
            "Bearer Token"
        }
    }
}

struct MangaSourceBrowseView: View {
    @Bindable var viewModel: MangaSourceViewModel
    let onOpen: (MangaRemoteReadingRequest) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: BookshelfLayout.v050CoverWidth,
                maximum: BookshelfLayout.v050CoverWidth
            ),
            spacing: BookshelfLayout.columnSpacing
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .sheet(item: $viewModel.detail) { manga in
            SuwayomiMangaDetailView(
                manga: manga,
                viewModel: viewModel,
                onOpen: onOpen
            )
        }
        .suwayomiErrorBanner(viewModel)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                HStack(spacing: 10) {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    NativeGlassMenuPicker(
                        selection: sourceSelection,
                        values: sourceValues,
                        minWidth: 170
                    ) { sourceID in
                        if let source = viewModel.sources.first(
                            where: { $0.id == sourceID }
                        ) {
                            Text(source.displayName)
                        } else {
                            Text("Select Source")
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text("Browse Mode")
                        .foregroundStyle(.secondary)
                    NativeGlassSegmentedPicker(
                        selection: browseModeSelection,
                        values: MangaSourceBrowseMode.allCases,
                        minSegmentWidth: 62,
                        isEnabled: { mode in
                            mode != .latest
                                || viewModel.selectedSource?.supportsLatest
                                    == true
                        }
                    ) { mode in
                        Text(mode.title)
                    }
                }

                Spacer()
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    TextField(
                        "Search Manga",
                        text: $viewModel.query
                    )
                    .nativeSettingsTextField()
                    .onSubmit { viewModel.search() }

                    Button("Search") { viewModel.search() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.isConnected {
            ContentUnavailableView {
                Label(
                    "Suwayomi Server Not Connected",
                    systemImage: "network.slash"
                )
            } description: {
                Text("Configure the external server in Manga Sources.")
            } actions: {
                Button("Reconnect") { viewModel.reconnect() }
                    .buttonStyle(.glass)
            }
        } else if viewModel.selectedSourceID == nil {
            ContentUnavailableView(
                "No Source Selected",
                systemImage: "books.vertical",
                description: Text(
                    "Install sources in Suwayomi, then select one here."
                )
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: BookshelfLayout.rowSpacing
                ) {
                    ForEach(viewModel.browseItems) { manga in
                        SuwayomiMangaCard(
                            manga: manga,
                            viewModel: viewModel
                        ) {
                            viewModel.showDetails(manga)
                        }
                        .onAppear {
                            viewModel.loadNextPageIfNeeded(
                                current: manga
                            )
                        }
                    }
                }
                .padding(22)
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var sourceSelection: Binding<String?> {
        Binding(
            get: { viewModel.selectedSourceID },
            set: { viewModel.selectSource($0) }
        )
    }

    private var browseModeSelection: Binding<MangaSourceBrowseMode> {
        Binding(
            get: { viewModel.browseMode },
            set: { viewModel.changeBrowseMode($0) }
        )
    }

    private var sourceValues: [String?] {
        [nil] + viewModel.sources.map { Optional($0.id) }
    }
}

struct RemoteMangaLibraryView: View {
    @Bindable var viewModel: MangaSourceViewModel
    let onOpen: (MangaRemoteReadingRequest) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: BookshelfLayout.v050CoverWidth,
                maximum: BookshelfLayout.v050CoverWidth
            ),
            spacing: BookshelfLayout.columnSpacing
        ),
    ]

    var body: some View {
        Group {
            if !viewModel.isConnected {
                ContentUnavailableView {
                    Label(
                        "Suwayomi Server Not Connected",
                        systemImage: "network.slash"
                    )
                } description: {
                    Text(
                        "The online library is stored by Suwayomi Server."
                    )
                } actions: {
                    Button("Reconnect") { viewModel.reconnect() }
                }
            } else if viewModel.library.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Suwayomi Library Is Empty",
                    systemImage: "books.vertical",
                    description: Text(
                        "Add manga from Browse or the Suwayomi WebUI."
                    )
                )
            } else {
                ScrollView {
                    HStack {
                        Text("Suwayomi Library")
                            .font(.title2.bold())
                        Spacer()
                        Button {
                            viewModel.refreshLibrary()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: BookshelfLayout.rowSpacing
                    ) {
                        ForEach(viewModel.library) { manga in
                            SuwayomiMangaCard(
                                manga: manga,
                                viewModel: viewModel
                            ) {
                                open(manga)
                            }
                            .contextMenu {
                                Button("View Details") {
                                    viewModel.showDetails(manga)
                                }
                                Button(
                                    "Remove from Suwayomi Library",
                                    role: .destructive
                                ) {
                                    viewModel.setLibrary(
                                        manga,
                                        isInLibrary: false
                                    )
                                }
                            }
                        }
                    }
                    .padding(22)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .sheet(item: $viewModel.detail) { manga in
            SuwayomiMangaDetailView(
                manga: manga,
                viewModel: viewModel,
                onOpen: onOpen
            )
        }
        .suwayomiErrorBanner(viewModel)
    }

    private func open(_ manga: SuwayomiManga) {
        do {
            onOpen(try viewModel.prepareReading(manga: manga))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func suwayomiErrorBanner(
        _ viewModel: MangaSourceViewModel
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if let errorMessage = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suwayomi Error")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                .padding(14)
                .frame(maxWidth: 380, alignment: .leading)
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: 14)
                )
                .padding(16)
            }
        }
    }
}

private struct SuwayomiMangaCard: View {
    let manga: SuwayomiManga
    @Bindable var viewModel: MangaSourceViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShelfBookCard(
                title: manga.title,
                progress: nil
            ) {
                SuwayomiCoverView(
                    manga: manga,
                    viewModel: viewModel
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SuwayomiCoverView: View {
    let manga: SuwayomiManga
    @Bindable var viewModel: MangaSourceViewModel
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(0.709, contentMode: .fit)
        .clipped()
        .task(id: manga.id) {
            guard let data = await viewModel.coverData(for: manga),
                  let loaded = NSImage(data: data) else {
                return
            }
            image = loaded
        }
    }
}

private struct SuwayomiMangaDetailView: View {
    let manga: SuwayomiManga
    @Bindable var viewModel: MangaSourceViewModel
    let onOpen: (MangaRemoteReadingRequest) -> Void

    var displayedManga: SuwayomiManga {
        viewModel.detail?.id == manga.id
            ? viewModel.detail ?? manga
            : manga
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(displayedManga.title)
                    .font(.title2.bold())
                Spacer()
                Button("Close") { viewModel.dismissDetails() }
                    .buttonStyle(.glass)
            }
            .padding()
            Divider()

            if viewModel.isLoadingDetails {
                ProgressView("Loading Manga Details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            SuwayomiCoverView(
                                manga: displayedManga,
                                viewModel: viewModel
                            )
                            .frame(width: 220, height: 320)
                            if let author = displayedManga.author,
                               !author.isEmpty {
                                LabeledContent("Author", value: author)
                            }
                            if let description =
                                displayedManga.mangaDescription,
                               !description.isEmpty {
                                Text(description)
                                    .textSelection(.enabled)
                            }
                            HStack {
                                Button("Read") { open() }
                                    .buttonStyle(.glassProminent)
                                Button(
                                    displayedManga.inLibrary
                                        ? "Remove from Library"
                                        : "Add to Library"
                                ) {
                                    viewModel.setLibrary(
                                        displayedManga,
                                        isInLibrary:
                                            !displayedManga.inLibrary
                                    )
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding()
                    }
                    .frame(minWidth: 300)

                    List(viewModel.detailChapters) { chapter in
                        Button {
                            open(chapterID: chapter.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.name)
                                HStack {
                                    if chapter.read {
                                        Label(
                                            "Read",
                                            systemImage: "checkmark.circle"
                                        )
                                    }
                                    if let scanlator = chapter.scanlator,
                                       !scanlator.isEmpty {
                                        Text(scanlator)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minWidth: 360)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private func open(chapterID: Int? = nil) {
        do {
            onOpen(
                try viewModel.prepareReading(
                    manga: displayedManga,
                    initialChapterID: chapterID
                )
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
