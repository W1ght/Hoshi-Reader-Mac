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
    @ObservationIgnored private var activeOperationID = UUID()
    @ObservationIgnored private var activeSearchQuery: String?
    @ObservationIgnored private var detailLoadID: UUID?
    @ObservationIgnored private var connectionLoadID = UUID()
    @ObservationIgnored private var connectedProfileID: String?
    @ObservationIgnored private var connectedLoadID: UUID?
    @ObservationIgnored private var detailConnectionIdentity: String?

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
        let operationID = beginOperation()
        let loadID = UUID()
        connectionLoadID = loadID
        self.profileID = profileID
        resetConnectionContent()
        serverURLDraft = SuwayomiConstants.defaultServerURL
        authMode = .none
        usernameDraft = ""
        secretDraft = ""
        task = Task {
            let configuration = await store.configuration(
                profileID: profileID
            )
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID
            ), !Task.isCancelled else {
                return
            }
            serverURLDraft = configuration.serverURL
            authMode = configuration.authMode
            usernameDraft = configuration.username
            secretDraft = ""
            await connect(
                using: configuration,
                profileID: profileID,
                loadID: loadID,
                operationID: operationID
            )
        }
    }

    func saveAndConnect() {
        let operationID = beginOperation()
        let profileID = profileID
        let configuration = currentConfiguration
        let secret = secretDraft
        let loadID = UUID()
        connectionLoadID = loadID
        resetConnectionContent()
        task = Task {
            do {
                let savedConfiguration = try await store.save(
                    profileID: profileID,
                    configuration: configuration,
                    secret: secret.isEmpty ? nil : secret
                )
                guard isCurrentOperation(operationID),
                      isCurrentConnection(
                    profileID: profileID,
                    loadID: loadID
                ), !Task.isCancelled else {
                    return
                }
                secretDraft = ""
                await connect(
                    using: savedConfiguration,
                    profileID: profileID,
                    loadID: loadID,
                    operationID: operationID
                )
            } catch {
                guard isCurrentOperation(operationID),
                      isCurrentConnection(
                    profileID: profileID,
                    loadID: loadID
                ), !Task.isCancelled else {
                    return
                }
                show(error)
            }
        }
    }

    func forgetConnection() {
        let operationID = beginOperation()
        let profileID = profileID
        let loadID = UUID()
        connectionLoadID = loadID
        resetConnectionContent()
        task = Task {
            do {
                try await store.clear(profileID: profileID)
            } catch {
                guard isCurrentOperation(operationID),
                      isCurrentConnection(
                    profileID: profileID,
                    loadID: loadID
                ), !Task.isCancelled else {
                    return
                }
                show(error)
                return
            }
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID
            ), !Task.isCancelled else {
                return
            }
            connectionState = .disconnected
            serverURLDraft = SuwayomiConstants.defaultServerURL
            authMode = .none
            usernameDraft = ""
            secretDraft = ""
        }
    }

    func reconnect() {
        let operationID = beginOperation()
        let profileID = profileID
        let configuration = currentConfiguration
        let loadID = UUID()
        connectionLoadID = loadID
        resetConnectionContent()
        task = Task {
            await connect(
                using: configuration,
                profileID: profileID,
                loadID: loadID,
                operationID: operationID
            )
        }
    }

    func selectSource(_ sourceID: String?) {
        guard isConnected else { return }
        guard selectedSourceID != sourceID else { return }
        selectedSourceID = sourceID
        query = ""
        activeSearchQuery = nil
        if selectedSource?.supportsLatest != true {
            browseMode = .popular
        }
        let operationID = beginOperation()
        guard let context = connectedContext else {
            browseItems = []
            return
        }
        task = Task {
            await browse(
                reset: true,
                client: context.client,
                profileID: context.profileID,
                loadID: context.loadID,
                operationID: operationID
            )
        }
    }

    func changeBrowseMode(_ mode: MangaSourceBrowseMode) {
        guard isConnected else { return }
        guard mode != .latest || selectedSource?.supportsLatest == true else {
            browseMode = .popular
            return
        }
        browseMode = mode
        query = ""
        activeSearchQuery = nil
        let operationID = beginOperation()
        guard let context = connectedContext else {
            browseItems = []
            return
        }
        task = Task {
            await browse(
                reset: true,
                client: context.client,
                profileID: context.profileID,
                loadID: context.loadID,
                operationID: operationID
            )
        }
    }

    func search() {
        guard isConnected else { return }
        let submittedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        query = submittedQuery
        activeSearchQuery = submittedQuery.isEmpty
            ? nil
            : submittedQuery
        let operationID = beginOperation()
        guard let context = connectedContext else {
            browseItems = []
            return
        }
        task = Task {
            await browse(
                reset: true,
                client: context.client,
                profileID: context.profileID,
                loadID: context.loadID,
                operationID: operationID
            )
        }
    }

    func refreshLibrary() {
        guard isConnected else { return }
        let operationID = beginOperation()
        guard let context = connectedContext else { return }
        task = Task {
            await loadLibrary(
                client: context.client,
                profileID: context.profileID,
                loadID: context.loadID,
                operationID: operationID
            )
        }
    }

    func loadNextPageIfNeeded(current manga: SuwayomiManga) {
        guard isConnected,
              hasNextPage,
              !isLoading,
              browseItems.suffix(6).contains(manga) else {
            return
        }
        let operationID = beginOperation()
        guard let context = connectedContext else { return }
        task = Task {
            await browse(
                reset: false,
                client: context.client,
                profileID: context.profileID,
                loadID: context.loadID,
                operationID: operationID
            )
        }
    }

    func showDetails(_ manga: SuwayomiManga) {
        guard isConnected else { return }
        let operationID = beginOperation()
        guard let context = connectedContext else {
            show(SuwayomiConnectorError.serverUnavailable)
            return
        }
        let loadID = UUID()
        detailLoadID = loadID
        detailConnectionIdentity = connectionIdentity(
            profileID: context.profileID,
            client: context.client
        )
        isLoadingDetails = true
        detailChapters = []
        detail = manga
        task = Task {
            await loadDetails(
                manga,
                client: context.client,
                profileID: context.profileID,
                connectionLoadID: context.loadID,
                detailLoadID: loadID,
                operationID: operationID
            )
        }
    }

    func dismissDetails() {
        if detailLoadID != nil {
            _ = beginOperation()
        }
        detailLoadID = nil
        isLoadingDetails = false
        detail = nil
        detailChapters = []
        detailConnectionIdentity = nil
    }

    func setLibrary(
        _ manga: SuwayomiManga,
        isInLibrary: Bool
    ) {
        guard isConnected else { return }
        let operationID = beginOperation()
        guard let context = connectedContext else {
            show(SuwayomiConnectorError.serverUnavailable)
            return
        }
        task = Task {
            do {
                try await context.client.setLibrary(
                    mangaID: manga.id,
                    isInLibrary: isInLibrary
                )
                try Task.checkCancellation()
                guard isCurrentOperation(operationID),
                      isCurrentConnection(
                    profileID: context.profileID,
                    loadID: context.loadID,
                    client: context.client
                ) else {
                    return
                }
                if detail?.id == manga.id {
                    detail?.inLibrary = isInLibrary
                }
                await loadLibrary(
                    client: context.client,
                    profileID: context.profileID,
                    loadID: context.loadID,
                    operationID: operationID
                )
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentOperation(operationID),
                      isCurrentConnection(
                    profileID: context.profileID,
                    loadID: context.loadID,
                    client: context.client
                ) else {
                    return
                }
                show(error)
            }
        }
    }

    func prepareReading(
        manga: SuwayomiManga,
        initialChapterID: Int? = nil
    ) throws -> MangaRemoteReadingRequest {
        guard isConnected,
              let context = connectedContext else {
            throw SuwayomiConnectorError.serverUnavailable
        }
        let expectedDetailIdentity = connectionIdentity(
            profileID: context.profileID,
            client: context.client
        )
        let hasCachedDetails =
            detailConnectionIdentity == expectedDetailIdentity
            && detail?.id == manga.id
            && !detailChapters.isEmpty
        let cachedManga = hasCachedDetails ? detail : nil
        let cachedChapters = hasCachedDetails ? detailChapters : []
        let client = context.client
        let profileID = context.profileID
        return MangaRemoteReadingRequest(
            provider: .suwayomi,
            sourceID: client.serverID,
            mangaID: String(manga.id),
            title: cachedManga?.title ?? manga.title,
            profileID: profileID
        ) {
            let loadedManga: SuwayomiManga
            let chapters: [SuwayomiChapter]
            if let cachedManga, !cachedChapters.isEmpty {
                loadedManga = cachedManga
                chapters = cachedChapters
            } else {
                loadedManga = try await client.manga(id: manga.id, onlineFetch: true)
                try Task.checkCancellation()
                chapters = try await client.chapters(mangaID: manga.id, onlineFetch: true)
            }
            try Task.checkCancellation()
            let pageProvider = try await SuwayomiMangaPageContentProvider(
                client: client,
                profileID: profileID,
                chapters: chapters
            )
            let session = try await MangaReadingSession.suwayomi(
                manga: loadedManga,
                chapters: chapters,
                initialChapterID: initialChapterID,
                profileID: profileID,
                client: client,
                pageProvider: pageProvider
            )
            return MangaRemoteReadingResult(session: session, pageProvider: pageProvider)
        }
    }

    func coverData(for manga: SuwayomiManga) async -> Data? {
        guard let context = connectedContext else { return nil }
        let data = try? await context.client.thumbnailData(
            mangaID: manga.id
        )
        guard isCurrentConnection(
            profileID: context.profileID,
            loadID: context.loadID,
            client: context.client
        ) else {
            return nil
        }
        return data
    }

    func coverRequestID(for manga: SuwayomiManga) -> String {
        [
            profileID,
            connectionLoadID.uuidString,
            client?.serverID ?? "disconnected",
            String(manga.id),
        ].joined(separator: "\u{1f}")
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
        using configuration: SuwayomiServerConfiguration,
        profileID: String,
        loadID: UUID,
        operationID: UUID
    ) async {
        guard isCurrentOperation(operationID),
              isCurrentConnection(
            profileID: profileID,
            loadID: loadID
        ) else {
            return
        }
        connectionState = .connecting
        errorMessage = nil
        do {
            let credentials = await store.credentials(
                profileID: profileID,
                configuration: configuration
            )
            try Task.checkCancellation()
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID
            ) else {
                return
            }
            let resolvedClient = try SuwayomiClient(
                configuration: configuration,
                credentials: credentials
            )
            let resolvedSources = try await resolvedClient.connect()
            try Task.checkCancellation()
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID
            ) else {
                return
            }
            client = resolvedClient
            connectedProfileID = profileID
            connectedLoadID = loadID
            sources = resolvedSources
            if selectedSourceID == nil
                || !resolvedSources.contains(where: {
                    $0.id == selectedSourceID
                }) {
                selectedSourceID = resolvedSources.first?.id
            }
            query = ""
            activeSearchQuery = nil
            if selectedSource?.supportsLatest != true {
                browseMode = .popular
            }
            await loadLibrary(
                client: resolvedClient,
                profileID: profileID,
                loadID: loadID,
                operationID: operationID
            )
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                      profileID: profileID,
                      loadID: loadID,
                      client: resolvedClient
                  ),
                  !Task.isCancelled else {
                return
            }
            await browse(
                reset: true,
                client: resolvedClient,
                profileID: profileID,
                loadID: loadID,
                operationID: operationID
            )
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                      profileID: profileID,
                      loadID: loadID,
                      client: resolvedClient
                  ),
                  !Task.isCancelled else {
                return
            }
            connectionState = .connected
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID
            ) else {
                return
            }
            resetConnectionContent()
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func loadLibrary(
        client: SuwayomiClient,
        profileID: String,
        loadID: UUID,
        operationID: UUID
    ) async {
        guard isCurrentOperation(operationID),
              isCurrentConnection(
            profileID: profileID,
            loadID: loadID,
            client: client
        ) else {
            return
        }
        isLoading = true
        do {
            let resolvedLibrary = try await client.library()
            try Task.checkCancellation()
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ) else {
                return
            }
            library = resolvedLibrary
            isLoading = false
        } catch is CancellationError {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ) else {
                return
            }
            isLoading = false
        } catch {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ) else {
                return
            }
            isLoading = false
            show(error)
        }
    }

    private func browse(
        reset: Bool,
        client: SuwayomiClient,
        profileID: String,
        loadID: UUID,
        operationID: UUID
    ) async {
        guard isCurrentOperation(operationID),
              isCurrentConnection(
            profileID: profileID,
            loadID: loadID,
            client: client
        ) else {
            return
        }
        guard let sourceID = selectedSourceID else {
            browseItems = []
            return
        }
        if reset {
            browsePage = 1
            browseItems = []
            hasNextPage = false
        }
        isLoading = true
        let requestedPage = browsePage
        let requestedSearchQuery = activeSearchQuery
        let requestedBrowseMode = browseMode
        do {
            let page: SuwayomiPagedManga
            if let requestedSearchQuery {
                page = try await client.search(
                    sourceID: sourceID,
                    query: requestedSearchQuery,
                    page: requestedPage
                )
            } else {
                switch requestedBrowseMode {
                case .popular:
                    page = try await client.popular(
                        sourceID: sourceID,
                        page: requestedPage
                    )
                case .latest:
                    page = try await client.latest(
                        sourceID: sourceID,
                        page: requestedPage
                    )
                }
            }
            try Task.checkCancellation()
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ),
            selectedSourceID == sourceID,
            activeSearchQuery == requestedSearchQuery,
            browseMode == requestedBrowseMode else {
                return
            }
            let existingIDs = Set(browseItems.map(\.id))
            let additions = page.mangaList.filter {
                !existingIDs.contains($0.id)
            }
            browseItems.append(contentsOf: additions)
            hasNextPage = page.hasNextPage && !additions.isEmpty
            if hasNextPage { browsePage += 1 }
            isLoading = false
        } catch is CancellationError {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ) else {
                return
            }
            isLoading = false
        } catch {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                profileID: profileID,
                loadID: loadID,
                client: client
            ) else {
                return
            }
            isLoading = false
            show(error)
        }
    }

    private func loadDetails(
        _ manga: SuwayomiManga,
        client: SuwayomiClient,
        profileID: String,
        connectionLoadID: UUID,
        detailLoadID: UUID,
        operationID: UUID
    ) async {
        guard isCurrentOperation(operationID),
              isCurrentConnection(
            profileID: profileID,
            loadID: connectionLoadID,
            client: client
        ) else {
            guard self.detailLoadID == detailLoadID else { return }
            self.detailLoadID = nil
            isLoadingDetails = false
            show(SuwayomiConnectorError.serverUnavailable)
            return
        }
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
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                      profileID: profileID,
                      loadID: connectionLoadID,
                      client: client
                  ),
                  self.detailLoadID == detailLoadID,
                  detail?.id == manga.id else {
                return
            }
            detail = resolvedManga
            detailChapters = resolvedChapters
            detailConnectionIdentity = connectionIdentity(
                profileID: profileID,
                client: client
            )
            self.detailLoadID = nil
            isLoadingDetails = false
        } catch is CancellationError {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                      profileID: profileID,
                      loadID: connectionLoadID,
                      client: client
                  ),
                  self.detailLoadID == detailLoadID else {
                return
            }
            self.detailLoadID = nil
            isLoadingDetails = false
        } catch {
            guard isCurrentOperation(operationID),
                  isCurrentConnection(
                      profileID: profileID,
                      loadID: connectionLoadID,
                      client: client
                  ),
                  self.detailLoadID == detailLoadID else {
                return
            }
            self.detailLoadID = nil
            isLoadingDetails = false
            show(error)
        }
    }

    private func beginOperation() -> UUID {
        task?.cancel()
        task = nil
        isLoading = false
        if detailLoadID != nil {
            detailLoadID = nil
            isLoadingDetails = false
        }
        let operationID = UUID()
        activeOperationID = operationID
        return operationID
    }

    private func isCurrentOperation(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }

    private var connectedContext: (
        client: SuwayomiClient,
        profileID: String,
        loadID: UUID
    )? {
        guard let client,
              connectedProfileID == profileID,
              connectedLoadID == connectionLoadID else {
            return nil
        }
        return (client, profileID, connectionLoadID)
    }

    private func isCurrentConnection(
        profileID: String,
        loadID: UUID,
        client expectedClient: SuwayomiClient? = nil
    ) -> Bool {
        guard self.profileID == profileID,
              connectionLoadID == loadID else {
            return false
        }
        guard let expectedClient else { return true }
        return client === expectedClient
            && connectedProfileID == profileID
            && connectedLoadID == loadID
    }

    private func connectionIdentity(
        profileID: String,
        client: SuwayomiClient
    ) -> String {
        SuwayomiIdentity.sha256(
            "\(profileID)\u{1f}\(client.serverID)"
        )
    }

    private func resetConnectionContent() {
        client = nil
        connectedProfileID = nil
        connectedLoadID = nil
        sources = []
        selectedSourceID = nil
        library = []
        browseItems = []
        browsePage = 1
        hasNextPage = false
        query = ""
        activeSearchQuery = nil
        detailLoadID = nil
        detailConnectionIdentity = nil
        detail = nil
        detailChapters = []
        isLoading = false
        isLoadingDetails = false
        connectionState = .disconnected
        errorMessage = nil
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
    var contentMode: ContentMode = .fill
    var containerAspectRatio: CGFloat = 0.709
    var showsBackground = true
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if showsBackground {
                Color.gray.opacity(0.3)
            } else {
                Color.clear
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(containerAspectRatio, contentMode: .fit)
        .clipped()
        .task(id: viewModel.coverRequestID(for: manga)) {
            image = nil
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
                GlassEffectContainer(spacing: 0) {
                    Button("Close") {
                        viewModel.dismissDetails()
                    }
                    .buttonStyle(.glass)
                }
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
                                viewModel: viewModel,
                                contentMode: .fit,
                                containerAspectRatio: 4.0 / 3.0,
                                showsBackground: false
                            )
                            .frame(maxWidth: .infinity)
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
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 8) {
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
        .frame(minWidth: 960, minHeight: 680)
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
