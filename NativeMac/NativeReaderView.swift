import AppKit
import EPUBKit
import SwiftUI
import WebKit
import CHoshiDicts

enum NativeReaderNavigationDirection: Equatable {
    case forward
    case backward
}

struct NativeReaderPageNavigation: Equatable {
    let id = UUID()
    let direction: NativeReaderNavigationDirection
}

private enum NativeReaderSheet: Identifiable {
    case appearance
    case chapters
    case highlights
    case statistics
    case sasayaki

    var id: Self { self }
}

struct NativeReaderLoader: View {
    @Environment(UserConfig.self) private var userConfig
    let book: BookMetadata
    var onClose: () -> Void
    @State private var model: NativeReaderModel

    init(book: BookMetadata, onClose: @escaping () -> Void) {
        self.book = book
        self.onClose = onClose
        _model = State(initialValue: NativeReaderModel(book: book))
    }

    var body: some View {
        Group {
            if model.document != nil {
                NativeReaderView(model: model, onClose: onClose)
            } else {
                ContentUnavailableView {
                    Label("Unable to Open Book", systemImage: "book.pages")
                } description: {
                    Text("The EPUB file could not be loaded from local storage.")
                }
            }
        }
        .task {
            model.configure(userConfig: userConfig)
            model.loadBook()
        }
    }
}

@Observable
@MainActor
final class NativeReaderModel {
    let book: BookMetadata
    let bridge = WebViewBridge()
    var document: EPUBDocument?
    var rootURL: URL?
    var bookInfo = BookInfo(characterCount: 0, chapterInfo: [:])
    var index = 0
    var progress: Double = 0
    var isLoading = true
    var popups: [NativeReaderPopup] = []
    var popup: NativeReaderPopup? { popups.last }
    var imageURL: URL?
    var highlights: [Highlight] = []
    var highlightRevision = 0
    var loadRevision = 0
    var pendingFragment: String?
    var isTracking = false
    var isPaused = false
    var lastTimestamp: Date = .now
    var lastCount = 0
    var stats: [Statistics] = []
    var sessionStatistics = NativeReaderModel.defaultStatistic(title: "")
    var todaysStatistics = NativeReaderModel.defaultStatistic(title: "")
    var allTimeStatistics = NativeReaderModel.defaultStatistic(title: "")
    var sasayakiPlayer: SasayakiPlayer?
    var wasPaused = false

    private var enableStatistics = false
    private var autostartStatistics = false
    private var autoSyncEnabled = false
    private var syncBookData = false
    private var syncStats = false
    private var statsSyncMode: StatisticsSyncMode = .merge
    private var syncAudioBook = false
    private var pendingAutoExport = false
    private var debounceTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init(book: BookMetadata) {
        self.book = book
    }

    func configure(userConfig: UserConfig) {
        enableStatistics = userConfig.enableStatistics
        autostartStatistics = userConfig.statisticsAutostartMode == .on
        autoSyncEnabled = userConfig.enableSync && userConfig.enableAutoSync
        syncBookData = userConfig.enableSync && userConfig.syncUploadBooks
        syncStats = userConfig.enableSync && userConfig.statisticsEnableSync
        statsSyncMode = userConfig.statisticsSyncMode
        syncAudioBook = userConfig.enableSasayaki && userConfig.sasayakiEnableSync
    }

    func loadBook() {
        guard document == nil,
              let root = rootDirectory,
              let epubURL else {
            return
        }

        guard let doc = try? BookStorage.loadEpub(epubURL) else {
            return
        }

        CSSSanitizer.sanitizeDirectory(doc.contentDirectory)
        document = doc
        rootURL = root
        bookInfo = BookStorage.loadBookInfo(root: root) ?? BookInfo(characterCount: 0, chapterInfo: [:])
        highlights = BookStorage.loadHighlights(root: root) ?? []
        setupSasayakiPlayer(rootURL: root)
        loadStatistics()

        if let bookmark = BookStorage.loadBookmark(root: root) {
            index = min(max(bookmark.chapterIndex, 0), max(doc.spine.items.count - 1, 0))
            progress = bookmark.progress
        }
        loadCurrentChapterState()

        if autostartStatistics {
            startTracking()
        }

        var bookCopy = book
        bookCopy.lastAccess = Date()
        try? BookStorage.save(bookCopy, inside: root, as: FileNames.metadata)
    }

    func syncOnOpenIfNeeded() async {
        guard autoSyncEnabled else {
            resetTrackingBaseline()
            return
        }
        let result = try? await SyncManager.shared.syncBook(
            book: book,
            direction: nil,
            syncBookData: syncBookData,
            syncStats: syncStats,
            statsSyncMode: statsSyncMode,
            syncAudioBook: syncAudioBook,
            importOnly: true
        )
        if case .imported = result {
            reloadBookmark()
        }
        loadCurrentChapterState()
        resetTrackingBaseline()
    }

    var title: String {
        document?.title ?? book.displayTitle
    }

    var currentChapterURL: URL? {
        guard let document,
              document.spine.items.indices.contains(index),
              let item = document.manifest.items[document.spine.items[index].idref] else {
            return nil
        }
        return document.contentDirectory.appendingPathComponent(item.path)
    }

    var readerReadAccessURL: URL? {
        document?.contentDirectory ?? rootURL
    }

    var coverURL: URL? {
        guard let rootURL else { return nil }
        return BookStorage.loadMetadata(root: rootURL)?.coverURL
    }

