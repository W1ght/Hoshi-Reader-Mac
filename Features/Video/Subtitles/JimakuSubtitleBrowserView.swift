import Combine
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class JimakuSubtitleBrowserModel {
    var apiKeyDraft = ""
    var query = ""
    var episodeText = ""
    var searchKind: JimakuSearchKind = .anime
    private(set) var hasAPIKey = false
    private(set) var isCheckingCredentials = true
    private(set) var isSavingCredential = false
    private(set) var isSearching = false
    private(set) var isLoadingFiles = false
    private(set) var hasSearched = false
    private(set) var entries: [JimakuEntry] = []
    private(set) var selectedEntry: JimakuEntry?
    private(set) var files: [JimakuSubtitleFile] = []
    private(set) var credentialStatusMessage: String?
    private(set) var errorMessage: String?

    private let client: JimakuAPIClient
    private let credentialStore: JimakuCredentialStore
    private var sourceIdentifier: String?
    private var operationGeneration = 0

    init(
        suggestion: JimakuMediaSuggestion? = nil,
        client: JimakuAPIClient = .shared,
        credentialStore: JimakuCredentialStore = .shared
    ) {
        self.client = client
        self.credentialStore = credentialStore
        if let suggestion {
            sourceIdentifier = suggestion.sourceIdentifier
            query = suggestion.query
            episodeText = suggestion.episode.map(String.init) ?? ""
        }
    }

    func prepare(for suggestion: JimakuMediaSuggestion) async {
        if sourceIdentifier != suggestion.sourceIdentifier {
            sourceIdentifier = suggestion.sourceIdentifier
            operationGeneration &+= 1
            query = suggestion.query
            episodeText = suggestion.episode.map(String.init) ?? ""
            hasSearched = false
            entries = []
            selectedEntry = nil
            files = []
            errorMessage = nil
            isSearching = false
            isLoadingFiles = false
        }
        await refreshCredentialState()
    }

    func refreshCredentialState() async {
        isCheckingCredentials = true
        defer { isCheckingCredentials = false }
        do {
            hasAPIKey = try await credentialStore.hasAPIKey()
            credentialStatusMessage = nil
        } catch {
            hasAPIKey = false
            credentialStatusMessage = String(
                localized: "Unable to read the Jimaku API key from Keychain."
            )
        }
    }

    func saveAPIKey() async {
        let normalized = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            errorMessage = String(localized: "Enter a Jimaku API key.")
            return
        }
        _ = await saveAPIKey(normalized)
    }

    func removeAPIKey() async {
        operationGeneration &+= 1
        isSavingCredential = true
        credentialStatusMessage = nil
        defer { isSavingCredential = false }
        do {
            try await credentialStore.removeAPIKey()
            apiKeyDraft = ""
            hasAPIKey = false
            entries = []
            selectedEntry = nil
            files = []
            hasSearched = false
            credentialStatusMessage = String(localized: "Jimaku API key removed.")
            NotificationCenter.default.post(name: .jimakuCredentialDidChange, object: nil)
        } catch {
            credentialStatusMessage = String(localized: "Unable to remove the Jimaku API key.")
        }
    }

    func search() async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedSourceIdentifier = sourceIdentifier
        guard !normalizedQuery.isEmpty else {
            errorMessage = String(localized: "Enter a title to search Jimaku.")
            return
        }
        guard let apiKey = await apiKeyForSearch(),
              sourceIdentifier == requestedSourceIdentifier else { return }

        operationGeneration &+= 1
        let generation = operationGeneration
        isSearching = true
        isLoadingFiles = false
        hasSearched = true
        errorMessage = nil
        selectedEntry = nil
        files = []
        do {
            let result = try await client.searchEntries(
                query: normalizedQuery,
                kind: searchKind,
                apiKey: apiKey
            )
            guard generation == operationGeneration else { return }
            entries = result
            isSearching = false
        } catch {
            guard generation == operationGeneration else { return }
            entries = []
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }

    func select(_ entry: JimakuEntry) async {
        let requestedSourceIdentifier = sourceIdentifier
        guard let apiKey = await storedAPIKey(),
              sourceIdentifier == requestedSourceIdentifier,
              let episode = parsedEpisode() else { return }

        operationGeneration &+= 1
        let generation = operationGeneration
        selectedEntry = entry
        files = []
        isLoadingFiles = true
        errorMessage = nil
        do {
            let result = try await client.files(
                for: entry.id,
                episode: episode,
                apiKey: apiKey
            )
            guard generation == operationGeneration,
                  selectedEntry?.id == entry.id else { return }
            files = result
            isLoadingFiles = false
        } catch {
            guard generation == operationGeneration else { return }
            files = []
            isLoadingFiles = false
            errorMessage = error.localizedDescription
        }
    }

    func showSearchResults() {
        operationGeneration &+= 1
        selectedEntry = nil
        files = []
        isLoadingFiles = false
        errorMessage = nil
    }

    private func apiKeyForSearch() async -> String? {
        let normalizedDraft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDraft.isEmpty {
            return await saveAPIKey(normalizedDraft) ? normalizedDraft : nil
        }
        return await storedAPIKey()
    }

    private func saveAPIKey(_ apiKey: String) async -> Bool {
        isSavingCredential = true
        credentialStatusMessage = nil
        defer { isSavingCredential = false }
        do {
            try await credentialStore.save(apiKey: apiKey)
            apiKeyDraft = ""
            hasAPIKey = true
            errorMessage = nil
            credentialStatusMessage = String(localized: "Jimaku API key saved.")
            NotificationCenter.default.post(name: .jimakuCredentialDidChange, object: nil)
            return true
        } catch {
            credentialStatusMessage = String(localized: "Unable to save the Jimaku API key.")
            return false
        }
    }

    private func storedAPIKey() async -> String? {
        do {
            guard let apiKey = try await credentialStore.apiKey() else {
                hasAPIKey = false
                errorMessage = String(localized: "Enter a Jimaku API key.")
                return nil
            }
            hasAPIKey = true
            return apiKey
        } catch {
            hasAPIKey = false
            errorMessage = String(localized: "Unable to read the Jimaku API key from Keychain.")
            return nil
        }
    }

    private func parsedEpisode() -> Int?? {
        let normalized = episodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .some(nil) }
        guard let episode = Int(normalized), (0...9_999).contains(episode) else {
            errorMessage = String(localized: "Enter an episode number from 0 to 9999.")
            return nil
        }
        return .some(episode)
    }
}

