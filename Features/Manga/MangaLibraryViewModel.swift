import Foundation
import Observation

nonisolated struct MangaShelfSection: Identifiable, Sendable {
    let shelf: MangaShelf?
    var items: [MangaLibraryItem]
    var isReading = false

    var id: String {
        if isReading {
            return "__reading__"
        }
        return shelf.map { "shelf:\($0.id.uuidString)" } ?? "unshelved"
    }
}

@Observable
@MainActor
final class MangaLibraryViewModel {
    var catalog: MangaLibraryCatalog = .empty
    var hasLoadedCatalog = false
    var isScanning = false
    var shouldShowError = false
    var errorMessage = ""
    var sortOption: MangaLibrarySortOption {
        didSet {
            MangaLibraryPreferences.save(sortOption: sortOption, in: preferences)
        }
    }
    var showReading: Bool {
        didSet {
            MangaLibraryPreferences.save(showReading: showReading, in: preferences)
        }
    }

    private let store: MangaLibraryStore
    private let preferences: UserDefaults
    private var scanTask: Task<Void, Never>?
    private var isLoadingCatalog = false

    init(
        store: MangaLibraryStore = .shared,
        preferences: UserDefaults = .standard
    ) {
        self.store = store
        self.preferences = preferences
        sortOption = MangaLibraryPreferences.sortOption(in: preferences)
        showReading = MangaLibraryPreferences.showReading(in: preferences)
    }

    var visibleItems: [MangaLibraryItem] {
        catalog.items.filter { !catalog.hiddenItemIDs.contains($0.id) }
    }

    func sections() -> [MangaShelfSection] {
        var sections: [MangaShelfSection] = []

        if showReading {
            let reading = visibleItems.filter {
                $0.lastReadAt != nil
                    && $0.progress < 0.999
            }
            if !reading.isEmpty {
                sections.append(
                    MangaShelfSection(
                        shelf: MangaShelf(name: "Reading"),
                        items: sort(reading, using: readingManualOrder),
                        isReading: true
                    )
                )
            }
        }

        for shelf in catalog.shelves {
            let shelfItems = visibleItems.filter {
                shelf.itemIDs.contains($0.id)
            }
            sections.append(
                MangaShelfSection(
                    shelf: shelf,
                    items: sort(shelfItems, using: shelf.itemIDs)
                )
            )
        }

        let shelvedIDs = Set(catalog.shelves.flatMap(\.itemIDs))
        let unshelved = visibleItems.filter {
            !shelvedIDs.contains($0.id)
        }
        sections.append(
            MangaShelfSection(
                shelf: nil,
                items: sort(unshelved, using: catalog.manualItemOrder)
            )
        )
        return sections
    }

    func load() {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        Task {
            defer {
                isLoadingCatalog = false
                hasLoadedCatalog = true
            }
            catalog = await store.snapshot()
            await store.splitMergedMokuroSourcesIfNeeded()
            catalog = await store.snapshot()
        }
    }

    func addSources(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        runScan {
            for url in urls {
                try Task.checkCancellation()
                let source = try await self.store.addSource(url: url)
                try await self.store.scanSource(id: source.id)
                self.catalog = await self.store.snapshot()
            }
        }
    }

    func removeSource(id: UUID) {
        perform {
            await self.store.removeSource(id: id)
        }
    }

    func source(for item: MangaLibraryItem) -> MangaLibrarySource? {
        catalog.sources.first { $0.id == item.sourceID }
    }

    func createShelf(name: String) {
        perform {
            await self.store.createShelf(name: name)
        }
    }

    func deleteShelf(id: UUID) {
        perform {
            await self.store.deleteShelf(id: id)
        }
    }

    func moveShelves(from source: IndexSet, to destination: Int) {
        perform {
            await self.store.moveShelves(from: source, to: destination)
        }
    }

    func moveItems(_ items: Set<MangaLibraryItem>, to shelfID: UUID?) {
        moveItemIDs(Set(items.map(\.id)), to: shelfID)
    }

    func moveItem(_ item: MangaLibraryItem, to shelfID: UUID?) {
        moveItemIDs([item.id], to: shelfID)
    }

    func reorderItem(
        _ sourceID: String,
        in section: MangaShelfSection,
        before targetID: String
    ) {
        guard !section.isReading else { return }
        sortOption = .manual
        perform {
            await self.store.reorderItem(
                sourceID,
                shelfID: section.shelf?.id,
                before: targetID
            )
        }
    }

    func renameItem(_ item: MangaLibraryItem, title: String) {
        perform {
            await self.store.renameItem(id: item.id, title: title)
        }
    }

    func markRead(_ item: MangaLibraryItem) {
        perform {
            await self.store.markRead(itemID: item.id)
        }
    }

    func recordOpened(_ item: MangaLibraryItem) {
        perform {
            await self.store.recordOpened(itemID: item.id)
        }
    }

    func removeItemsFromLibrary(_ items: Set<MangaLibraryItem>) {
        let ids = Set(items.map(\.id))
        perform {
            await self.store.removeItemsFromLibrary(ids)
        }
    }

    func cancelScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private var readingManualOrder: [String] {
        catalog.shelves.flatMap(\.itemIDs) + catalog.manualItemOrder
    }

    private func sort(
        _ items: [MangaLibraryItem],
        using manualOrder: [String]
    ) -> [MangaLibraryItem] {
        switch sortOption {
        case .manual:
            let positions = Dictionary(
                uniqueKeysWithValues: manualOrder.enumerated().map { ($1, $0) }
            )
            return items.sorted {
                switch (positions[$0.id], positions[$1.id]) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
            }
        case .recent:
            return items.sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }
        case .title:
            return items.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    private func moveItemIDs(_ ids: Set<String>, to shelfID: UUID?) {
        guard !ids.isEmpty else { return }
        perform {
            await self.store.moveItems(ids, to: shelfID)
        }
    }

    private func perform(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        Task {
            await operation()
            catalog = await store.snapshot()
        }
    }

    private func runScan(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        scanTask?.cancel()
        isScanning = true
        scanTask = Task {
            defer {
                isScanning = false
                scanTask = nil
            }
            do {
                try await operation()
                catalog = await store.snapshot()
            } catch is CancellationError {
                catalog = await store.snapshot()
            } catch {
                catalog = await store.snapshot()
                errorMessage = error.localizedDescription
                shouldShowError = true
            }
        }
    }
}