    var currentCharacter: Int {
        guard let document,
              document.spine.items.indices.contains(index),
              let item = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[item.path] else {
            return 0
        }
        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * progress)
    }

    var currentChapterCount: Int {
        guard let document,
              document.spine.items.indices.contains(index),
              let item = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[item.path] else {
            return 0
        }
        return chapterInfo.currentTotal + chapterInfo.chapterCount
    }

    private var chapterRange: (start: Int, end: Int)? {
        guard let document,
              document.spine.items.indices.contains(index),
              let item = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[item.path] else {
            return nil
        }
        return (chapterInfo.currentTotal, chapterInfo.currentTotal + chapterInfo.chapterCount)
    }

    func chapterHighlightsJSON() -> String? {
        guard let range = chapterRange else { return nil }
        let list = highlights.filter { $0.character >= range.start && $0.character < range.end }
        guard !list.isEmpty,
              let data = try? JSONEncoder().encode(list) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func updateProgress(_ newProgress: Double) {
        progress = min(max(newProgress, 0), 1)
    }

    func saveBookmark(_ newProgress: Double) {
        guard let rootURL else { return }
        updateProgress(newProgress)
        let bookmark = Bookmark(
            chapterIndex: index,
            progress: progress,
            characterCount: currentCharacter,
            lastModified: Date()
        )
        try? BookStorage.save(bookmark, inside: rootURL, as: FileNames.bookmark)
        flushStats()
        scheduleAutoExport()
    }

    func handleRestoreCompleted() {
        if sasayakiPlayer?.hasAudio != true {
            sasayakiPlayer?.restoreAudio()
        }
        isLoading = false
        pendingFragment = nil
        sasayakiPlayer?.handleRestoreCompleted(currentIndex: index)
    }

    func importSasayakiAudio(from url: URL) throws {
        try sasayakiPlayer?.importAudio(from: url)
    }

    func startTracking() {
        guard enableStatistics else { return }
        isTracking = true
        isPaused = false
        resetTrackingBaseline()
    }

    func stopTracking() {
        guard isTracking else { return }
        flushStats()
        isTracking = false
        isPaused = false
    }

    func toggleStatisticsTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }

    func startTrackingOnPageTurnIfNeeded(userConfig: UserConfig) {
        if userConfig.statisticsAutostartMode == .pageturn && !isTracking {
            startTracking()
        }
    }

    func updateStats() {
        guard enableStatistics else { return }
        let currentDateKey = Self.formattedDate(date: .now)
        if todaysStatistics.dateKey != currentDateKey {
            if let index = stats.firstIndex(where: { $0.dateKey == todaysStatistics.dateKey }) {
                stats[index] = todaysStatistics
            } else {
                stats.append(todaysStatistics)
            }
            todaysStatistics = stats.first(where: { $0.dateKey == currentDateKey }) ?? Self.defaultStatistic(title: title)
        }

        let now = Date.now
        let timeDiff = now.timeIntervalSince(lastTimestamp)
        let charDiff = currentCharacter - lastCount
        let finalCharDiff = charDiff < 0 && abs(charDiff) > sessionStatistics.charactersRead ? -sessionStatistics.charactersRead : charDiff
        let lastStatisticModified = Int(now.timeIntervalSince1970 * 1000)
        guard timeDiff > 0 else { return }

        updateStatistic(to: &sessionStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)
        updateStatistic(to: &todaysStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)
        updateStatistic(to: &allTimeStatistics, timeDiff: timeDiff, characterDiff: finalCharDiff, lastStatisticModified: lastStatisticModified)

        lastTimestamp = now
        lastCount = currentCharacter
    }

    func resetTrackingBaseline() {
        lastTimestamp = .now
        lastCount = currentCharacter
    }

    func flushStats() {
        guard enableStatistics, isTracking, !isPaused else { return }
        updateStats()
        saveStats()
    }

    func nextChapter() -> Bool {
        guard let document, index < document.spine.items.count - 1 else {
            return false
        }
        flushStats()
        sasayakiPlayer?.prepareTransition()
        index += 1
        progress = 0
        pendingFragment = nil
        loadRevision += 1
        saveBookmark(0)
        isLoading = true
        popups.removeAll()
        loadCurrentChapterState()
        return true
    }

    func previousChapter() -> Bool {
        guard index > 0 else {
            return false
        }
        flushStats()
        sasayakiPlayer?.prepareTransition()
        index -= 1
        progress = 1
        pendingFragment = nil
        loadRevision += 1
        saveBookmark(1)
        isLoading = true
        popups.removeAll()
        loadCurrentChapterState()
        return true
    }

    func jumpToCharacter(_ characterCount: Int) {
        guard let result = bookInfo.resolveCharacterPosition(characterCount) else { return }
        flushStats()
        sasayakiPlayer?.prepareTransition()
        index = result.spineIndex
        progress = result.progress
        pendingFragment = nil
        loadRevision += 1
        saveBookmark(result.progress)
        isLoading = true
        popups.removeAll()
        loadCurrentChapterState()
    }

    func jumpToChapter(index: Int, fragment: String? = nil) {
        guard let document,
              document.spine.items.indices.contains(index) else {
            return
        }
        flushStats()
        sasayakiPlayer?.prepareTransition()
        self.index = index
        progress = 0
        pendingFragment = fragment
        loadRevision += 1
        saveBookmark(0)
        isLoading = true
        popups.removeAll()
        loadCurrentChapterState()
    }

    func removeHighlight(_ highlight: Highlight) {
        guard let rootURL else { return }
        highlights.removeAll { $0.id == highlight.id }
        try? BookStorage.save(highlights, inside: rootURL, as: FileNames.highlights)
        highlightRevision += 1
        loadRevision += 1
        isLoading = true
    }

    func handleSelection(
        _ selection: SelectionData,
        userConfig: UserConfig,
        replacingExistingPopups: Bool = false,
        isVertical: Bool? = nil,
        isFullWidth: Bool? = nil
    ) -> Int? {
        if replacingExistingPopups {
            popups.removeAll()
        }

        let lookupResults = LookupEngine.shared.lookup(
            selection.text,
            maxResults: userConfig.maxResults,
            scanLength: userConfig.scanLength
        )
        guard let firstResult = lookupResults.first else {
            return nil
        }

        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        let cue = selection.normalizedOffset.flatMap { offset in
            sasayakiPlayer?.hasAudio == true ? sasayakiPlayer?.findCue(chapterIndex: index, offset: offset) : nil
        }
        let popup = NativeReaderPopup(
            selection: selection,
            lookupResults: lookupResults,
            dictionaryStyles: dictionaryStyles,
            isVertical: isVertical ?? userConfig.verticalWriting,
            isFullWidth: isFullWidth ?? userConfig.popupFullWidth,
            sasayakiCue: cue
        )
        popups.append(popup)

        if !lookupResults.isEmpty, sasayakiPlayer?.isPlaying == true {
            if userConfig.sasayakiAutoPause {
                sasayakiPlayer?.togglePlayback()
                wasPaused = true
            } else {
                wasPaused = false
            }
        }
        return String(firstResult.matched).count
    }

    func closePopup() {
        guard !popups.isEmpty else { return }
        let popupIds = Set(popups.map(\.id))
        withAnimation(.default.speed(2.4)) {
            popups = popups.map {
                var popup = $0
                popup.isVisible = false
                return popup
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
        }
        bridge.send(.clearSelection)
        if wasPaused, sasayakiPlayer?.isPlaying == false {
            sasayakiPlayer?.togglePlayback()
        }
        wasPaused = false
    }

    func closeChildPopups(parent index: Int) {
        let popupIds = Set(popups.dropFirst(index + 1).map(\.id))
        guard !popupIds.isEmpty else { return }
        withAnimation(.default.speed(2.4)) {
            popups = popups.map {
                var popup = $0
                if popupIds.contains(popup.id) {
                    popup.isVisible = false
                }
                return popup
            }
        } completion: {
            self.popups.removeAll { popupIds.contains($0.id) }
        }
    }

    func dismissPopup(id: UUID) {
        guard let index = popups.firstIndex(where: { $0.id == id }),
              popups.indices.contains(index) else {
            return
        }

        if index == 0 {
            closePopup()
        } else if popups.indices.contains(index - 1) {
            popups[index - 1].clearSelection.toggle()
            closeChildPopups(parent: index - 1)
        }
    }

    func setPopupVisibility(id: UUID, isVisible: Bool) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else {
            return
        }
        if isVisible {
            popups[index].isVisible = true
        } else {
            dismissPopup(id: id)
        }
    }

    func jumpToLink(_ url: URL) -> Bool {
        guard let document else { return false }
        let normalizedTarget = Self.urlWithoutFragment(url).standardizedFileURL
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        for (spineIndex, spineItem) in document.spine.items.enumerated() {
            guard let item = document.manifest.items[spineItem.idref] else { continue }
            let spineURL = document.contentDirectory.appendingPathComponent(item.path).standardizedFileURL
            if spineURL == normalizedTarget {
                flushStats()
                sasayakiPlayer?.prepareTransition()
                index = spineIndex
                progress = 0
                pendingFragment = fragment
                loadRevision += 1
                saveBookmark(0)
                isLoading = true
                popups.removeAll()
                loadCurrentChapterState()
                return true
            }
        }
        return false
    }

    private var rootDirectory: URL? {
        guard let booksFolder = try? BookStorage.getBooksDirectory() else {
            return nil
        }
        return booksFolder.appendingPathComponent(book.folder)
    }

    private var epubURL: URL? {
        guard let root = rootDirectory else { return nil }
        if let epub = book.epub ?? BookStorage.loadMetadata(root: root)?.epub {
            let url = root.appendingPathComponent(epub)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }

        let inferred = root.appendingPathComponent(root.lastPathComponent).appendingPathExtension("epub")
        if FileManager.default.fileExists(atPath: inferred.path(percentEncoded: false)) {
            return inferred
        }

        if let candidates = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ),
           let epub = candidates.first(where: { $0.pathExtension.lowercased() == "epub" }) {
            return epub
        }

        let mimetype = root.appendingPathComponent("mimetype")
        if FileManager.default.fileExists(atPath: mimetype.path(percentEncoded: false)) {
            return root
        }

        return nil
    }

    private func reloadBookmark() {
        guard let rootURL else { return }
        if let bookmark = BookStorage.loadBookmark(root: rootURL) {
            index = bookmark.chapterIndex
            progress = bookmark.progress
        }
        loadStatistics()
        if syncAudioBook {
            sasayakiPlayer?.reloadPlayback()
        }
    }

    private func setupSasayakiPlayer(rootURL: URL) {
        sasayakiPlayer = SasayakiPlayer(
            rootURL: rootURL,
            bridge: bridge,
            loadChapter: { [weak self] chapterIndex, progress in
                self?.loadChapterForSasayaki(index: chapterIndex, progress: progress)
            },
            getCurrentIndex: { [weak self] in
                self?.index ?? 0
            },
            onPlayback: { [weak self] in
                guard self?.syncAudioBook == true else { return }
                self?.scheduleAutoExport()
            }
        )
    }

    private func loadChapterForSasayaki(index: Int, progress: Double) {
        guard let document,
              document.spine.items.indices.contains(index) else {
            return
        }
        flushStats()
        sasayakiPlayer?.prepareTransition()
        self.index = index
        self.progress = progress
        pendingFragment = nil
        loadRevision += 1
        saveBookmark(progress)
        isLoading = true
        popups.removeAll()
        resetTrackingBaseline()
        loadCurrentChapterState()
    }

    private func loadCurrentChapterState() {
        guard let url = currentChapterURL else { return }
        bridge.updateState(
            url: url,
            progress: progress,
            sasayakiCues: sasayakiPlayer?.hasMatch == true ? sasayakiPlayer?.cues(for: index) : nil,
            highlights: chapterHighlightsJSON()
        )
    }

    private func scheduleAutoExport() {
        guard autoSyncEnabled else { return }
        pendingAutoExport = true
        guard debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            await MainActor.run {
                self?.debounceTask = nil
            }
            await self?.runAutoExport(direction: .exportToTtu)
        }
    }

    func flushAutoSync() async {
        debounceTask?.cancel()
        debounceTask = nil
        await runAutoExport(direction: .exportToTtu)
    }

    private func runAutoExport(direction: SyncDirection?) async {
        if let exportTask {
            await exportTask.value
        }

        guard pendingAutoExport else { return }
        pendingAutoExport = false

        let task = Task { [weak self] in
            guard let self else { return }
            _ = try? await SyncManager.shared.syncBook(
                book: book,
                direction: direction,
                syncBookData: syncBookData,
                syncStats: syncStats,
                statsSyncMode: statsSyncMode,
                syncAudioBook: syncAudioBook
            )
        }
        exportTask = task
        await task.value
        exportTask = nil
    }

    private func loadStatistics() {
        guard enableStatistics else { return }
        let title = title
        stats = Self.deduplicateStatistics(BookStorage.loadStatistics(root: rootURL ?? rootDirectory ?? URL(filePath: "/")) ?? [])
        sessionStatistics = Self.defaultStatistic(title: title)
        todaysStatistics = stats.first(where: { $0.dateKey == Self.formattedDate(date: .now) }) ?? Self.defaultStatistic(title: title)
        allTimeStatistics = Self.defaultStatistic(title: title)

        for stat in stats {
            allTimeStatistics.readingTime += stat.readingTime
            allTimeStatistics.charactersRead += stat.charactersRead
            allTimeStatistics.lastReadingSpeed = allTimeStatistics.readingTime > 0
                ? Int((Double(allTimeStatistics.charactersRead) / allTimeStatistics.readingTime) * 3600.0)
                : 0
        }
    }

    private func saveStats() {
        guard let rootURL else { return }
        if let index = stats.firstIndex(where: { $0.dateKey == todaysStatistics.dateKey }) {
            stats[index] = todaysStatistics
        } else {
            stats.append(todaysStatistics)
        }
        stats = Self.deduplicateStatistics(stats)
        try? BookStorage.save(stats, inside: rootURL, as: FileNames.statistics)
    }

    private func updateStatistic(
        to statistic: inout Statistics,
        timeDiff: Double,
        characterDiff: Int,
        lastStatisticModified: Int
    ) {
        statistic.readingTime += timeDiff
        statistic.charactersRead = max(statistic.charactersRead + characterDiff, 0)
        statistic.lastReadingSpeed = statistic.readingTime > 0
            ? Int((Double(statistic.charactersRead) / statistic.readingTime) * 3600.0)
            : 0
        statistic.maxReadingSpeed = max(statistic.maxReadingSpeed, statistic.lastReadingSpeed)
        statistic.minReadingSpeed = statistic.minReadingSpeed != 0
            ? min(statistic.minReadingSpeed, statistic.lastReadingSpeed)
            : statistic.lastReadingSpeed
        if characterDiff != 0 {
            statistic.altMinReadingSpeed = statistic.altMinReadingSpeed != 0
                ? min(statistic.altMinReadingSpeed, statistic.lastReadingSpeed)
                : statistic.lastReadingSpeed
        }
        statistic.lastStatisticModified = lastStatisticModified
    }

    private static func defaultStatistic(title: String) -> Statistics {
        Statistics(
            title: title,
            dateKey: formattedDate(date: .now),
            charactersRead: 0,
            readingTime: 0,
            minReadingSpeed: 0,
            altMinReadingSpeed: 0,
            lastReadingSpeed: 0,
            maxReadingSpeed: 0,
            lastStatisticModified: 0
        )
    }

    private static func deduplicateStatistics(_ statistics: [Statistics]) -> [Statistics] {
        var grouped: [String: Statistics] = [:]
        for statistic in statistics {
            if let existing = grouped[statistic.dateKey] {
                if statistic.lastStatisticModified > existing.lastStatisticModified {
                    grouped[statistic.dateKey] = statistic
                }
            } else {
                grouped[statistic.dateKey] = statistic
            }
        }
        return Array(grouped.values)
    }

    private static func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private static func urlWithoutFragment(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }
}

