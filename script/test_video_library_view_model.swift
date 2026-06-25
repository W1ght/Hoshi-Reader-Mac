import Foundation

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message): expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

private func touch(_ url: URL, modified: Date, size: Int = 1) throws {
    FileManager.default.createFile(
        atPath: url.path,
        contents: Data(repeating: 0x31, count: size)
    )
    try FileManager.default.setAttributes(
        [.modificationDate: modified],
        ofItemAtPath: url.path
    )
}

@main
private enum VideoLibraryViewModelTests {
    @MainActor
    static func main() throws {
        try testContinueWatchingShowsOnlyResumableVideos()
        try testSearchMatchesTitleFolderSourceAndPath()
        try testSortOptionsOrderAllVideos()
        try testUnfinishedFilterUsesIncompletePlaybackState()
        try testSmartFiltersSplitUnwatchedFinishedAndMissingVideos()
        try testSourceSummariesCountItemsAndRefreshOneSource()
        try testV3OrganizationMetadataSubtitleAndCollections()
        try testV3SelectionBatchActionsAndMissingCleanup()
        try testPlaybackStateActionsUpdateRows()
        try testFilteredEmptyStateUsesSearchCopy()
        try testPlaybackHistoryRefreshAdvancesRevision()
        print("Video library view model tests passed")
    }

    @MainActor
    private static func makeViewModel() throws -> VideoLibraryViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-library-view-model-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Anime Source", isDirectory: true)
        let season1 = source.appendingPathComponent("Season 1", isDirectory: true)
        let season2 = source.appendingPathComponent("Season 2", isDirectory: true)
        try FileManager.default.createDirectory(at: season1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: season2, withIntermediateDirectories: true)

        try touch(
            season1.appendingPathComponent("Alpha.mp4"),
            modified: Date(timeIntervalSince1970: 10),
            size: 10
        )
        try touch(
            season2.appendingPathComponent("Beta.mkv"),
            modified: Date(timeIntervalSince1970: 30),
            size: 30
        )
        try touch(
            source.appendingPathComponent("Gamma.webm"),
            modified: Date(timeIntervalSince1970: 20),
            size: 20
        )

        let store = VideoLibraryStore(
            fileURL: root.appendingPathComponent("library.json"),
            fileManager: .default
        )
        let librarySource = try store.addSource(folderURL: source)
        try store.scanSource(id: librarySource.id)

        let suiteName = "moe.shishamo.hoshi.tests.video-library-view-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let history = VideoPlaybackHistoryStore(defaults: defaults)
        history.savePlaybackState(
            position: 20,
            duration: 100,
            updatedAt: Date(timeIntervalSince1970: 100),
            for: season1.appendingPathComponent("Alpha.mp4")
        )
        history.savePlaybackState(
            position: 50,
            duration: 100,
            updatedAt: Date(timeIntervalSince1970: 200),
            for: season2.appendingPathComponent("Beta.mkv")
        )