struct JimakuSubtitleBrowserView: View {
    private static let configurationPanelWidth: CGFloat = 430
    private static let minimumPanelWidth: CGFloat = 1_120
    private static let idealPanelWidth: CGFloat = 1_240
    private static let maximumPanelWidth: CGFloat = 1_440
    private static let minimumPanelHeight: CGFloat = 680
    private static let idealPanelHeight: CGFloat = 760
    private static let maximumPanelHeight: CGFloat = 900

    @Environment(\.dismiss) private var dismiss

    let suggestion: JimakuMediaSuggestion
    let selectedFileID: String?
    let onSelectFile: (JimakuSubtitleFile) -> Void

    @State private var model: JimakuSubtitleBrowserModel
    @State private var isShowingAPIKeyRemovalConfirmation = false

    init(
        suggestion: JimakuMediaSuggestion,
        selectedFileID: String?,
        onSelectFile: @escaping (JimakuSubtitleFile) -> Void
    ) {
        self.suggestion = suggestion
        self.selectedFileID = selectedFileID
        self.onSelectFile = onSelectFile
        _model = State(
            initialValue: JimakuSubtitleBrowserModel(suggestion: suggestion)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                configurationPanel
                    .frame(width: Self.configurationPanelWidth)

                Divider()

                resultsPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: Self.minimumPanelWidth,
            idealWidth: Self.idealPanelWidth,
            maxWidth: Self.maximumPanelWidth,
            minHeight: Self.minimumPanelHeight,
            idealHeight: Self.idealPanelHeight,
            maxHeight: Self.maximumPanelHeight
        )
        .task(id: suggestion) {
            await model.prepare(for: suggestion)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .jimakuCredentialDidChange)
        ) { _ in
            Task { await model.refreshCredentialState() }
        }
        .confirmationDialog(
            "Remove Jimaku API Key?",
            isPresented: $isShowingAPIKeyRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove API Key", role: .destructive) {
                Task { await model.removeAPIKey() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved Jimaku API key will be removed from this Mac.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Get Subtitles (Jimaku)", systemImage: "icloud.and.arrow.down")
                .font(.title3.weight(.semibold))

            Spacer()

            Button(role: .cancel) {
                dismiss()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var configurationPanel: some View {
        @Bindable var model = model

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Jimaku API Key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField(
                            LocalizedStringKey(
                                model.hasAPIKey
                                    ? "Saved API key — enter to replace"
                                    : "Enter a Jimaku API key"
                            ),
                            text: $model.apiKeyDraft
                        )
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task { await model.saveAPIKey() }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))

                        Button {
                            Task { await model.saveAPIKey() }
                        } label: {
                            Label("Save", systemImage: "key.horizontal")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(
                            model.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.isSavingCredential
                        )
                    }

                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Link(destination: URL(string: "https://jimaku.cc/account")!) {
                                Label("Create API Key", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.glass)

                            if model.hasAPIKey {
                                Button(role: .destructive) {
                                    isShowingAPIKeyRemovalConfirmation = true
                                } label: {
                                    Label("Remove Saved API Key", systemImage: "trash")
                                }
                                .buttonStyle(.glass)
                                .tint(.red)
                                .disabled(model.isSavingCredential)
                            }
                        }
                    }
                    .font(.caption.weight(.medium))

                    HStack(spacing: 6) {
                        if model.isCheckingCredentials || model.isSavingCredential {
                            ProgressView()
                                .controlSize(.small)
                        } else if model.hasAPIKey {
                            Label("Saved in Keychain", systemImage: "key.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    Text("You can also change the API key in Video Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Content Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    NativeGlassSegmentedPicker(
                        selection: $model.searchKind,
                        values: JimakuSearchKind.allCases,
                        minSegmentWidth: 108,
                        fillsWidth: true,
                        isEnabled: { _ in !model.isSearching && !model.isLoadingFiles }
                    ) { kind in
                        Label(
                            kind == .anime ? String(localized: "Anime") : String(localized: "Live Action"),
                            systemImage: kind == .anime ? "sparkles" : "film"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search title", text: $model.query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await model.search() }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Episode (Optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Episode", text: $model.episodeText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }

                Button {
                    Task { await model.search() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Search")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.isSearching || model.isSavingCredential)

                if let credentialStatusMessage = model.credentialStatusMessage {
                    statusMessage(credentialStatusMessage, systemImage: "key")
                }
                if let errorMessage = model.errorMessage {
                    statusMessage(errorMessage, systemImage: "exclamationmark.triangle")
                }
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var resultsPanel: some View {
        if model.isSearching {
            centeredStatus("Searching Jimaku", systemImage: "magnifyingglass")
        } else if let entry = model.selectedEntry {
            fileResults(for: entry)
        } else if model.entries.isEmpty {
            if model.hasSearched {
                ContentUnavailableView(
                    "No Jimaku Results",
                    systemImage: "captions.bubble",
                    description: Text("Try another title or content type.")
                )
            } else {
                ContentUnavailableView(
                    "Search Jimaku",
                    systemImage: "captions.bubble",
                    description: Text("Search results will appear here.")
                )
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.entries) { entry in
                        entryRow(entry)
                    }
                }
                .padding(22)
            }
        }
    }

    private func fileResults(for entry: JimakuEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.showSearchResults()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .help("Back to Jimaku Results")

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let secondaryName = entry.secondaryName {
                        Text(secondaryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(18)

            Divider()

            if model.isLoadingFiles {
                centeredStatus("Loading Jimaku Subtitles", systemImage: "arrow.down.circle")
            } else if model.files.isEmpty {
                ContentUnavailableView(
                    "No Supported Subtitles",
                    systemImage: "captions.bubble",
                    description: Text("No supported subtitles were found for this title and episode.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.files) { file in
                            fileRow(file)
                        }
                    }
                    .padding(22)
                }
            }
        }
    }

    private func entryRow(_ entry: JimakuEntry) -> some View {
        Button {
            Task { await model.select(entry) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.flags.movie == true ? "film" : "play.rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let secondaryName = entry.secondaryName {
                        Text(secondaryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private func fileRow(_ file: JimakuSubtitleFile) -> some View {
        let isSelected = selectedFileID == file.id
        return Button {
            onSelectFile(file)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }

    private func centeredStatus(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusMessage(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
