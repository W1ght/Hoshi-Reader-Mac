#if HOSHI_VIDEO
import Foundation
import Observation

enum VideoLibraryDisplayMode: String, CaseIterable, Identifiable {
    case continueWatching
    case favorites
    case unwatched
    case finished
    case missing
    case recent
    case all
    case series
    case folders
    case collections

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .continueWatching: "Continue Watching"
        case .favorites: "Favorites"
        case .unwatched: "Unwatched"
        case .finished: "Finished"
        case .missing: "Missing"
        case .recent: "Recent"
        case .all: "All Videos"
        case .series: "Series"
        case .folders: "Folders"
        case .collections: "Collections"
        }
    }
}

enum VideoLibrarySortOption: String, CaseIterable, Identifiable {
    case recentPlayback
    case title
    case modifiedDate
    case folder

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .recentPlayback: "Recent Playback"
        case .title: "File Name"
        case .modifiedDate: "Modified Date"
        case .folder: "Folder"
        }
    }
}

enum VideoLibraryLayoutMode: String, CaseIterable, Identifiable {
    case list
    case posters

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .list: "List"
        case .posters: "Posters"
        }
    }

    var systemImageName: String {
        switch self {
        case .list: "list.bullet"
        case .posters: "square.grid.2x2"
        }
    }
}

struct VideoLibraryRow: Identifiable, Equatable {
    var id: String { item.id }

    let item: VideoLibraryItem
    let sourceName: String
    let playbackState: VideoPlaybackState?
    let metadata: VideoLibraryItemMetadata
    let organization: VideoLibraryItemOrganization
    let subtitleCandidateURL: URL?

    var displayTitle: String {
        metadata.displayTitle ?? item.title
    }

    var boundSubtitleURL: URL? {
        guard let path = metadata.boundSubtitlePath else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

struct VideoLibrarySection: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [VideoLibraryRow]
}

struct VideoLibraryItemOrganization: Equatable {
    let seriesName: String
    let seasonName: String?
}

struct VideoLibrarySourceSummary: Identifiable, Equatable {
    var id: UUID { source.id }

    let source: VideoLibrarySource
    let itemCount: Int
    let inProgressCount: Int
    let missingCount: Int
}

@Observable
@MainActor
final class VideoLibraryViewModel {
    var displayMode: VideoLibraryDisplayMode = .continueWatching
    var layoutMode: VideoLibraryLayoutMode = .list
    var sortOption: VideoLibrarySortOption = .title
    var searchText = ""
    var showUnfinishedOnly = false
    var selectedItemID: String?
    var selectedItemIDs: Set<String> = []
    var catalog: VideoLibraryCatalog
    var isScanning = false
    var shouldShowError = false
    var errorMessage = ""
    private(set) var playbackHistoryRevision = 0

    private let store: VideoLibraryStore
    private let historyStore: VideoPlaybackHistoryStore

    init(
        store: VideoLibraryStore = VideoLibraryStore(),
        historyStore: VideoPlaybackHistoryStore = VideoPlaybackHistoryStore()
    ) {
        self.store = store
        self.historyStore = historyStore
        self.catalog = store.catalog
    }

    var sources: [VideoLibrarySource] {
        catalog.sources
    }

    var hasSources: Bool {
        !catalog.sources.isEmpty
    }

    var selectedRow: VideoLibraryRow? {
        guard let selectedItemID else { return nil }
        return rows(for: catalog.items).first { $0.id == selectedItemID }
    }

    var sourceSummaries: [VideoLibrarySourceSummary] {
        _ = playbackHistoryRevision
        let rowsBySource = Dictionary(grouping: rows(for: catalog.items)) { $0.item.sourceID }
        return catalog.sources.map { source in
            let rows = rowsBySource[source.id] ?? []
            return VideoLibrarySourceSummary(
                source: source,
                itemCount: rows.count,
                inProgressCount: rows.filter { $0.playbackState?.isResumable == true }.count,
                missingCount: rows.filter { isMissing($0.item) }.count
            )
        }
    }

    var emptyTitleKey: String {
        if isFiltering {
            return "No Matching Videos"
        }
        switch displayMode {
        case .continueWatching:
            return "No Videos in Progress"
        case .favorites:
            return "No Favorite Videos"
        case .unwatched:
            return "No Unwatched Videos"
        case .finished:
            return "No Finished Videos"
        case .missing:
            return "No Missing Videos"
        case .recent:
            return "No Recent Videos"
        case .all, .series, .folders, .collections:
            return "No Videos"
        }
    }

