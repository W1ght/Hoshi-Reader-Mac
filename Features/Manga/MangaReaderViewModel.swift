import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MangaReaderViewModel {
    private struct PendingProgress {
        let chapter: MangaReadingChapter
        let pageIndex: Int
        let pageCount: Int
        let completed: Bool
    }

    let session: MangaReadingSession
    let pageProvider: any MangaPageContentProvider
    let popupPresentation = PopupPresentationCoordinator()

    var layout: MangaReaderLayout {
        didSet {
            guard layout != oldValue else { return }
            MangaReaderPreferences.save(layout: layout, in: preferences)
            popupPresentation.closeAll()
        }
    }
    var direction: MangaReadingDirection {
        didSet {
            guard direction != oldValue else { return }
            MangaReaderPreferences.save(direction: direction, in: preferences)
            popupPresentation.closeAll()
            rebuildPresentationPagesIfPossible()
        }
    }
    var splitsWidePages = false {
        didSet {
            guard splitsWidePages != oldValue else { return }
            MangaPageProcessingPreferences.save(
                splitsWidePages: splitsWidePages,
                in: preferences
            )
            pageProcessingPreferenceDidChange()
        }
    }
    var cropsWhiteBorders = false {
        didSet {
            guard cropsWhiteBorders != oldValue else { return }
            MangaPageProcessingPreferences.save(
                cropsWhiteBorders: cropsWhiteBorders,
                in: preferences
            )
            pageProcessingPreferenceDidChange()
        }
    }
    var zoomPercentage: Int {
        didSet {
            let clamped = MangaReaderPreferences.clampedZoomPercentage(
                zoomPercentage
            )
            guard clamped == zoomPercentage else {
                zoomPercentage = clamped
                return
            }
            guard zoomPercentage != oldValue else { return }
            MangaReaderPreferences.save(
                zoomPercentage: zoomPercentage,
                in: preferences
            )
            popupPresentation.closeAll()
        }
    }
    var currentPageIndex: Int
    private(set) var currentChapterIndex: Int
    private(set) var pageReferences: [MangaPageReference]
    private(set) var presentationPages: [MangaPresentationPage] = []
    private(set) var isPreparingPages = false
    private(set) var isLoadingChapter = false
    private(set) var isContentAvailable = true
    var errorMessage: String?
    var isOCREnabled = false
    var isRecognizingText = false
    var ocrRegionsByPage: [Int: [MangaOCRTextRegion]] = [:]
    var mokuroRegionsByPage: [Int: [MangaOCRTextRegion]] = [:]
    var ocrStatusMessage: String?
    var ocrCompletedPageCount = 0
    var ocrTotalPageCount = 0
    var ocrScanCancellationID = 0
    private(set) var lookupPageIndex: Int?

    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var activeOCRScanID: UUID?
    @ObservationIgnored private var ocrContentGeneration = UUID()
    @ObservationIgnored private var isOCRScanPaused = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var cachedPageAnalyses: [MangaPageAnalysis]?
    @ObservationIgnored private var activeChapterLoadID: UUID?
    @ObservationIgnored private var pendingProgressByChapter:
        [String: PendingProgress] = [:]
    @ObservationIgnored private var pendingProgressOrder: [String] = []
    @ObservationIgnored private var completedProgressChapterIDs:
        Set<String> = []
    @ObservationIgnored private var progressWriteTask: Task<Void, Never>?

    init(
        session: MangaReadingSession,
        pageProvider: any MangaPageContentProvider,
        preferences: UserDefaults = .standard
    ) {
        self.session = session
        self.pageProvider = pageProvider
        self.preferences = preferences
        let initialLayout = preferences.object(forKey: MangaReaderPreferences.layoutKey) == nil
            ? session.suggestedLayout ?? MangaReaderPreferences.layout(in: preferences)
            : MangaReaderPreferences.layout(in: preferences)
        layout = initialLayout
        direction = preferences.object(forKey: MangaReaderPreferences.directionKey) == nil
            ? session.suggestedDirection ?? MangaReaderPreferences.direction(in: preferences)
            : MangaReaderPreferences.direction(in: preferences)
        splitsWidePages = MangaPageProcessingPreferences.splitsWidePages(
            in: preferences
        )
        cropsWhiteBorders = MangaPageProcessingPreferences.cropsWhiteBorders(
            in: preferences
        )
        zoomPercentage = MangaReaderPreferences.zoomPercentage(in: preferences)
        isOCREnabled = MangaReaderPreferences.isOCREnabled(in: preferences)
        currentChapterIndex = min(
            max(0, session.initialChapterIndex),
            max(0, session.chapters.count - 1)
        )
        pageReferences = session.initialPages
        currentPageIndex = min(
            max(0, session.initialPageIndex),
            max(0, session.initialPages.count - 1)
        )
        let sourcePaths = session.initialPages.map(\.displayPath)
        presentationPages = MangaPagePresentationResolver.unprocessedPages(
            sourcePaths: sourcePaths
        )
        isPreparingPages = pageProcessingOptions.requiresAnalysis
    }

    convenience init(
        item: MangaLibraryItem,
        source: MangaLibrarySource,
        profileID: String = ProfileRepository.shared.activeProfile.id,
        preferences: UserDefaults = .standard
    ) {
        do {
            let local = try MangaReadingSession.local(
                item: item,
                source: source,
                profileID: profileID
            )
            self.init(
                session: local.session,
                pageProvider: local.provider,
                preferences: preferences
            )
        } catch {
            let chapter = MangaReadingChapter(
                id: item.id,
                title: item.displayTitle
            )
            let fallback = MangaReadingSession(
                profileID: profileID,
                documentID: item.id,
                title: item.title,
                chapters: [chapter],
                initialChapterIndex: 0,
                initialPageIndex: item.currentPageIndex,
                initialPages: [],
                modifiedAt: item.modifiedAt,
                allowsCoverUpdates: false,
                suggestedLayout: nil,
                suggestedDirection: nil,
                progressWriter: { _, _, _, _ in },
                coverWriter: { _ in throw MangaPageLoaderError.pageUnavailable }
            )
            self.init(
                session: fallback,
                pageProvider: UnavailableMangaPageContentProvider(),
                preferences: preferences
            )
            errorMessage = error.localizedDescription
            isContentAvailable = false
        }
    }

    var title: String { session.title }
    var profileID: String { session.profileID }
    var allowsCoverUpdates: Bool { session.allowsCoverUpdates }
    var chapters: [MangaReadingChapter] { session.chapters }
    var currentChapter: MangaReadingChapter? {
        chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex]
            : nil
    }

    var pageCount: Int {
        presentationPages.count
    }

    var sourcePageCount: Int {
        pageReferences.count
    }

    var zoomScale: Double {
        Double(zoomPercentage) / 100
    }

    var displayedPageIndices: [Int] {
        switch layout {
        case .singlePage, .continuous:
            [currentPageIndex]
        case .doublePage:
            MangaPagePairResolver.indices(
                startingAt: currentPageIndex,
                pageCount: pageCount,
                direction: direction
            )
        }
    }

    var displayedPages: [MangaPresentationPage] {
        displayedPageIndices.compactMap {
            presentationPages.indices.contains($0)
                ? presentationPages[$0]
                : nil
        }
    }

    var pageLabel: String {
        guard pageCount > 0 else { return "0 / 0" }
        if layout == .doublePage, displayedPageIndices.count > 1 {
            let ordered = displayedPageIndices.sorted()
            return "\(ordered[0] + 1)–\(ordered[1] + 1) / \(pageCount)"
        }
        return "\(currentPageIndex + 1) / \(pageCount)"
    }

    var canGoBackward: Bool {
        currentPageIndex > 0
    }

    var canGoForward: Bool {
        currentPageIndex < pageCount - 1
    }

    var visibleOCRRequestID: String {
        let sourceIndices = displayedPages.map(\.sourcePageIndex)
        return "\(currentChapterIndex)|\(isOCREnabled)|\(sourceIndices.map(String.init).joined(separator: ","))"
    }

    var fullOCRRequestID: String {
        "\(currentChapterIndex)|\(isOCREnabled)|\(layout == .continuous)|\(ocrScanCancellationID)"
    }

    var pageProcessingOptions: MangaPageProcessingOptions {
        MangaPageProcessingOptions(
            splitsWidePages: splitsWidePages,
            readingDirection: direction,
            cropsWhiteBorders: cropsWhiteBorders
        )
    }

    var pageProcessingRequestID: String {
        [
            splitsWidePages.description,
            direction.rawValue,
            cropsWhiteBorders.description,
            String(currentChapterIndex),
        ].joined(separator: "|")
    }

    var ocrProgress: Double {
        guard ocrTotalPageCount > 0 else { return 0 }
        return Double(ocrCompletedPageCount) / Double(ocrTotalPageCount)
    }

    var isOCRRecognitionPaused: Bool {
        isOCRScanPaused
    }

    var visibleOCRRegions: [Int: [MangaOCRTextRegion]] {
        Dictionary(
            uniqueKeysWithValues: displayedPages.map { page in
                (
                    page.index,
                    MangaPageProcessor.regions(
                        rawLookupRegions(at: page.sourcePageIndex),
                        for: page
                    )
                )
            }
        )
    }

    func lookupRegions(for page: MangaPresentationPage) -> [MangaOCRTextRegion] {
        MangaPageProcessor.regions(
            rawLookupRegions(at: page.sourcePageIndex),
            for: page
        )
    }

    func lookupRequestID(for page: MangaPresentationPage) -> String {
        "\(page.sourcePageIndex)|\(page.index)|\(isOCREnabled)|\(pageProcessingRequestID)"
    }

    var allVisiblePagesUseMokuro: Bool {
        displayedPages.allSatisfy {
            mokuroRegionsByPage[$0.sourcePageIndex] != nil
        }
    }

    func preparePageProcessing() async {
        guard pageProcessingOptions.requiresAnalysis else {
            isPreparingPages = false
            rebuildPresentationPages(using: nil)
            return
        }
        if let cachedPageAnalyses {
            isPreparingPages = false
            rebuildPresentationPages(using: cachedPageAnalyses)
            return
        }
        guard !pageReferences.isEmpty else { return }

        isPreparingPages = true
        let provider = pageProvider
        let references = pageReferences
        let analysisTask = Task(priority: .userInitiated) {
            var analyses: [MangaPageAnalysis] = []
            analyses.reserveCapacity(references.count)
            for page in references {
                try Task.checkCancellation()
                let payload = try await provider.payload(for: page)
                guard let imageData = payload.imageData else {
                    analyses.append(MangaPageAnalysis(
                        pixelWidth: 1200,
                        pixelHeight: 1800,
                        whiteBorderContentRect: CGRect(
                            x: 0,
                            y: 0,
                            width: 1,
                            height: 1
                        )
                    ))
                    continue
                }
                analyses.append(
                    try MangaPageProcessor.analyze(
                        imageData
                    )
                )
            }
            return analyses
        }
        do {
            let analyses = try await withTaskCancellationHandler {
                try await analysisTask.value
            } onCancel: {
                analysisTask.cancel()
            }
            try Task.checkCancellation()
            cachedPageAnalyses = analyses
            isPreparingPages = false
            rebuildPresentationPages(using: analyses)
        } catch is CancellationError {
            return
        } catch {
            isPreparingPages = false
            showOCRStatus(error.localizedDescription)
        }
    }

    func goBackward() {
        move(by: layout == .doublePage ? -2 : -1)
    }

    func goForward() {
        move(by: layout == .doublePage ? 2 : 1)
    }

    func handleLeftArrow() {
        if direction == .rightToLeft {
            goForward()
        } else {
            goBackward()
        }
    }

    func handleRightArrow() {
        if direction == .rightToLeft {
            goBackward()
        } else {
            goForward()
        }
    }

    @discardableResult
    func handleEscape() -> Bool {
        guard !popupPresentation.popups.isEmpty else { return false }
        popupPresentation.closeAll()
        return true
    }

    func go(to pageIndex: Int) {
        guard pageCount > 0 else { return }
        let clamped = min(max(0, pageIndex), pageCount - 1)
        guard clamped != currentPageIndex else { return }
        popupPresentation.closeAll()
        currentPageIndex = clamped
        persistProgress()
    }

    func openChapter(at index: Int, pageIndex: Int = 0) async {
        guard chapters.indices.contains(index),
              index != currentChapterIndex || pageReferences.isEmpty else {
            return
        }
        invalidateOCRForChapterChange()
        persistProgress()
        popupPresentation.closeAll()
        isLoadingChapter = true
        isPreparingPages = false
        errorMessage = nil
        let loadID = UUID()
        activeChapterLoadID = loadID
        await pageProvider.cancelPendingRequests()
        let chapter = chapters[index]
        do {
            let pages = try await pageProvider.pages(for: chapter)
            try Task.checkCancellation()
            guard activeChapterLoadID == loadID else { return }
            currentChapterIndex = index
            pageReferences = pages
            cachedPageAnalyses = nil
            currentPageIndex = min(
                max(0, pageIndex),
                max(0, pages.count - 1)
            )
            presentationPages =
                MangaPagePresentationResolver.unprocessedPages(
                    sourcePaths: pages.map(\.displayPath)
                )
            isContentAvailable = !pages.isEmpty
            isLoadingChapter = false
            activeChapterLoadID = nil
            isPreparingPages = pageProcessingOptions.requiresAnalysis
            if isPreparingPages {
                await preparePageProcessing()
            }
        } catch is CancellationError {
            guard activeChapterLoadID == loadID else { return }
            isLoadingChapter = false
            activeChapterLoadID = nil
        } catch {
            guard activeChapterLoadID == loadID else { return }
            isLoadingChapter = false
            activeChapterLoadID = nil
            errorMessage = error.localizedDescription
        }
    }

    func goToPreviousChapter() async {
        guard currentChapterIndex > 0 else { return }
        await openChapter(at: currentChapterIndex - 1)
    }

    func goToNextChapter() async {
        guard currentChapterIndex + 1 < chapters.count else { return }
        await openChapter(at: currentChapterIndex + 1)
    }

    func toggleOCR() {
        isOCREnabled.toggle()
        isOCRScanPaused = false
        ocrScanCancellationID += 1
        MangaReaderPreferences.save(
            isOCREnabled: isOCREnabled,
            in: preferences
        )
        popupPresentation.closeAll()
        if !isOCREnabled {
            isRecognizingText = false
            activeOCRScanID = nil
        }
    }

    func cancelOCRRecognition() {
        guard isRecognizingText else { return }
        isOCRScanPaused = true
        activeOCRScanID = nil
        isRecognizingText = false
        ocrScanCancellationID += 1
        showOCRStatus(
            String(localized: "Text recognition paused. Completed pages remain available.")
        )
    }

    func resumeOCRRecognition() {
        guard isOCREnabled, isOCRScanPaused else { return }
        isOCRScanPaused = false
        ocrScanCancellationID += 1
    }

    func loadVisibleOCRRegions() async {
        guard !isLoadingChapter else { return }
        await loadOCRRegions(
            for: Array(Set(displayedPages.map(\.sourcePageIndex))).sorted()
        )
    }

    func loadOCRRegions(for requestedIndices: [Int]) async {
        guard !isLoadingChapter else { return }
        let contentGeneration = ocrContentGeneration
        let requestedIndices = requestedIndices.filter {
            $0 >= 0 && $0 < sourcePageCount
        }
        guard !requestedIndices.isEmpty else { return }

        do {
            for pageIndex in requestedIndices where mokuroRegionsByPage[pageIndex] == nil {
                try Task.checkCancellation()
                guard pageReferences.indices.contains(pageIndex) else {
                    throw MangaPageLoaderError.pageUnavailable
                }
                let payload = try await pageProvider.payload(
                    for: pageReferences[pageIndex]
                )
                let regions = payload.embeddedTextRegions
                try Task.checkCancellation()
                guard ocrContentGeneration == contentGeneration else {
                    return
                }
                if let regions {
                    mokuroRegionsByPage[pageIndex] = regions
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard ocrContentGeneration == contentGeneration else {
                return
            }
            showOCRStatus(error.localizedDescription)
            return
        }

        guard isOCREnabled else { return }
        let pagePaths = ocrPageIdentities
        for pageIndex in requestedIndices
        where mokuroRegionsByPage[pageIndex] == nil
            && ocrRegionsByPage[pageIndex] == nil {
            try? Task.checkCancellation()
            guard !Task.isCancelled,
                  let key = ocrCacheKey(
                      pageIndex: pageIndex,
                      pagePaths: pagePaths
                  ) else {
                return
            }
            if let regions = await MangaOCRService.shared.cachedRegions(
                for: key,
                pagePaths: pagePaths
            ) {
                guard isOCREnabled,
                      ocrContentGeneration == contentGeneration else {
                    return
                }
                ocrRegionsByPage[pageIndex] = regions
            }
        }
    }

    func recognizeAllPages() async {
        guard isOCREnabled,
              !isOCRScanPaused,
              !isLoadingChapter,
              sourcePageCount > 0,
              let currentChapter else {
            return
        }
        let contentGeneration = ocrContentGeneration

        do {
            let usesMokuro = try await pageProvider.hasEmbeddedText(
                for: currentChapter
            )
            guard ocrContentGeneration == contentGeneration else {
                return
            }
            if usesMokuro {
                await loadVisibleOCRRegions()
                return
            }
        } catch is CancellationError {
            return
        } catch {
            guard ocrContentGeneration == contentGeneration else {
                return
            }
            showOCRStatus(error.localizedDescription)
            return
        }

        let scanID = UUID()
        activeOCRScanID = scanID
        isRecognizingText = true
        ocrCompletedPageCount = 0
        ocrTotalPageCount = sourcePageCount
        defer {
            if activeOCRScanID == scanID {
                activeOCRScanID = nil
                isRecognizingText = false
            }
        }

        let sourcePageIndex = currentSourcePageIndex
        let pageOrder = Array(sourcePageIndex..<sourcePageCount)
            + Array(0..<sourcePageIndex)
        var requestedNetworkPage = false
        var hasFailedPages = false
        let pagePaths = ocrPageIdentities

        for pageIndex in pageOrder {
            do {
                try Task.checkCancellation()
                guard isOCREnabled,
                      activeOCRScanID == scanID,
                      ocrContentGeneration == contentGeneration,
                      let key = ocrCacheKey(
                          pageIndex: pageIndex,
                          pagePaths: pagePaths
                      ) else {
                    throw CancellationError()
                }

                if let regions = await MangaOCRService.shared.cachedRegions(
                    for: key,
                    pagePaths: pagePaths
                ) {
                    guard isOCREnabled,
                          activeOCRScanID == scanID,
                          ocrContentGeneration == contentGeneration else {
                        throw CancellationError()
                    }
                    ocrRegionsByPage[pageIndex] = regions
                    ocrCompletedPageCount += 1
                    continue
                }

                let payload = try await payloadForOCR(at: pageIndex)
                guard let imageData = payload.imageData else {
                    throw MangaPageLoaderError.pageUnavailable
                }
                try Task.checkCancellation()
                guard isOCREnabled,
                      activeOCRScanID == scanID,
                      ocrContentGeneration == contentGeneration else {
                    throw CancellationError()
                }
                requestedNetworkPage = true
                let regions = try await MangaOCRService.shared.recognizeText(
                    in: imageData,
                    key: key,
                    pagePaths: pagePaths
                )
                try Task.checkCancellation()
                guard isOCREnabled,
                      activeOCRScanID == scanID,
                      ocrContentGeneration == contentGeneration else {
                    throw CancellationError()
                }
                ocrRegionsByPage[pageIndex] = regions
                ocrCompletedPageCount += 1
            } catch is CancellationError {
                return
            } catch {
                guard activeOCRScanID == scanID,
                      ocrContentGeneration == contentGeneration else {
                    return
                }
                hasFailedPages = true
                ocrCompletedPageCount += 1
            }
        }
        if hasFailedPages {
            showOCRStatus(
                String(
                    localized:
                        "Text recognition finished with some pages pending. They will be retried next time."
                )
            )
        } else if requestedNetworkPage {
            showOCRStatus(String(localized: "Text recognition complete."))
        }
    }

    func presentOCRLookup(
        region: MangaOCRTextRegion,
        anchorRect: CGRect,
        userConfig: UserConfig
    ) -> Int? {
        let profile = ProfileRepository.shared.activeProfile
        guard let candidate = TextSelectionResolver.lookupCandidate(
            in: region.sentence,
            utf16Offset: region.utf16Offset,
            scanLength: userConfig.scanLength,
            contentLanguage: profile.language
        ) else {
            return nil
        }
        let selection = SelectionData(
            text: candidate.text,
            sentence: region.sentence,
            rect: anchorRect,
            normalizedOffset: candidate.utf16Start,
            miningContext: .text(
                region.sentence,
                targetUTF16Location: candidate.utf16Start
            )
        )
        let matchedLength = popupPresentation.present(
            selection: selection,
            userConfig: userConfig,
            replacingExisting: true,
            isVertical: region.isVertical
        )
        if matchedLength != nil {
            lookupPageIndex = region.pageIndex
        }
        if matchedLength == nil {
            showOCRStatus(String(localized: "No dictionary result found."))
        }
        return matchedLength
    }

    func presentNestedLookup(
        selection: SelectionData,
        userConfig: UserConfig
    ) -> Int? {
        popupPresentation.present(
            selection: selection,
            userConfig: userConfig
        )
    }

    func dismissPopup(id: UUID) {
        popupPresentation.dismiss(id: id)
    }

    func closeOCRLookup() {
        popupPresentation.closeAll()
    }

    func showOCRStatus(_ message: String) {
        ocrStatusMessage = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            ocrStatusMessage = nil
        }
    }

    func imageData(at pageIndex: Int) async -> Data? {
        await pagePayload(at: pageIndex)?.imageData
    }

    private func pagePayload(
        at pageIndex: Int
    ) async -> MangaPagePayload? {
        guard pageReferences.indices.contains(pageIndex) else { return nil }
        do {
            return try await pageProvider.payload(
                for: pageReferences[pageIndex]
            )
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renderedImage(
        for page: MangaPresentationPage
    ) async -> NSImage? {
        guard pageReferences.indices.contains(page.sourcePageIndex) else {
            return nil
        }
        do {
            let payload = try await pageProvider.payload(
                for: pageReferences[page.sourcePageIndex]
            )
            guard let imageData = payload.imageData else {
                return Self.renderedTextPage(
                    payload.text ?? "",
                    title: pageReferences[page.sourcePageIndex].displayPath
                )
            }
            prefetchPages(around: page.sourcePageIndex)
            let rendered = try await Task.detached(priority: .userInitiated) {
                try MangaPageProcessor.renderedImage(
                    from: imageData,
                    transform: page.transform
                )
            }.value
            return rendered.image
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func prefetchPages(around pageIndex: Int) {
        let indices = ((pageIndex - 2)...(pageIndex + 2))
            .filter {
                $0 != pageIndex && pageReferences.indices.contains($0)
            }
        let pages = indices.map { pageReferences[$0] }
        let provider = pageProvider
        Task(priority: .utility) {
            await provider.prefetch(pages: pages)
        }
    }

    func setCover(to pageIndex: Int) {
        guard pageReferences.indices.contains(pageIndex) else {
            showOCRStatus(String(localized: "The selected manga page could not be used as a cover."))
            return
        }
        Task {
            do {
                let payload = try await pageProvider.payload(
                    for: pageReferences[pageIndex]
                )
                guard let imageData = payload.imageData else {
                    throw MangaPageLoaderError.pageUnavailable
                }
                try await session.coverWriter(imageData)
                showOCRStatus(String(localized: "Manga cover updated."))
            } catch is CancellationError {
                return
            } catch {
                showOCRStatus(error.localizedDescription)
            }
        }
    }

    func miningContext(sentence: String) async -> MiningContext {
        guard let pageIndex = lookupPageIndex,
              pageReferences.indices.contains(pageIndex),
              let payload = await pagePayload(at: pageIndex),
              let imageData = payload.imageData,
              let imageExtension = payload.fileExtension else {
            return MiningContext(
                sentence: sentence,
                documentTitle: session.title,
                coverURL: nil
            )
        }
        return MiningContext(
            sentence: sentence,
            documentTitle: session.title,
            coverURL: nil,
            manga: MangaMiningContext(
                pageIndex: pageIndex,
                imageData: imageData,
                imageExtension: imageExtension
            )
        )
    }

    private func move(by amount: Int) {
        go(to: currentPageIndex + amount)
    }

    private var currentSourcePageIndex: Int {
        guard presentationPages.indices.contains(currentPageIndex) else {
            return min(
                max(0, currentPageIndex),
                max(0, sourcePageCount - 1)
            )
        }
        return presentationPages[currentPageIndex].sourcePageIndex
    }

    private func rawLookupRegions(
        at sourcePageIndex: Int
    ) -> [MangaOCRTextRegion] {
        if let mokuroRegions = mokuroRegionsByPage[sourcePageIndex] {
            return mokuroRegions
        }
        return isOCREnabled
            ? ocrRegionsByPage[sourcePageIndex] ?? []
            : []
    }

    private func pageProcessingPreferenceDidChange() {
        popupPresentation.closeAll()
        if pageProcessingOptions.requiresAnalysis {
            if cachedPageAnalyses != nil {
                rebuildPresentationPagesIfPossible()
            } else {
                isPreparingPages = true
            }
        } else {
            isPreparingPages = false
            rebuildPresentationPages(using: nil)
        }
    }

    private func rebuildPresentationPagesIfPossible() {
        guard let cachedPageAnalyses else { return }
        rebuildPresentationPages(using: cachedPageAnalyses)
    }

    private func rebuildPresentationPages(
        using analyses: [MangaPageAnalysis]?
    ) {
        let sourcePaths = pageReferences.map(\.displayPath)
        let currentPage = presentationPages.indices.contains(currentPageIndex)
            ? presentationPages[currentPageIndex]
            : nil
        let nextPages: [MangaPresentationPage]
        if let analyses, pageProcessingOptions.requiresAnalysis {
            nextPages = MangaPagePresentationResolver.pages(
                sourcePaths: sourcePaths,
                analyses: analyses,
                options: pageProcessingOptions
            )
        } else {
            nextPages = MangaPagePresentationResolver.unprocessedPages(
                sourcePaths: sourcePaths
            )
        }

        presentationPages = nextPages
        guard !nextPages.isEmpty else {
            currentPageIndex = 0
            return
        }
        if let currentPage,
           let exactIndex = nextPages.firstIndex(where: {
               $0.sourcePageIndex == currentPage.sourcePageIndex
                   && $0.transform == currentPage.transform
           }) {
            currentPageIndex = exactIndex
        } else {
            let sourcePageIndex = currentPage?.sourcePageIndex
                ?? min(max(0, currentPageIndex), sourcePageCount - 1)
            currentPageIndex = nextPages.firstIndex(where: {
                $0.sourcePageIndex == sourcePageIndex
            }) ?? 0
        }
    }

    private func ocrCacheKey(
        pageIndex: Int,
        pagePaths: [String]
    ) -> MangaOCRCacheKey? {
        guard pagePaths.indices.contains(pageIndex) else { return nil }
        return MangaOCRCacheKey(
            itemID: ocrCacheItemID,
            pageIndex: pageIndex,
            pagePath: pagePaths[pageIndex],
            modifiedAt: session.modifiedAt,
            language: ocrLanguage
        )
    }

    private var ocrLanguage: MangaOCRLanguage {
        guard let profile = ProfileRepository.shared.profile(id: session.profileID)
        else {
            return .japanese
        }
        switch profile.language {
        case .japanese: return .japanese
        case .english: return .english
        }
    }

    private var ocrCacheItemID: String {
        guard let currentChapter,
              currentChapter.remoteIdentity != nil else {
            return session.documentID
        }
        return SuwayomiIdentity.sha256(
            [
                session.profileID,
                session.documentID,
                currentChapter.id,
            ].joined(separator: "\u{1f}")
        )
    }

    private var ocrPageIdentities: [String] {
        pageReferences.map(\.ocrCacheIdentity)
    }

    private func payloadForOCR(
        at pageIndex: Int,
        maximumAttempts: Int = 3
    ) async throws -> MangaPagePayload {
        guard pageReferences.indices.contains(pageIndex) else {
            throw MangaPageLoaderError.pageUnavailable
        }
        let page = pageReferences[pageIndex]
        var attempt = 0
        while true {
            do {
                return try await pageProvider.payload(for: page)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt < maximumAttempts else { throw error }
                try await Task.sleep(
                    for: .milliseconds(350 * attempt)
                )
            }
        }
    }

    private nonisolated static func renderedTextPage(
        _ text: String,
        title: String
    ) -> NSImage {
        let size = NSSize(width: 1200, height: 1800)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 10
        paragraph.paragraphSpacing = 14
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (title as NSString).draw(
            in: NSRect(x: 82, y: 80, width: size.width - 164, height: 42),
            withAttributes: headingAttributes
        )
        (text as NSString).draw(
            with: NSRect(x: 82, y: 150, width: size.width - 164, height: size.height - 232),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        image.unlockFocus()
        return image
    }

    private func persistProgress() {
        guard let chapter = currentChapter else { return }
        let pageIndex = currentSourcePageIndex
        let pageCount = sourcePageCount
        let completed = pageCount > 0 && pageIndex >= pageCount - 1
        if completed || chapter.wasReadAtOpen {
            completedProgressChapterIDs.insert(chapter.id)
        }
        let pendingCompletion =
            completedProgressChapterIDs.contains(chapter.id)
            || pendingProgressByChapter[chapter.id]?.completed == true
        if pendingProgressByChapter[chapter.id] == nil {
            pendingProgressOrder.append(chapter.id)
        }
        pendingProgressByChapter[chapter.id] = PendingProgress(
            chapter: chapter,
            pageIndex: pageIndex,
            pageCount: pageCount,
            completed: pendingCompletion
        )
        guard progressWriteTask == nil else { return }
        progressWriteTask = Task {
            while let chapterID = pendingProgressOrder.first {
                pendingProgressOrder.removeFirst()
                guard let progress =
                    pendingProgressByChapter.removeValue(
                        forKey: chapterID
                    ) else {
                    continue
                }
                await session.progressWriter(
                    progress.chapter,
                    progress.pageIndex,
                    progress.pageCount,
                    progress.completed
                )
            }
            progressWriteTask = nil
        }
    }

    private func invalidateOCRForChapterChange() {
        ocrContentGeneration = UUID()
        activeOCRScanID = nil
        isRecognizingText = false
        ocrScanCancellationID += 1
        ocrCompletedPageCount = 0
        ocrTotalPageCount = 0
        ocrRegionsByPage = [:]
        mokuroRegionsByPage = [:]
        lookupPageIndex = nil
        statusTask?.cancel()
        statusTask = nil
        ocrStatusMessage = nil
    }
}