        return VideoLibraryViewModel(store: store, historyStore: history)
    }

    @MainActor
    private static func makeOrganizedViewModel() throws -> VideoLibraryViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-library-organized-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Library", isDirectory: true)
        let showSeason1 = source
            .appendingPathComponent("Show A", isDirectory: true)
            .appendingPathComponent("Season 1", isDirectory: true)
        let showSeason2 = source
            .appendingPathComponent("Show A", isDirectory: true)
            .appendingPathComponent("Season 2", isDirectory: true)
        let movies = source.appendingPathComponent("Movies", isDirectory: true)
        try FileManager.default.createDirectory(at: showSeason1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: showSeason2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)

        try touch(
            showSeason1.appendingPathComponent("Episode 01.mp4"),
            modified: Date(timeIntervalSince1970: 10),
            size: 10
        )
        try touch(
            showSeason2.appendingPathComponent("Episode 02.mkv"),
            modified: Date(timeIntervalSince1970: 20),
            size: 20
        )
        try touch(
            showSeason1.appendingPathComponent("Episode 01.ja.srt"),
            modified: Date(timeIntervalSince1970: 11),
            size: 1
        )
        try touch(
            movies.appendingPathComponent("Movie.webm"),
            modified: Date(timeIntervalSince1970: 30),
            size: 30
        )

        let store = VideoLibraryStore(
            fileURL: root.appendingPathComponent("library.json"),
            fileManager: .default
        )
        let librarySource = try store.addSource(folderURL: source)
        try store.scanSource(id: librarySource.id)

        let suiteName = "moe.shishamo.hoshi.tests.video-library-organized-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let history = VideoPlaybackHistoryStore(defaults: defaults)
        return VideoLibraryViewModel(store: store, historyStore: history)
    }

    @MainActor
    private static func titles(_ viewModel: VideoLibraryViewModel) -> [String] {
        viewModel.sections().flatMap(\.rows).map(\.displayTitle)
    }

    @MainActor
    private static func row(_ viewModel: VideoLibraryViewModel, title: String) -> VideoLibraryRow {
        guard let row = viewModel.sections().flatMap(\.rows).first(where: { $0.item.title == title }) else {
            fputs("FAIL: expected row titled \(title)\n", stderr)
            exit(1)
        }
        return row
    }

    @MainActor
    private static func item(_ viewModel: VideoLibraryViewModel, title: String) -> VideoLibraryItem {
        guard let item = viewModel.catalog.items.first(where: { $0.title == title }) else {
            fputs("FAIL: expected catalog item titled \(title)\n", stderr)
            exit(1)
        }
        return item
    }

    @MainActor
    private static func itemContaining(_ viewModel: VideoLibraryViewModel, title: String) -> VideoLibraryItem {
        guard let item = viewModel.catalog.items.first(where: { $0.title.contains(title) }) else {
            fputs("FAIL: expected catalog item containing \(title)\n", stderr)
            exit(1)
        }
        return item
    }

    @MainActor
    private static func testContinueWatchingShowsOnlyResumableVideos() throws {
        let viewModel = try makeViewModel()

        expect(viewModel.displayMode, .continueWatching, "video library should open on continue watching")
        expect(
            titles(viewModel),
            ["Beta", "Alpha"],
            "continue watching should show only resumable videos ordered by recent playback"
        )
    }

    @MainActor
    private static func testSearchMatchesTitleFolderSourceAndPath() throws {
        let viewModel = try makeViewModel()
        viewModel.displayMode = .all

        viewModel.searchText = "beta"
        expect(titles(viewModel), ["Beta"], "search should match video title")

        viewModel.searchText = "season 1"
        expect(titles(viewModel), ["Alpha"], "search should match parent folder")

        viewModel.searchText = "anime source"
        expect(
            titles(viewModel),
            ["Alpha", "Beta", "Gamma"],
            "search should match source name"
        )
    }

    @MainActor
    private static func testSortOptionsOrderAllVideos() throws {
        let viewModel = try makeViewModel()
        viewModel.displayMode = .all

        viewModel.sortOption = .title
        expect(titles(viewModel), ["Alpha", "Beta", "Gamma"], "title sort should be ascending")

        viewModel.sortOption = .modifiedDate
        expect(titles(viewModel), ["Beta", "Gamma", "Alpha"], "modified sort should be newest first")

        viewModel.sortOption = .folder
        expect(titles(viewModel), ["Gamma", "Alpha", "Beta"], "folder sort should group by folder name then title")

        viewModel.sortOption = .recentPlayback
        expect(titles(viewModel), ["Beta", "Alpha", "Gamma"], "recent playback sort should put played videos first")
    }

    @MainActor
    private static func testUnfinishedFilterUsesIncompletePlaybackState() throws {
        let viewModel = try makeViewModel()
        viewModel.displayMode = .all
        viewModel.showUnfinishedOnly = true

        expect(
            titles(viewModel),
            ["Alpha", "Beta"],
            "unfinished filter should show only videos with incomplete playback state"
        )
    }

    @MainActor
    private static func testSmartFiltersSplitUnwatchedFinishedAndMissingVideos() throws {
        let viewModel = try makeViewModel()

        viewModel.displayMode = .unwatched
        expect(titles(viewModel), ["Gamma"], "unwatched filter should show existing videos without playback state")

        viewModel.markWatched(item(viewModel, title: "Beta"))
        viewModel.displayMode = .finished
        expect(titles(viewModel), ["Beta"], "finished filter should show videos marked watched")

        try FileManager.default.removeItem(at: item(viewModel, title: "Gamma").url)
        viewModel.displayMode = .missing
        expect(titles(viewModel), ["Gamma"], "missing filter should show catalog items whose files are gone")

        expect(viewModel.emptyTitleKey, "No Missing Videos", "missing view should have specific empty-state copy")
        expect(
            viewModel.emptyDescriptionKey,
            "Missing videos will appear here until their source is refreshed.",
            "missing view should explain stale items"
        )
    }

    @MainActor
    private static func testSourceSummariesCountItemsAndRefreshOneSource() throws {
        let viewModel = try makeViewModel()
        var summary = viewModel.sourceSummaries.first!

        expect(summary.itemCount, 3, "source summary should count all videos in the source")
        expect(summary.inProgressCount, 2, "source summary should count resumable videos")
        expect(summary.missingCount, 0, "source summary should start with no missing videos")

        try FileManager.default.removeItem(at: item(viewModel, title: "Gamma").url)
        summary = viewModel.sourceSummaries.first!
        expect(summary.missingCount, 1, "source summary should count catalog items missing on disk")

        viewModel.refreshSource(id: summary.id)
        summary = viewModel.sourceSummaries.first!
        expect(summary.itemCount, 2, "single-source refresh should remove stale items after a successful scan")
        expect(summary.missingCount, 0, "single-source refresh should clear missing count after stale removal")
    }

    @MainActor
    private static func testV3OrganizationMetadataSubtitleAndCollections() throws {
        let viewModel = try makeOrganizedViewModel()
        let episode1 = itemContaining(viewModel, title: "Episode 01")
        let subtitleURL = episode1.url
            .deletingPathExtension()
            .appendingPathExtension("ja.srt")

        viewModel.displayMode = .series
        expect(
            viewModel.sections().map(\.title),
            ["Movies", "Show A"],
            "series view should group videos by inferred source-relative series"
        )
        expect(
            viewModel.sections().filter { $0.title == "Show A" }.first?.rows.map(\.organization.seasonName),
            ["Season 1", "Season 2"],
            "series rows should expose inferred season names"
        )

        viewModel.setDisplayTitle("Pilot", for: episode1)
        viewModel.setFavorite(true, for: episode1)
        viewModel.setTags(["Anime", "Listening", "Anime"], for: episode1)
        viewModel.bindSubtitle(subtitleURL, for: episode1)
        let collection = viewModel.createCollection(name: "Weekend", items: [episode1])

        viewModel.displayMode = .favorites
        expect(titles(viewModel), ["Pilot"], "favorites view should show favorited videos with display titles")

        viewModel.displayMode = .all
        viewModel.searchText = "listening"
        expect(titles(viewModel), ["Pilot"], "search should match custom tags")
        viewModel.searchText = ""

        let pilotRow = row(viewModel, title: "Episode 01")
        expect(pilotRow.displayTitle, "Pilot", "row should expose custom display title")
        expect(pilotRow.metadata.tags, ["Anime", "Listening"], "row should expose normalized tags")
        expect(
            pilotRow.boundSubtitleURL,
            subtitleURL.standardizedFileURL,
            "row should expose manually bound subtitles"
        )
        expect(
            pilotRow.subtitleCandidateURL,
            subtitleURL.standardizedFileURL,
            "row should expose manually bound subtitle candidates without scanning folders"
        )
        expect(
            viewModel.subtitleURLForOpening(episode1),
            subtitleURL.standardizedFileURL,
            "opening a video with a bound subtitle should pass that subtitle to the player"
        )
        viewModel.bindSubtitle(nil, for: episode1)
        let unboundPilotRow = row(viewModel, title: "Episode 01")
        expect(
            unboundPilotRow.subtitleCandidateURL,
            nil,
            "row construction should not scan folders for same-name subtitle candidates"
        )

        viewModel.displayMode = .collections
        expect(viewModel.sections().map(\.title), ["Weekend"], "collections view should group custom collections")
        expect(titles(viewModel), ["Pilot"], "collections view should show collection videos")
        expect(collection.name, "Weekend", "collection creation should return the saved collection")

        viewModel.setCollectionMembership(false, collectionID: collection.id, for: episode1)
        expect(
            viewModel.sections(),
            [],
            "removing a video from a collection should remove it from the collections view"
        )

        viewModel.setCollectionMembership(true, collectionID: collection.id, for: episode1)
        expect(titles(viewModel), ["Pilot"], "adding a video back to a collection should restore it")

        viewModel.removeCollection(id: collection.id)
        expect(viewModel.catalog.collections, [], "removing a collection should delete the collection")
        viewModel.displayMode = .all
        expect(
            row(viewModel, title: "Episode 01").metadata.collectionIDs,
            [],
            "removing a collection should clear item collection metadata"
        )
    }

    @MainActor
    private static func testV3SelectionBatchActionsAndMissingCleanup() throws {
        let viewModel = try makeOrganizedViewModel()
        let episode1 = itemContaining(viewModel, title: "Episode 01")
        let episode2 = itemContaining(viewModel, title: "Episode 02")
        let movie = item(viewModel, title: "Movie")

        viewModel.select(item: episode1)
        expect(
            viewModel.selectedRow?.item.path,
            episode1.path,
            "selecting an item should expose its detail row"
        )

        viewModel.selectedItemIDs = Set([episode1.id, episode2.id])
        viewModel.markSelectedWatched()
        viewModel.displayMode = .finished
        expect(
            titles(viewModel),
            ["Episode 02", "Episode 01"],
            "batch mark watched should update selected videos"
        )

        viewModel.clearSelectedProgress()
        expect(
            titles(viewModel),
            [],
            "batch clear progress should remove selected videos from finished view"
        )

        try FileManager.default.removeItem(at: movie.url)
        viewModel.displayMode = .missing
        expect(titles(viewModel), ["Movie"], "missing view should include deleted files before cleanup")
        let removed = viewModel.removeMissingItems()
        expect(removed, 1, "missing cleanup should report removed item count")
        expect(titles(viewModel), [], "missing cleanup should remove stale rows")
    }

    @MainActor
    private static func testPlaybackStateActionsUpdateRows() throws {
        let viewModel = try makeViewModel()

        viewModel.markWatched(row(viewModel, title: "Beta").item)
        expect(
            titles(viewModel),
            ["Alpha"],
            "mark watched should remove the video from continue watching"
        )

        viewModel.displayMode = .recent
        let watched = row(viewModel, title: "Beta")
        expect(watched.playbackState?.isFinished, true, "marked watched row should keep finished state")

        viewModel.clearProgress(watched.item)
        expect(
            titles(viewModel),
            ["Alpha"],
            "clear progress should remove the video from recent playback"
        )

        viewModel.displayMode = .continueWatching
        let alpha = row(viewModel, title: "Alpha")
        let url = viewModel.openFromBeginningURL(for: alpha.item)
        expect(url, alpha.item.url, "open from beginning should resolve the item URL")
        expect(
            titles(viewModel),
            [],
            "open from beginning should clear resume progress before opening"
        )
    }


    @MainActor
    private static func testFilteredEmptyStateUsesSearchCopy() throws {
        let viewModel = try makeViewModel()
        viewModel.displayMode = .all

        expect(viewModel.emptyTitleKey, "No Videos", "unfiltered all view should use the normal empty title")
        expect(
            viewModel.emptyDescriptionKey,
            "Refresh your folders or add another source.",
            "unfiltered all view should keep the normal empty description"
        )

        viewModel.searchText = "missing title"
        expect(
            viewModel.emptyTitleKey,
            "No Matching Videos",
            "filtered empty view should say no videos matched"
        )
        expect(
            viewModel.emptyDescriptionKey,
            "Try a different search or filter.",
            "filtered empty view should suggest changing filters"
        )
    }

    @MainActor
    private static func testPlaybackHistoryRefreshAdvancesRevision() throws {
        let viewModel = try makeViewModel()
        let revision = viewModel.playbackHistoryRevision

        viewModel.refreshPlaybackHistory()

        expect(
            viewModel.playbackHistoryRevision,
            revision + 1,
            "refreshing playback history should advance the observable revision"
        )
    }
}