    var emptyDescriptionKey: String {
        if isFiltering {
            return "Try a different search or filter."
        }
        switch displayMode {
        case .continueWatching:
            return "Partially watched videos will appear here."
        case .favorites:
            return "Favorite videos will appear here."
        case .unwatched:
            return "Videos without playback progress will appear here."
        case .finished:
            return "Videos marked watched will appear here."
        case .missing:
            return "Missing videos will appear here until their source is refreshed."
        case .recent:
            return "Played videos will appear here."
        case .all, .series, .folders, .collections:
            return "Refresh your folders or add another source."
        }
    }

    func load() {
        catalog = store.catalog
    }

    func refreshPlaybackHistory() {
        playbackHistoryRevision &+= 1
    }

    func addFolders(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isScanning = true
            defer { isScanning = false }

            for url in urls {
                let source = try store.addSource(folderURL: url)
                try store.scanSource(id: source.id)
            }
            catalog = store.catalog
        } catch {
            catalog = store.catalog
            showError(error.localizedDescription)
        }
    }

    func refreshAllSources() {
        guard !catalog.sources.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            try store.scanAllSources()
            catalog = store.catalog
        } catch {
            catalog = store.catalog
            showError(error.localizedDescription)
        }
    }

    func refreshSource(id: UUID) {
        isScanning = true
        defer { isScanning = false }
        do {
            try store.scanSource(id: id)
            catalog = store.catalog
        } catch {
            catalog = store.catalog
            showError(error.localizedDescription)
        }
    }

    func removeSource(id: UUID) {
        store.removeSource(id: id)
        catalog = store.catalog
        let itemIDs = Set(catalog.items.map(\.id))
        selectedItemIDs = selectedItemIDs.intersection(itemIDs)
        if let selectedItemID, !catalog.items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }

    func select(item: VideoLibraryItem) {
        selectedItemID = item.id
        selectedItemIDs = [item.id]
    }

    func openURL(for item: VideoLibraryItem) -> URL? {
        let url = store.resolvedURL(for: item)
        guard FileManager.default.fileExists(atPath: url.path) else {
            refreshSourceAfterMissingItem(item)
            showError(String(localized: "The saved video file is no longer available."))
            return nil
        }
        return url
    }

    func subtitleURLForOpening(_ item: VideoLibraryItem) -> URL? {
        guard let path = store.metadata(for: item).boundSubtitlePath else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func openFromBeginningURL(for item: VideoLibraryItem) -> URL? {
        historyStore.clearProgress(for: item.url)
        refreshPlaybackHistory()
        return openURL(for: item)
    }

    func markWatched(_ item: VideoLibraryItem) {
        let duration = historyStore.playbackState(for: item.url)?.duration
        historyStore.markWatched(duration: duration, for: item.url)
        refreshPlaybackHistory()
    }

    func clearProgress(_ item: VideoLibraryItem) {
        historyStore.clearProgress(for: item.url)
        refreshPlaybackHistory()
    }

    func setDisplayTitle(_ title: String?, for item: VideoLibraryItem) {
        store.setDisplayTitle(title, for: item)
        catalog = store.catalog
    }

    func setFavorite(_ isFavorite: Bool, for item: VideoLibraryItem) {
        store.setFavorite(isFavorite, for: item)
        catalog = store.catalog
    }

    func setTags(_ tags: [String], for item: VideoLibraryItem) {
        store.setTags(tags, for: item)
        catalog = store.catalog
    }

    func bindSubtitle(_ subtitleURL: URL?, for item: VideoLibraryItem) {
        store.bindSubtitle(subtitleURL, for: item)
        catalog = store.catalog
    }

    @discardableResult
    func createCollection(
        name: String,
        items: [VideoLibraryItem]
    ) -> VideoLibraryCollection {
        let collection = store.createCollection(name: name, itemPaths: items.map(\.path))
        catalog = store.catalog
        return collection
    }

    func setCollectionMembership(
        _ isIncluded: Bool,
        collectionID: UUID,
        for item: VideoLibraryItem
    ) {
        guard let collection = catalog.collections.first(where: { $0.id == collectionID }) else {
            return
        }
        var itemPaths = collection.itemPaths
        if isIncluded {
            if !itemPaths.contains(item.path) {
                itemPaths.append(item.path)
            }
        } else {
            itemPaths.removeAll { $0 == item.path }
        }
        store.updateCollection(id: collectionID, name: collection.name, itemPaths: itemPaths)
        catalog = store.catalog
    }

    func removeCollection(id: UUID) {
        store.removeCollection(id: id)
        catalog = store.catalog
    }

    func markSelectedWatched() {
        for item in selectedItems {
            markWatched(item)
        }
    }

    func clearSelectedProgress() {
        for item in selectedItems {
            clearProgress(item)
        }
    }

    @discardableResult
    func removeMissingItems(sourceID: UUID? = nil) -> Int {
        let removed = store.removeMissingItems(sourceID: sourceID)
        catalog = store.catalog
        let itemIDs = Set(catalog.items.map(\.id))
        selectedItemIDs = selectedItemIDs.intersection(itemIDs)
        if let selectedItemID, !itemIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        return removed
    }

    func sections() -> [VideoLibrarySection] {
        _ = playbackHistoryRevision
        let rows = queriedRows()
        switch displayMode {
        case .continueWatching:
            let continueRows = rows
                .filter { $0.playbackState?.isResumable == true }
                .sorted(by: recentPlaybackSort)
            return continueRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "continue", title: String(localized: "Continue Watching"), rows: continueRows)]
        case .favorites:
            let favoriteRows = rows
                .filter { $0.metadata.isFavorite }
            return favoriteRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "favorites", title: String(localized: "Favorites"), rows: favoriteRows)]
        case .unwatched:
            let unwatchedRows = rows
                .filter { $0.playbackState == nil && !isMissing($0.item) }
            return unwatchedRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "unwatched", title: String(localized: "Unwatched"), rows: unwatchedRows)]
        case .finished:
            let finishedRows = rows
                .filter { $0.playbackState?.isFinished == true }
                .sorted(by: recentPlaybackSort)
            return finishedRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "finished", title: String(localized: "Finished"), rows: finishedRows)]
        case .missing:
            let missingRows = rows
                .filter { isMissing($0.item) }
            return missingRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "missing", title: String(localized: "Missing"), rows: missingRows)]
        case .recent:
            let recentRows = rows
                .filter { $0.playbackState != nil }
                .sorted(by: recentPlaybackSort)
            return recentRows.isEmpty
                ? []
                : [VideoLibrarySection(id: "recent", title: String(localized: "Recent"), rows: recentRows)]
        case .all:
            return rows.isEmpty
                ? []
                : [VideoLibrarySection(id: "all", title: String(localized: "All Videos"), rows: rows)]
        case .series:
            return groupedSections(
                rows: rows,
                idPrefix: "series",
                title: { $0.organization.seriesName },
                sort: seriesSort
            )
        case .folders:
            let sourceNames = Dictionary(uniqueKeysWithValues: catalog.sources.map { ($0.id, $0.name) })
            return Dictionary(grouping: rows) { row in
                sourceNames[row.item.sourceID] ?? row.item.parentFolder
            }
            .map { name, rows in
                VideoLibrarySection(
                    id: name,
                    title: name,
                    rows: rows.sorted(by: sortRows)
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .collections:
            let rowsByPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.item.path, $0) })
            return catalog.collections.compactMap { collection in
                let collectionRows = collection.itemPaths.compactMap { rowsByPath[$0] }
                guard !collectionRows.isEmpty else { return nil }
                return VideoLibrarySection(
                    id: "collection-\(collection.id.uuidString)",
                    title: collection.name,
                    rows: collectionRows.sorted(by: sortRows)
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func queriedRows() -> [VideoLibraryRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows(for: catalog.items)
            .filter { row in
                guard !query.isEmpty else { return true }
                return row.matches(query)
            }
            .filter { row in
                guard showUnfinishedOnly else { return true }
                guard let state = row.playbackState else { return false }
                return state.isResumable
            }
            .sorted(by: sortRows)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || showUnfinishedOnly
    }

    private var selectedItems: [VideoLibraryItem] {
        catalog.items.filter { selectedItemIDs.contains($0.id) }
    }

    private func rows(for items: [VideoLibraryItem]) -> [VideoLibraryRow] {
        let sourcesByID = Dictionary(uniqueKeysWithValues: catalog.sources.map { ($0.id, $0) })
        let playbackStates = historyStore.playbackStates(for: items.map(\.url))
        return items.map { item in
            let source = sourcesByID[item.sourceID]
            let metadata = store.metadata(for: item)
            return VideoLibraryRow(
                item: item,
                sourceName: source?.name ?? item.parentFolder,
                playbackState: playbackStates[item.url.standardizedFileURL.path],
                metadata: metadata,
                organization: organization(for: item, source: source),
                subtitleCandidateURL: subtitleCandidateURL(for: item, metadata: metadata)
            )
        }
    }

    private func sortRows(_ lhs: VideoLibraryRow, _ rhs: VideoLibraryRow) -> Bool {
        switch sortOption {
        case .recentPlayback:
            return recentPlaybackSort(lhs, rhs)
        case .title:
            return titleSort(lhs, rhs)
        case .modifiedDate:
            let lhsDate = lhs.item.modifiedAt ?? .distantPast
            let rhsDate = rhs.item.modifiedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return titleSort(lhs, rhs)
        case .folder:
            let folderCompare = lhs.item.parentFolder.localizedStandardCompare(rhs.item.parentFolder)
            if folderCompare != .orderedSame {
                return folderCompare == .orderedAscending
            }
            return titleSort(lhs, rhs)
        }
    }

    private func recentPlaybackSort(_ lhs: VideoLibraryRow, _ rhs: VideoLibraryRow) -> Bool {
        let lhsDate = lhs.playbackState?.updatedAt ?? .distantPast
        let rhsDate = rhs.playbackState?.updatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return titleSort(lhs, rhs)
    }

    private func titleSort(_ lhs: VideoLibraryRow, _ rhs: VideoLibraryRow) -> Bool {
        let titleCompare = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
        if titleCompare != .orderedSame {
            return titleCompare == .orderedAscending
        }
        return lhs.item.path.localizedStandardCompare(rhs.item.path) == .orderedAscending
    }

    private func seriesSort(_ lhs: VideoLibraryRow, _ rhs: VideoLibraryRow) -> Bool {
        let lhsSeason = lhs.organization.seasonName ?? ""
        let rhsSeason = rhs.organization.seasonName ?? ""
        let seasonCompare = lhsSeason.localizedStandardCompare(rhsSeason)
        if seasonCompare != .orderedSame {
            return seasonCompare == .orderedAscending
        }
        return titleSort(lhs, rhs)
    }

    private func groupedSections(
        rows: [VideoLibraryRow],
        idPrefix: String,
        title: (VideoLibraryRow) -> String,
        sort: (VideoLibraryRow, VideoLibraryRow) -> Bool
    ) -> [VideoLibrarySection] {
        Dictionary(grouping: rows, by: title)
            .map { name, rows in
                VideoLibrarySection(
                    id: "\(idPrefix)-\(name)",
                    title: name,
                    rows: rows.sorted(by: sort)
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func organization(
        for item: VideoLibraryItem,
        source: VideoLibrarySource?
    ) -> VideoLibraryItemOrganization {
        guard let source else {
            return VideoLibraryItemOrganization(seriesName: item.parentFolder, seasonName: nil)
        }
        let sourceURL = URL(fileURLWithPath: source.path).standardizedFileURL
        let parentURL = item.url.deletingLastPathComponent().standardizedFileURL
        let sourceComponents = sourceURL.pathComponents
        let parentComponents = parentURL.pathComponents
        let relativeComponents = Array(parentComponents.dropFirst(sourceComponents.count))
        guard let first = relativeComponents.first else {
            return VideoLibraryItemOrganization(seriesName: source.name, seasonName: nil)
        }
        if relativeComponents.count >= 2 {
            return VideoLibraryItemOrganization(
                seriesName: first,
                seasonName: relativeComponents[1]
            )
        }
        if Self.looksLikeSeason(first) {
            return VideoLibraryItemOrganization(seriesName: source.name, seasonName: first)
        }
        return VideoLibraryItemOrganization(seriesName: first, seasonName: nil)
    }

    private func subtitleCandidateURL(
        for item: VideoLibraryItem,
        metadata: VideoLibraryItemMetadata
    ) -> URL? {
        if let boundPath = metadata.boundSubtitlePath {
            return URL(fileURLWithPath: boundPath).standardizedFileURL
        }
        return nil
    }

    private func refreshSourceAfterMissingItem(_ item: VideoLibraryItem) {
        do {
            try store.scanSource(id: item.sourceID)
            catalog = store.catalog
        } catch {
            catalog = store.catalog
        }
    }

    private func isMissing(_ item: VideoLibraryItem) -> Bool {
        !FileManager.default.fileExists(atPath: item.url.path)
    }

    private func showError(_ message: String) {
        errorMessage = message
        shouldShowError = true
    }

    private static func looksLikeSeason(_ component: String) -> Bool {
        component.range(
            of: #"(?i)\b(season|saison|temporada|s)\s*\d+\b"#,
            options: .regularExpression
        ) != nil
    }
}

private extension VideoLibraryRow {
    func matches(_ query: String) -> Bool {
        let fields = [
            displayTitle,
            item.title,
            item.parentFolder,
            sourceName,
            organization.seriesName,
            organization.seasonName ?? "",
            metadata.tags.joined(separator: " "),
            metadata.boundSubtitlePath ?? "",
            item.path,
        ]
        return fields.contains { field in
            field.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
#endif
