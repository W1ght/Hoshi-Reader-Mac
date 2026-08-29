import Observation
import SwiftUI

@Observable
@MainActor
final class AJATTSubtitleBrowserModel {
    var query = ""
    var episodeText = ""
    var catalogKind: AJATTCatalogKind = .anime
    private(set) var isSearching = false
    private(set) var isLoadingFiles = false
    private(set) var hasSearched = false
    private(set) var entries: [AJATTEntry] = []
    private(set) var selectedEntry: AJATTEntry?
    private(set) var files: [AJATTSubtitleFile] = []
    private(set) var errorMessage: String?

    private let client: AJATTSubtitleCatalogClient
    private var sourceIdentifier: String?
    private var operationGeneration = 0

    init(
        suggestion: JimakuMediaSuggestion? = nil,
        client: AJATTSubtitleCatalogClient = .shared
    ) {
        self.client = client
        if let suggestion {
            sourceIdentifier = suggestion.sourceIdentifier
            query = suggestion.query
            episodeText = suggestion.episode.map(String.init) ?? ""
        }
    }

    func prepare(for suggestion: JimakuMediaSuggestion) {
        guard sourceIdentifier != suggestion.sourceIdentifier else { return }
        sourceIdentifier = suggestion.sourceIdentifier
        operationGeneration &+= 1
        query = suggestion.query
        episodeText = suggestion.episode.map(String.init) ?? ""
        isSearching = false
        isLoadingFiles = false
        hasSearched = false
        entries = []
        selectedEntry = nil
        files = []
        errorMessage = nil
    }

    func search() async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            errorMessage = String(localized: "Enter a title to search AJATT.")
            return
        }

        operationGeneration &+= 1
        let generation = operationGeneration
        isSearching = true
        isLoadingFiles = false
        hasSearched = true
        entries = []
        selectedEntry = nil
        files = []
        errorMessage = nil
        do {
            let result = try await client.searchEntries(
                query: normalizedQuery,
                kind: catalogKind
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

    func select(_ entry: AJATTEntry) async {
        guard let episode = parsedEpisode() else { return }

        operationGeneration &+= 1
        let generation = operationGeneration
        selectedEntry = entry
        files = []
        isLoadingFiles = true
        errorMessage = nil
        do {
            let result = try await client.files(for: entry, episode: episode)
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

struct AJATTSubtitleBrowserView: View {
    private static let configurationPanelWidth: CGFloat = 390
    private static let minimumPanelWidth: CGFloat = 1_080
    private static let idealPanelWidth: CGFloat = 1_200
    private static let maximumPanelWidth: CGFloat = 1_400
    private static let minimumPanelHeight: CGFloat = 660
    private static let idealPanelHeight: CGFloat = 740
    private static let maximumPanelHeight: CGFloat = 880

    @Environment(\.dismiss) private var dismiss

    let suggestion: JimakuMediaSuggestion
    let selectedFileID: String?
    let onSelectFile: (AJATTSubtitleFile) -> Void

    @State private var model: AJATTSubtitleBrowserModel

    init(
        suggestion: JimakuMediaSuggestion,
        selectedFileID: String?,
        onSelectFile: @escaping (AJATTSubtitleFile) -> Void
    ) {
        self.suggestion = suggestion
        self.selectedFileID = selectedFileID
        self.onSelectFile = onSelectFile
        _model = State(
            initialValue: AJATTSubtitleBrowserModel(suggestion: suggestion)
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
            model.prepare(for: suggestion)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Get Subtitles (AJATT)", systemImage: "icloud.and.arrow.down")
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
                VStack(alignment: .leading, spacing: 8) {
                    Label("AJATT Japanese Subtitles", systemImage: "captions.bubble.fill")
                        .font(.headline)
                    Text("AJATT provides a volunteer-maintained catalog of Japanese SRT and ASS subtitles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The catalog is downloaded when you search; your title stays on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Content Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    NativeGlassSegmentedPicker(
                        selection: $model.catalogKind,
                        values: AJATTCatalogKind.allCases,
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
                .disabled(model.isSearching || model.isLoadingFiles)

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var resultsPanel: some View {
        if model.isSearching {
            centeredStatus("Searching AJATT", systemImage: "magnifyingglass")
        } else if let entry = model.selectedEntry {
            fileResults(for: entry)
        } else if model.entries.isEmpty {
            if model.hasSearched {
                ContentUnavailableView(
                    "No AJATT Results",
                    systemImage: "captions.bubble",
                    description: Text("Try another title or content type.")
                )
            } else {
                ContentUnavailableView(
                    "Search AJATT",
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

    private func fileResults(for entry: AJATTEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.showSearchResults()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .help("Back to AJATT Results")

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
                centeredStatus("Loading AJATT Subtitles", systemImage: "arrow.down.circle")
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

    private func entryRow(_ entry: AJATTEntry) -> some View {
        Button {
            Task { await model.select(entry) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.kind.isMovie ? "film" : "play.rectangle")
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

    private func fileRow(_ file: AJATTSubtitleFile) -> some View {
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
}