struct NativeReaderPopup: Identifiable {
    let id = UUID()
    let selection: SelectionData
    let lookupResults: [LookupResult]
    let dictionaryStyles: [String: String]
    let isVertical: Bool
    let isFullWidth: Bool
    var sasayakiCue: SasayakiMatch?
    var isVisible = true
    var clearSelection = false
}

struct NativeReaderView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(\.colorScheme) private var systemColorScheme
    @State var model: NativeReaderModel
    var onClose: () -> Void
    @State private var focusMode = false
    @State private var pageNavigation: NativeReaderPageNavigation?
    @State private var activeSheet: NativeReaderSheet?

    private var sepiaInverted: Bool {
        userConfig.theme == .sepia && userConfig.sepiaInvertInDark && systemColorScheme == .dark
    }

    private var readerBackgroundColor: Color {
        if sepiaInverted {
            return Color(red: 0.094, green: 0.082, blue: 0.047)
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return Color(red: 0.949, green: 0.886, blue: 0.788)
        }
        return userConfig.theme == .custom ? userConfig.customBackgroundColor : Color(nsColor: .windowBackgroundColor)
    }

    private var readerTextColor: String? {
        if sepiaInverted {
            return "#F2E2C9"
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return "#332A1B"
        }
        return userConfig.theme == .custom ? nsColorHex(userConfig.customTextColor) : nil
    }

    private var readerTheme: ColorScheme {
        if userConfig.theme == .custom {
            return userConfig.uiTheme.colorScheme ?? systemColorScheme
        }
        if userConfig.theme == .sepia && userConfig.sepiaInvertInDark {
            return systemColorScheme
        }
        return userConfig.theme.colorScheme ?? systemColorScheme
    }

    private var sasayakiTextColor: String {
        readerTheme == .dark ? nsColorHex(userConfig.sasayakiDarkTextColor) : nsColorHex(userConfig.sasayakiTextColor)
    }

    private var sasayakiBackgroundColor: String {
        readerTheme == .dark ? nsColorHex(userConfig.sasayakiDarkBackgroundColor) : nsColorHex(userConfig.sasayakiBackgroundColor)
    }

    private var progressString: String {
        var result: [String] = []
        if userConfig.readerShowCharacters {
            result.append("\(model.currentCharacter) / \(model.bookInfo.characterCount)")
        }
        if userConfig.readerShowPercentage {
            let percent = model.bookInfo.characterCount > 0
                ? (Double(model.currentCharacter) / Double(model.bookInfo.characterCount) * 100)
                : 0
            result.append("\(String(format: "%.2f%%", percent))")
        }
        return result.joined(separator: " ")
    }

    private func navigateBackward() {
        model.startTrackingOnPageTurnIfNeeded(userConfig: userConfig)
        pageNavigation = NativeReaderPageNavigation(direction: .backward)
    }

    private func navigateForward() {
        model.startTrackingOnPageTurnIfNeeded(userConfig: userConfig)
        pageNavigation = NativeReaderPageNavigation(direction: .forward)
    }

    private func toggleFocusMode() {
        withAnimation(.default.speed(2)) {
            focusMode.toggle()
        }
    }

    private func toggleSasayakiPlayback() {
        guard userConfig.enableSasayaki,
              model.sasayakiPlayer?.hasAudio == true else {
            return
        }
        model.wasPaused = false
        model.sasayakiPlayer?.togglePlayback()
    }

    private func playPreviousSasayakiCue() {
        guard userConfig.enableSasayaki,
              model.sasayakiPlayer?.hasAudio == true else {
            return
        }
        model.sasayakiPlayer?.prevCue()
    }

    private func playNextSasayakiCue() {
        guard userConfig.enableSasayaki,
              model.sasayakiPlayer?.hasAudio == true else {
            return
        }
        model.sasayakiPlayer?.nextCue()
    }

    private func replaySasayakiCue() {
        guard userConfig.enableSasayaki,
              model.sasayakiPlayer?.hasAudio == true,
              let cue = model.popup?.sasayakiCue else {
            return
        }

        Task { @MainActor in
            await WordAudioPlayer.shared.stop()
            model.sasayakiPlayer?.playCue(from: cue, stop: true)
        }
    }

    private func jumpToSasayakiCue() {
        guard userConfig.enableSasayaki,
              model.sasayakiPlayer?.hasAudio == true,
              let cue = model.popup?.sasayakiCue else {
            return
        }

        Task { @MainActor in
            await WordAudioPlayer.shared.stop()
            model.sasayakiPlayer?.playCue(from: cue, stop: false)
            model.closePopup()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let readerSize = CGSize(
                width: max(geometry.size.width.rounded(), 1),
                height: max(geometry.size.height.rounded(), 1)
            )
            let readerIdentity = [
                "\(model.index)",
                "\(userConfig.continuousMode)",
                "\(userConfig.verticalWriting)",
                "\(userConfig.fontSize)",
                userConfig.selectedFont,
                "\(model.highlightRevision)",
                "\(model.loadRevision)",
                "\(Int(readerSize.width))",
                "\(Int(readerSize.height))",
            ].joined(separator: "-")

            ZStack {
                if let chapterURL = model.currentChapterURL,
                   let readAccessURL = model.readerReadAccessURL {
                    NativeReaderWebView(
                        chapterURL: chapterURL,
                        readAccessURL: readAccessURL,
                        reloadID: readerIdentity,
                        progress: model.progress,
                        bridge: model.bridge,
                        bridgeCommandCount: model.bridge.pendingCommands.count,
                        userConfig: userConfig,
                        viewSize: readerSize,
                        textColor: readerTextColor,
                        sasayakiTextColor: sasayakiTextColor,
                        sasayakiBackgroundColor: sasayakiBackgroundColor,
                        highlightsJSON: model.chapterHighlightsJSON(),
                        fragment: model.pendingFragment,
                        pageNavigation: pageNavigation,
                        onPageTurn: {
                            model.startTrackingOnPageTurnIfNeeded(userConfig: userConfig)
                        },
                        onNextChapter: model.nextChapter,
                        onPreviousChapter: model.previousChapter,
                        onProgressChanged: model.updateProgress,
                        onSaveBookmark: model.saveBookmark,
                        onInternalLink: model.jumpToLink,
                        onTextSelected: { selection in
                            model.handleSelection(selection, userConfig: userConfig, replacingExistingPopups: true)
                        },
                        onTapOutside: {
                            if model.popup == nil {
                                withAnimation(.default.speed(2)) {
                                    focusMode.toggle()
                                }
                            } else {
                                model.closePopup()
                            }
                        },
                        onRestoreCompleted: {
                            model.handleRestoreCompleted()
                        },
                        onImageTapped: { url in
                            model.imageURL = url
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                ForEach(model.popups) { popup in
                    let popupId = popup.id
                    PopupView(
                        userConfig: userConfig,
                        isVisible: Binding(
                            get: {
                                model.popups.first(where: { $0.id == popupId })?.isVisible ?? false
                            },
                            set: { visible in
                                model.setPopupVisibility(id: popupId, isVisible: visible)
                            }
                        ),
                        selectionData: popup.selection,
                        lookupResults: popup.lookupResults,
                        dictionaryStyles: popup.dictionaryStyles,
                        screenSize: geometry.size,
                        isVertical: popup.isVertical,
                        isFullWidth: popup.isFullWidth,
                        coverURL: nil,
                        documentTitle: model.title,
                        clearSelection: popup.clearSelection,
                        onTextSelected: { selection in
                            if let index = model.popups.firstIndex(where: { $0.id == popupId }) {
                                model.closeChildPopups(parent: index)
                            }
                            return model.handleSelection(
                                selection,
                                userConfig: userConfig,
                                isVertical: false,
                                isFullWidth: false
                            )
                        },
                        onTapOutside: {
                            if let index = model.popups.firstIndex(where: { $0.id == popupId }) {
                                model.closeChildPopups(parent: index)
                            }
                        },
                        onSwipeDismiss: {
                            model.dismissPopup(id: popupId)
                        },
                        onPause: {
                            model.wasPaused = false
                        },
                        sasayakiCue: popup.sasayakiCue,
                        sasayakiPlayer: model.sasayakiPlayer,
                        wasPaused: model.wasPaused
                    )
                    .id(popup.id)
                    .zIndex(Double(100 + (model.popups.firstIndex(where: { $0.id == popupId }) ?? 0)))
                }

                if model.isLoading {
                    ProgressView()
                        .controlSize(.regular)
                }
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(readerBackgroundColor.ignoresSafeArea())
        .overlay(alignment: .top) {
            nativeTopInfoOverlay
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            nativeBottomControls
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            if let url = model.imageURL {
                NativeFullscreenImageView(url: url, backgroundColor: readerBackgroundColor) {
                    model.imageURL = nil
                }
            }
        }
        .background {
            keyboardShortcuts
            NativeReaderSasayakiShortcutMonitor(
                isEnabled: activeSheet == nil,
                userConfig: userConfig,
                onPrevious: playPreviousSasayakiCue,
                onNext: playNextSasayakiCue
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            XboxControllerManager.shared.configure(userConfig: userConfig)
        }
        .task {
            await model.syncOnOpenIfNeeded()
        }
        .task(id: model.isTracking) {
            guard model.isTracking, !model.isPaused else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !model.isPaused {
                    model.updateStats()
                }
            }
        }
        .onDisappear {
            model.flushStats()
            model.sasayakiPlayer?.teardown()
            Task {
                await model.flushAutoSync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: XboxControllerManager.actionNotification)) { notification in
            guard let rawAction = notification.userInfo?["action"] as? String,
                  let action = XboxControllerAction(rawValue: rawAction) else {
                return
            }

            switch action {
            case .previousPage:
                navigateBackward()
            case .nextPage:
                navigateForward()
            case .previousSasayakiCue:
                playPreviousSasayakiCue()
            case .playPauseSasayaki:
                toggleSasayakiPlayback()
            case .nextSasayakiCue:
                playNextSasayakiCue()
            case .replaySasayakiCue:
                replaySasayakiCue()
            case .jumpSasayakiCue:
                jumpToSasayakiCue()
            case .toggleStatistics:
                model.toggleStatisticsTracking()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .appearance:
                NavigationStack {
                    NativeSettingsDetailView(section: .appearance, userConfig: userConfig)
                        .navigationTitle("Appearance")
                        .toolbar {
                            ToolbarItem(placement: .automatic) {
                                NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
                                    activeSheet = nil
                                }
                            }
                        }
                }
                .frame(minWidth: 640, minHeight: 680)
                .preferredColorScheme(readerTheme)
            case .chapters:
                if let document = model.document {
                    ChapterListView(
                        displayTitle: model.book.displayTitle,
                        document: document,
                        bookInfo: model.bookInfo,
                        currentIndex: model.index,
                        currentCharacter: model.currentCharacter,
                        coverURL: model.coverURL,
                        onJumpToChapter: { spineIndex, fragment in
                            model.jumpToChapter(index: spineIndex, fragment: fragment)
                            activeSheet = nil
                        },
                        onJumpToCharacter: { character in
                            model.jumpToCharacter(character)
                            activeSheet = nil
                        }
                    )
                    .frame(minWidth: 560, minHeight: 680)
                }
            case .highlights:
                if let document = model.document {
                    HighlightListView(
                        document: document,
                        bookInfo: model.bookInfo,
                        highlights: model.highlights,
                        onJump: { highlight in
                            model.jumpToCharacter(highlight.character)
                            activeSheet = nil
                        },
                        onDelete: { highlight in
                            model.removeHighlight(highlight)
                        }
                    )
                    .frame(minWidth: 560, minHeight: 620)
                }
            case .statistics:
                ReaderStatisticsContentView(
                    sessionStatistics: model.sessionStatistics,
                    todaysStatistics: model.todaysStatistics,
                    allTimeStatistics: model.allTimeStatistics,
                    bookCharacterCount: model.bookInfo.characterCount,
                    currentCharacter: model.currentCharacter,
                    currentChapterCount: model.currentChapterCount,
                    isTracking: model.isTracking,
                    onStart: model.startTracking,
                    onStop: model.stopTracking,
                    onClose: {
                        activeSheet = nil
                    }
                )
                .frame(minWidth: 520, minHeight: 560)
            case .sasayaki:
                if let player = model.sasayakiPlayer {
                    SasayakiSheet(
                        player: player,
                        onImportAudio: model.importSasayakiAudio,
                        onDismiss: {
                            activeSheet = nil
                        }
                    )
                    .frame(minWidth: 520, minHeight: 620)
                }
            }
        }
        .preferredColorScheme(readerTheme)
    }

    @ViewBuilder
    private var nativeTopInfoOverlay: some View {
        if !focusMode {
            let showTitle = userConfig.readerShowTitle
            let showProgress = userConfig.readerShowProgressTop && !progressString.isEmpty

            if showTitle || showProgress {
                VStack(alignment: .center, spacing: 2) {
                    if showTitle {
                        Text(model.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if showProgress {
                        Text(progressString)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .nativeReaderGlassCapsuleSurface()
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var nativeBottomInfoOverlay: some View {
        if !focusMode && !userConfig.readerShowProgressTop && !progressString.isEmpty {
            Text(progressString)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .nativeReaderGlassCapsuleSurface()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var nativeBottomControls: some View {
        if !focusMode {
            ZStack {
                nativeBottomInfoOverlay

                HStack {
                    NativeGlassCircleButton(systemName: "chevron.left", diameter: 34, fontSize: 18) {
                        onClose()
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if userConfig.enableStatistics && userConfig.readerShowStatisticsToggle {
                            NativeReaderGlassIconButton(systemName: model.isTracking ? "timer" : "chart.xyaxis.line", fontSize: 16) {
                                model.toggleStatisticsTracking()
                            }
                        }

                        if userConfig.enableSasayaki && userConfig.readerShowSasayakiToggle && model.sasayakiPlayer?.hasAudio == true {
                            NativeReaderGlassIconButton(
                                systemName: model.sasayakiPlayer?.isPlaying == true || model.wasPaused ? "pause.fill" : "waveform",
                                fontSize: 16
                            ) {
                                toggleSasayakiPlayback()
                            }
                        }

                        Menu {
                            Button {
                                activeSheet = .appearance
                            } label: {
                                Label("Appearance", systemImage: "paintpalette")
                            }
                            Button {
                                activeSheet = .chapters
                            } label: {
                                Label("Chapters", systemImage: "list.bullet")
                            }
                            Button {
                                activeSheet = .highlights
                            } label: {
                                Label("Highlights", systemImage: "highlighter")
                            }
                            if userConfig.enableStatistics {
                                Button {
                                    activeSheet = .statistics
                                } label: {
                                    Label("Statistics", systemImage: "chart.xyaxis.line")
                                }
                            }
                            if userConfig.enableSasayaki && model.sasayakiPlayer?.hasMatch == true {
                                Button {
                                    activeSheet = .sasayaki
                                } label: {
                                    Label("Sasayaki", systemImage: "waveform")
                                }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 34, height: 34)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .nativeReaderGlassCapsuleControl()
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        VStack {
            Button("Previous Page") {
                navigateBackward()
            }
            .keyboardShortcut(
                userConfig.readerPreviousPageShortcut.keyEquivalent,
                modifiers: userConfig.readerPreviousPageShortcut.eventModifiers
            )

            Button("Next Page") {
                navigateForward()
            }
            .keyboardShortcut(
                userConfig.readerNextPageShortcut.keyEquivalent,
                modifiers: userConfig.readerNextPageShortcut.eventModifiers
            )

            Button("Previous Sasayaki Cue") {
                playPreviousSasayakiCue()
            }
            .keyboardShortcut(
                userConfig.sasayakiPreviousCueShortcut.keyEquivalent,
                modifiers: userConfig.sasayakiPreviousCueShortcut.eventModifiers
            )

            Button("Toggle Sasayaki Playback") {
                toggleSasayakiPlayback()
            }
            .keyboardShortcut(
                userConfig.sasayakiPlayPauseShortcut.keyEquivalent,
                modifiers: userConfig.sasayakiPlayPauseShortcut.eventModifiers
            )

            Button("Next Sasayaki Cue") {
                playNextSasayakiCue()
            }
            .keyboardShortcut(
                userConfig.sasayakiNextCueShortcut.keyEquivalent,
                modifiers: userConfig.sasayakiNextCueShortcut.eventModifiers
            )

            Button("Replay Sasayaki Cue") {
                replaySasayakiCue()
            }
            .keyboardShortcut(
                userConfig.sasayakiReplayCueShortcut.keyEquivalent,
                modifiers: userConfig.sasayakiReplayCueShortcut.eventModifiers
            )

            Button("Jump to Sasayaki Cue") {
                jumpToSasayakiCue()
            }
            .keyboardShortcut(
                userConfig.sasayakiJumpCueShortcut.keyEquivalent,
                modifiers: userConfig.sasayakiJumpCueShortcut.eventModifiers
            )

            Button("Close Reader") {
                onClose()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Close Reader Window") {
                onClose()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Toggle Focus Mode") {
                toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [])
        }
        .labelsHidden()
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .accessibilityHidden(true)
    }
}

private struct NativeReaderSasayakiShortcutMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let userConfig: UserConfig
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> KeyMonitorNSView {
        let view = KeyMonitorNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: KeyMonitorNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.userConfig = userConfig
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.installMonitor()
    }

    static func dismantleNSView(_ nsView: KeyMonitorNSView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class KeyMonitorNSView: NSView {
        var isEnabled = false
        var userConfig: UserConfig?
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  let userConfig else {
                return event
            }
            if userConfig.sasayakiPreviousCueShortcut.matches(event) {
                onPrevious?()
                return nil
            }
            if userConfig.sasayakiNextCueShortcut.matches(event) {
                onNext?()
                return nil
            }
            return event
        }
    }
}

private struct NativeReaderGlassIconButton: View {
    let systemName: String
    var fontSize: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .nativeReaderGlassCircleControl()
    }
}

private extension View {
    @ViewBuilder
    func nativeReaderGlassCircleControl() -> some View {
        self
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.quaternary.opacity(0.58), lineWidth: 0.7)
            }
            .nativeReaderGlassCircle()
    }

    @ViewBuilder
    func nativeReaderGlassCapsuleControl() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary.opacity(0.58), lineWidth: 0.7)
            }
            .nativeReaderGlassCapsule()
    }

    @ViewBuilder
    func nativeReaderGlassCapsuleSurface() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary.opacity(0.58), lineWidth: 0.7)
            }
            .nativeReaderGlassCapsule()
    }

    @ViewBuilder
    func nativeReaderGlassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
    }

    @ViewBuilder
    func nativeReaderGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
        }
    }
}

struct NativeReaderWebView: NSViewRepresentable {
    let chapterURL: URL
    let readAccessURL: URL
    let reloadID: String
    let progress: Double
    let bridge: WebViewBridge
    let bridgeCommandCount: Int
    let userConfig: UserConfig
    let viewSize: CGSize
    let textColor: String?
    let sasayakiTextColor: String
    let sasayakiBackgroundColor: String
    let highlightsJSON: String?
    let fragment: String?
    let pageNavigation: NativeReaderPageNavigation?
    var onPageTurn: () -> Void
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onProgressChanged: (Double) -> Void
    var onSaveBookmark: (Double) -> Void
    var onInternalLink: (URL) -> Bool
    var onTextSelected: (SelectionData) -> Int?
    var onTapOutside: () -> Void
    var onRestoreCompleted: () -> Void
    var onImageTapped: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "restoreCompleted")
        config.userContentController.add(context.coordinator, name: "imageTapped")
        config.userContentController.add(context.coordinator, name: "wheelNavigation")
        config.userContentController.add(context.coordinator, name: "tapOutside")
        config.userContentController.add(context.coordinator, name: "progressChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.reloadID = reloadID
        webView.loadFileURL(chapterURL, allowingReadAccessTo: readAccessURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncTextColor()
        context.coordinator.syncSasayakiColors()
        if !bridge.pendingCommands.isEmpty {
            let commands = bridge.pendingCommands
            bridge.pendingCommands.removeAll()
            commands.forEach { context.coordinator.handleCommand($0) }
        }
        if context.coordinator.reloadID != reloadID {
            context.coordinator.reloadID = reloadID
            context.coordinator.pendingProgress = progress
            webView.loadFileURL(chapterURL, allowingReadAccessTo: readAccessURL)
        }
        if context.coordinator.lastNavigationRequestID != pageNavigation?.id {
            context.coordinator.lastNavigationRequestID = pageNavigation?.id
            if let direction = pageNavigation?.direction {
                context.coordinator.navigate(direction)
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "restoreCompleted")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageTapped")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wheelNavigation")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "progressChanged")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: NativeReaderWebView
        weak var webView: WKWebView?
        var reloadID = ""
        var pendingProgress: Double
        var lastNavigationRequestID: UUID?
        private var shouldSyncProgressAfterRestore = false
        private var hasSyncedTextColor = false
        private var lastTextColor: String?

        init(_ parent: NativeReaderWebView) {
            self.parent = parent
            self.pendingProgress = parent.progress
        }

        static func textColorScript(_ hex: String?) -> String {
            if let hex {
                return "document.documentElement.style.setProperty('--hoshi-text-color', '\(hex)');"
            }
            return "document.documentElement.style.removeProperty('--hoshi-text-color');"
        }

        fileprivate func syncTextColor() {
            guard !hasSyncedTextColor || lastTextColor != parent.textColor else {
                return
            }
            applyTextColor(parent.textColor)
        }

        private func applyTextColor(_ hex: String?) {
            hasSyncedTextColor = true
            lastTextColor = hex
            webView?.evaluateJavaScript(Self.textColorScript(hex)) { _, _ in }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "wheelNavigation":
                guard !parent.userConfig.continuousMode, let direction = message.body as? String else { return }
                navigate(direction == "forward" ? .forward : .backward)
            case "progressChanged":
                guard parent.userConfig.continuousMode else { return }
                let progress: Double?
                if let value = message.body as? Double {
                    progress = value
                } else if let value = message.body as? NSNumber {
                    progress = value.doubleValue
                } else {
                    progress = nil
                }
                guard let progress else { return }
                parent.onProgressChanged(progress)
                parent.onSaveBookmark(progress)
            case "restoreCompleted":
                message.webView?.alphaValue = 1
                if shouldSyncProgressAfterRestore {
                    shouldSyncProgressAfterRestore = false
                    syncProgress()
                }
                parent.onRestoreCompleted()
            case "tapOutside":
                parent.onTapOutside()
            case "imageTapped":
                if let src = message.body as? String, let url = URL(string: src) {
                    parent.onImageTapped(url)
                }
            case "textSelected":
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String,
                      let sentence = body["sentence"] as? String,
                      let rectData = body["rect"] as? [String: Any],
                      let x = rectData["x"] as? CGFloat,
                      let y = rectData["y"] as? CGFloat,
                      let w = rectData["width"] as? CGFloat,
                      let h = rectData["height"] as? CGFloat else {
                    return
                }
                let viewportRect = CGRect(x: x, y: y, width: w, height: h)
                let scrollBoundsOrigin = message.webView?.visibleRect.origin ?? .zero
                let selectionRect = ReaderViewportGeometry.selectionRect(
                    fromViewportRect: viewportRect,
                    scrollBoundsOrigin: scrollBoundsOrigin,
                    subtractVerticalScrollOffset: !parent.userConfig.continuousMode || parent.userConfig.verticalWriting
                )
                let selection = SelectionData(
                    text: text,
                    sentence: sentence,
                    rect: selectionRect,
                    normalizedOffset: body["normalizedOffset"] as? Int
                )
                if let highlightCount = parent.onTextSelected(selection) {
                    highlightSelection(count: highlightCount)
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if parent.onInternalLink(url) {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectReader(into: webView)
        }

        private func injectReader(into webView: WKWebView) {
            let writingMode = parent.userConfig.verticalWriting ? "vertical-rl" : "horizontal-tb"
            let pageWidth = max(Int(parent.viewSize.width.rounded()), 1)
            let pageHeight = max(Int(parent.viewSize.height.rounded()), 1)
            let verticalPadding = Double(parent.userConfig.verticalPadding)
            let horizontalPadding = Double(parent.userConfig.horizontalPadding)
            let bottomOverlap = parent.userConfig.verticalWriting ? parent.userConfig.fontSize : 0
            let readerScriptName = parent.userConfig.continuousMode ? "scrollreader" : "reader"
            let readerScript = Self.bundleString(readerScriptName, extension: "js")
            let selectionScript = Self.bundleString("selection", extension: "js")
            let highlightsScript = Self.bundleString("highlights", extension: "js")
            let textColorCss = Self.textColorScript(parent.textColor)
            let sasayakiColorCss = """
            document.documentElement.style.setProperty('--hoshi-sasayaki-text-color', '\(parent.sasayakiTextColor)');
            document.documentElement.style.setProperty('--hoshi-sasayaki-background-color', '\(parent.sasayakiBackgroundColor)');
            """
            let highlightsSetupScript = parent.highlightsJSON.map { "window.hoshiHighlights.applyHighlights(\($0));" } ?? ""
            let sasayakiSetupScript = parent.bridge.sasayakiCues.map { "window.hoshiReader.applySasayakiCues(\($0));" } ?? ""
            let initialRestoreScript: String = {
                if let fragment = parent.fragment {
                    shouldSyncProgressAfterRestore = true
                    return "window.hoshiReader.jumpToFragment(\(Self.javaScriptStringLiteral(fragment)))"
                }
                shouldSyncProgressAfterRestore = false
                return "window.hoshiReader.restoreProgress(\(pendingProgress))"
            }()

            var fontFaceCss = ""
            if let fontURL = try? FontManager.shared.fontUrl(
                name: parent.userConfig.selectedFont,
                verticalWriting: parent.userConfig.verticalWriting
            ) {
                fontFaceCss = """
                @font-face {
                    font-family: '\(parent.userConfig.selectedFont)';
                    src: url('\(fontURL.absoluteString)');
                }
                """
            }

            let columnWidth = parent.userConfig.verticalWriting
                ? "var(--page-height, 100vh)"
                : "calc(var(--page-width, 100vw) - \(horizontalPadding)vw)"
            let columnGap = parent.userConfig.verticalWriting
                ? "calc(\(verticalPadding)vh + \(bottomOverlap)px)"
                : "\(horizontalPadding)vw"
            let overflowCss = parent.userConfig.continuousMode
                ? (parent.userConfig.verticalWriting ? "overflow-y: hidden !important;" : "overflow-x: hidden !important;")
                : "overflow: hidden !important; width: var(--page-width, 100vw) !important; height: var(--page-height, 100vh) !important; column-width: \(columnWidth) !important; column-gap: \(columnGap) !important;"
            let advancedCss = parent.userConfig.layoutAdvanced ? """
            line-height: \(parent.userConfig.lineHeight) !important;
            letter-spacing: \(parent.userConfig.characterSpacing / 100.0)em !important;
            """ : ""
            let bottomPaddingCss = parent.userConfig.verticalWriting && bottomOverlap > 0
                ? "padding-bottom: calc(\(verticalPadding / 2)vh + \(bottomOverlap)px) !important;"
                : ""
            let globalSizingCss = parent.userConfig.verticalWriting ? "" : """
            * {
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            """
            let horizontalOverflowCss = parent.userConfig.verticalWriting ? "" : """
                column-fill: auto !important;
                -webkit-column-fill: auto !important;
                overflow-wrap: anywhere !important;
                word-break: normal !important;
                orphans: 1;
                widows: 1;
            """
            let breakableTextCss = parent.userConfig.verticalWriting ? "" : """
            p, div, span, li {
                break-inside: auto !important;
                -webkit-column-break-inside: auto !important;
                overflow-wrap: anywhere !important;
                word-break: normal !important;
            }
            pre, code {
                white-space: pre-wrap !important;
                overflow-wrap: anywhere !important;
                word-break: break-word !important;
            }
            table {
                table-layout: fixed !important;
                width: 100% !important;
                overflow-wrap: anywhere !important;
                word-break: break-word !important;
            }
            """
            let pageBreakCss = parent.userConfig.avoidPageBreak ? """
            p {
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
            }
            """ : ""
            let paragraphSpacingCss: String = {
                guard parent.userConfig.layoutAdvanced else { return "" }
                if parent.userConfig.verticalWriting {
                    return """
                    p {
                        margin-right: \(parent.userConfig.paragraphSpacing)em !important;
                        margin-left: \(parent.userConfig.paragraphSpacing)em !important;
                    }
                    """
                }
                return """
                p {
                    margin-top: \(parent.userConfig.paragraphSpacing)em !important;
                    margin-bottom: \(parent.userConfig.paragraphSpacing)em !important;
                }
                """
            }()
            let gridCss = parent.userConfig.justifyText ? "" : """
                text-align: start !important;
                hanging-punctuation: allow-end !important;
                line-break: strict !important;
            """
            let imgWidth = "\(100 - horizontalPadding)vw"
            let imgHeight = parent.userConfig.verticalWriting
                ? "calc(\(100 - verticalPadding)vh - \(Double(bottomOverlap) * (100 - verticalPadding) / 100)px)"
                : "\(100 - verticalPadding)vh"
            let spacerJs: String = {
                if parent.userConfig.verticalWriting {
                    guard verticalPadding > 0 || bottomOverlap > 0 else { return "" }
                    return """
                    var spacer = document.createElement('div');
                    spacer.style.height = 'calc(\(verticalPadding / 2)vh + \(bottomOverlap)px)';
                    spacer.style.width = '100%';
                    spacer.style.display = 'block';
                    spacer.style.breakInside = 'avoid';
                    document.body.appendChild(spacer);
                    """
                }
                guard horizontalPadding > 0 else { return "" }
                return """
                var spacer = document.createElement('div');
                spacer.style.height = '100%';
                spacer.style.width = '\(horizontalPadding / 2)vw';
                spacer.style.display = 'block';
                spacer.style.breakInside = 'avoid';
                document.body.appendChild(spacer);
                """
            }()

            let css = """
            \(fontFaceCss)
            @media (prefers-color-scheme: light) { :root { --hoshi-text-color: #000; } }
            @media (prefers-color-scheme: dark) { :root { --hoshi-text-color: #fff; } }
            \(globalSizingCss)
            html {
                -webkit-line-box-contain: block glyphs replaced;
            }
            html, body {
                margin: 0 !important;
                padding: 0 !important;
                color: var(--hoshi-text-color) !important;
                writing-mode: \(writingMode) !important;
                font-family: '\(parent.userConfig.selectedFont)', serif !important;
                font-size: \(parent.userConfig.fontSize)px !important;
                -webkit-text-size-adjust: none !important;
                box-sizing: border-box !important;
                padding: \(verticalPadding / 2)vh \(horizontalPadding / 2)vw !important;
                \(bottomPaddingCss)
                \(overflowCss)
                \(horizontalOverflowCss)
                \(advancedCss)
                \(gridCss)
            }
            \(breakableTextCss)
            img.block-img, svg {
                max-width: \(imgWidth) !important;
                max-height: \(imgHeight) !important;
                width: auto !important;
                height: auto !important;
                display: block !important;
                margin: auto !important;
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
                object-fit: contain !important;
            }
            .blur-wrapper {
                display: table;
                margin: auto;
                line-height: 0;
                overflow: hidden;
            }
            img.block-img.blurred,
            svg.blurred {
                filter: blur(24px) !important;
                clip-path: inset(0);
            }
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            .hoshi-sasayaki-cue.hoshi-sasayaki-active {
                color: var(--hoshi-sasayaki-text-color) !important;
                background-color: var(--hoshi-sasayaki-background-color) !important;
            }
            ruby > rt, ruby > rp { -webkit-user-select: none; }
            \(HighlightColor.css)
            \(pageBreakCss)
            \(paragraphSpacingCss)
            """

            let script = """
            (function() {
                var viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }
                var newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);
                document.documentElement.style.setProperty('--page-height', '\(pageHeight)px');
                document.documentElement.style.setProperty('--page-width', '\(pageWidth)px');
                var style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);
                \(textColorCss)
                \(sasayakiColorCss)
                window.scanNonJapaneseText = \(parent.userConfig.scanNonJapaneseText);
                \(spacerJs)
                \(selectionScript)
                \(readerScript)
                \(highlightsScript)
                window.hoshiSelection.registerModifierTracking();
                window.hoshiReader.pageHeight = \(pageHeight);
                window.hoshiReader.pageWidth = \(pageWidth);
                window.hoshiReader.registerCopyText?.();
                window.hoshiReader.registerWheelNavigation?.(\(!parent.userConfig.continuousMode && parent.userConfig.readerWheelPageTurnEnabled ? "true" : "false"));
                if (\(parent.userConfig.continuousMode ? "true" : "false") && !window.hoshiNativeProgressRegistered) {
                    window.hoshiNativeProgressRegistered = true;
                    var hoshiNativeProgressFrame = null;
                    var hoshiNativeLastProgressPost = 0;
                    const postNativeProgress = () => {
                        hoshiNativeProgressFrame = null;
                        const now = Date.now();
                        if (now - hoshiNativeLastProgressPost < 250) { return; }
                        hoshiNativeLastProgressPost = now;
                        const progress = window.hoshiReader.calculateProgress?.();
                        if (typeof progress === 'number' && Number.isFinite(progress)) {
                            window.webkit?.messageHandlers?.progressChanged?.postMessage(progress);
                        }
                    };
                    window.addEventListener('scroll', () => {
                        if (hoshiNativeProgressFrame === null) {
                            hoshiNativeProgressFrame = requestAnimationFrame(postNativeProgress);
                        }
                    }, { passive: true });
                }
                if (\(parent.userConfig.readerHideFurigana ? "true" : "false")) {
                    document.querySelectorAll('rt').forEach(rt => rt.remove());
                }

                // Wrap text directly under ruby nodes so selection/highlight ranges stay stable.
                document.querySelectorAll('ruby').forEach(ruby => {
                    ruby.childNodes.forEach(node => {
                        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                            const span = document.createElement('span');
                            span.textContent = node.textContent;
                            node.replaceWith(span);
                        }
                    });
                });

                function setupImage(element, src, wrap, blurElement = element) {
                    var target = element;
                    if (\(parent.userConfig.blurImages ? "true" : "false")) {
                        blurElement.classList.add('blurred');
                        if (wrap) {
                            target = document.createElement('div');
                            target.className = 'blur-wrapper';
                            blurElement.before(target);
                            target.append(blurElement);
                        }
                    }
                    target.onclick = event => {
                        event.preventDefault();
                        event.stopPropagation();
                        if (blurElement.classList.contains('blurred')) {
                            blurElement.classList.remove('blurred');
                            return;
                        }
                        webkit.messageHandlers.imageTapped.postMessage(new URL(src, document.baseURI).href);
                    };
                }

                document.querySelectorAll('svg[preserveAspectRatio="none"]').forEach(svg => svg.removeAttribute('preserveAspectRatio'));
                document.querySelectorAll('svg').forEach(svg => {
                    var svgImage = svg.querySelector('image');
                    if (!svgImage) {
                        return;
                    }
                    setupImage(svgImage, svgImage.href.baseVal, false, svg);
                });
                var imagePromises = Array.from(document.querySelectorAll('img')).map(img => {
                    return new Promise(resolve => {
                        function processImg() {
                            const isGaiji = img.classList.contains('gaiji') || img.classList.contains('gaiji-line');
                            if (!isGaiji && (img.naturalWidth > 256 || img.naturalHeight > 256)) {
                                img.classList.add('block-img');
                                setupImage(img, img.src, true);
                            }
                            resolve();
                        }
                        if (img.complete && img.naturalWidth > 0) {
                            processImg();
                        } else {
                            img.onload = processImg;
                            img.onerror = () => resolve();
                        }
                    });
                });
                document.addEventListener('click', event => {
                    if (event.target?.closest?.('a, button, input, textarea, select, [contenteditable="true"]')) { return; }
                    const selected = window.hoshiSelection.selectText(event.clientX, event.clientY, 16);
                    if (!selected) { webkit.messageHandlers.tapOutside.postMessage(null); }
                }, true);
                let restoreFallback = setTimeout(() => {
                    window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
                }, 2500);
                Promise.all(imagePromises)
                    .then(() => new Promise(resolve => setTimeout(resolve, 50)))
                    .then(() => {
                        window.hoshiReader.buildNodeOffsets?.();
                        \(sasayakiSetupScript)
                        \(highlightsSetupScript)
                        return \(initialRestoreScript);
                    })
                    .catch(error => {
                        console.error('Native reader restore failed', error);
                        window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
                    })
                    .finally(() => clearTimeout(restoreFallback));
            })();
            """

            webView.alphaValue = 0
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    print("NativeReaderWebView injection error: \(error.localizedDescription)")
                    webView.alphaValue = 1
                    self.parent.onRestoreCompleted()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak webView] in
                guard let self, let webView, webView.alphaValue == 0 else { return }
                print("NativeReaderWebView restore fallback")
                webView.alphaValue = 1
                self.parent.onRestoreCompleted()
            }
        }

        fileprivate func navigate(_ direction: NativeReaderNavigationDirection) {
            guard let webView else { return }
            parent.onPageTurn()
            let jsDirection = direction == .forward ? "forward" : "backward"
            let script = parent.userConfig.continuousMode
                ? Self.continuousNavigationScript(direction: direction, currentProgress: parent.progress)
                : "window.hoshiReader.paginate('\(jsDirection)')"
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                if let outcome = result as? String, outcome == "limit" {
                    if direction == .forward {
                        _ = self.parent.onNextChapter()
                    } else {
                        _ = self.parent.onPreviousChapter()
                    }
                    return
                }
                if self.parent.userConfig.continuousMode {
                    if let progress = result as? Double {
                        self.parent.onProgressChanged(progress)
                        self.parent.onSaveBookmark(progress)
                    } else if let progress = result as? NSNumber {
                        let value = progress.doubleValue
                        self.parent.onProgressChanged(value)
                        self.parent.onSaveBookmark(value)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.syncProgress()
                        }
                    }
                    return
                }
                self.syncProgress()
            }
        }

        fileprivate func handleCommand(_ command: WebViewCommand) {
            guard let webView else { return }
            switch command {
            case .loadChapter,
                 .navigate,
                 .stepContinuous:
                break
            case .restoreProgress(let progress):
                webView.evaluateJavaScript("window.hoshiReader.restoreProgress(\(progress))") { [weak self] _, _ in
                    self?.syncProgress()
                }
            case .jumpToFragment(let fragment):
                let literal = Self.javaScriptStringLiteral(fragment)
                webView.evaluateJavaScript("window.hoshiReader.jumpToFragment(\(literal))") { [weak self] _, _ in
                    self?.syncProgress()
                }
            case .clearSelection:
                clearSelection()
            case .updateTextColor(let hex):
                applyTextColor(hex)
            case .updateSasayakiColors(let textHex, let backgroundHex):
                webView.evaluateJavaScript("""
                    document.documentElement.style.setProperty('--hoshi-sasayaki-text-color', '\(textHex)');
                    document.documentElement.style.setProperty('--hoshi-sasayaki-background-color', '\(backgroundHex)');
                """) { _, _ in }
            case .applySasayakiCues(let cues, let completion):
                webView.evaluateJavaScript("window.hoshiReader.applySasayakiCues(\(cues))") { _, _ in completion?() }
            case .highlightSasayakiCue(let id, let reveal):
                let cue = Self.javaScriptStringLiteral(id)
                let revealFlag = reveal ? "true" : "false"
                webView.evaluateJavaScript("window.hoshiReader.highlightSasayakiCue(\(cue), \(revealFlag))") { [weak self] result, _ in
                    guard let self else { return }
                    if let progress = result as? Double {
                        self.parent.onProgressChanged(progress)
                        self.parent.onSaveBookmark(progress)
                    } else if let progress = result as? NSNumber {
                        let value = progress.doubleValue
                        self.parent.onProgressChanged(value)
                        self.parent.onSaveBookmark(value)
                    }
                }
            case .clearSasayakiCue:
                webView.evaluateJavaScript("window.hoshiReader.clearSasayakiCue()") { _, _ in }
            case .removeHighlight(let id):
                let literal = Self.javaScriptStringLiteral(id)
                webView.evaluateJavaScript("window.hoshiHighlights.removeHighlight(\(literal))") { _, _ in }
            }
        }

        fileprivate func syncSasayakiColors() {
            webView?.evaluateJavaScript("""
                document.documentElement.style.setProperty('--hoshi-sasayaki-text-color', '\(parent.sasayakiTextColor)');
                document.documentElement.style.setProperty('--hoshi-sasayaki-background-color', '\(parent.sasayakiBackgroundColor)');
            """) { _, _ in }
        }

        private func clearSelection() {
            webView?.evaluateJavaScript("window.hoshiSelection?.clearSelection?.()") { _, _ in }
        }

        private static func continuousNavigationScript(
            direction: NativeReaderNavigationDirection,
            currentProgress: Double
        ) -> String {
            let jsDirection = direction == .forward ? "forward" : "backward"
            let current = min(max(currentProgress, 0), 1)
            return """
            (function() {
                const direction = '\(jsDirection)';
                const vertical = window.hoshiReader?.isVertical?.() === true;
                const current = \(current);
                const total = vertical
                    ? Math.max(document.documentElement.scrollWidth, document.body.scrollWidth, window.innerWidth)
                    : Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, window.innerHeight);
                const view = vertical ? window.innerWidth : window.innerHeight;
                const step = Math.min(Math.max((view / total) * 0.92, 0.06), 0.25);
                const next = direction === 'forward' ? current + step : current - step;
                if ((direction === 'forward' && current >= 0.995) || (direction === 'backward' && current <= 0.005)) {
                    return 'limit';
                }
                const target = Math.min(Math.max(next, 0), 1);
                window.hoshiReader?.restoreProgress?.(target);
                return target;
            })()
            """
        }

        private func syncProgress() {
            webView?.evaluateJavaScript("window.hoshiReader.calculateProgress()") { [weak self] result, _ in
                guard let self, let progress = result as? Double else { return }
                self.parent.onProgressChanged(progress)
                self.parent.onSaveBookmark(progress)
            }
        }

        private func highlightSelection(count: Int) {
            webView?.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(count))") { _, _ in }
        }

        private static func bundleString(_ name: String, extension ext: String) -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return content
        }

        private static func javaScriptStringLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8) else {
                return "''"
            }
            return encoded
        }
    }
}

private struct NativeFullscreenImageView: View {
    let url: URL
    let backgroundColor: Color
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundColor.ignoresSafeArea()
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .padding(24)
        }
    }
}

private func nsColorHex(_ color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .labelColor
    return ColorHexCodec.hexString(
        red: nsColor.redComponent,
        green: nsColor.greenComponent,
        blue: nsColor.blueComponent,
        alpha: nsColor.alphaComponent
    )
}
