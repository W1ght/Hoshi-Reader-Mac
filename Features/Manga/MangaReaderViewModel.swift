import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MangaReaderViewModel {
    let item: MangaLibraryItem
    let source: MangaLibrarySource
    let loader: MangaPageLoader?
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
    private(set) var presentationPages: [MangaPresentationPage] = []
    private(set) var isPreparingPages = false
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
    @ObservationIgnored private var isOCRScanPaused = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var cachedPageAnalyses: [MangaPageAnalysis]?

    init(
        item: MangaLibraryItem,
        source: MangaLibrarySource,
        preferences: UserDefaults = .standard
    ) {
        self.item = item
        self.source = source
        self.preferences = preferences
        let initialLayout = MangaReaderPreferences.layout(in: preferences)
        layout = initialLayout
        direction = MangaReaderPreferences.direction(in: preferences)
        splitsWidePages = MangaPageProcessingPreferences.splitsWidePages(
            in: preferences
        )
        cropsWhiteBorders = MangaPageProcessingPreferences.cropsWhiteBorders(
            in: preferences
        )
        zoomPercentage = MangaReaderPreferences.zoomPercentage(in: preferences)
        isOCREnabled = MangaReaderPreferences.isOCREnabled(in: preferences)
        currentPageIndex = min(max(0, item.currentPageIndex), max(0, item.pageCount - 1))
        do {
            loader = try MangaPageLoader(item: item, source: source)
        } catch {
            loader = nil
            errorMessage = error.localizedDescription
        }
        let sourcePaths = loader?.pages.map(\.path) ?? []
        presentationPages = MangaPagePresentationResolver.unprocessedPages(
            sourcePaths: sourcePaths
        )
        isPreparingPages = pageProcessingOptions.requiresAnalysis
    }

    var pageCount: Int {
        presentationPages.count
    }

    var sourcePageCount: Int {
        loader?.pages.count ?? item.pageCount
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
        return "\(isOCREnabled)|\(sourceIndices.map(String.init).joined(separator: ","))"
    }

    var fullOCRRequestID: String {
        "\(isOCREnabled)|\(layout == .continuous)|\(ocrScanCancellationID)"
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
        guard let loader else { return }

        isPreparingPages = true
        let analysisTask = Task.detached(priority: .userInitiated) {
            var analyses: [MangaPageAnalysis] = []
            analyses.reserveCapacity(loader.pages.count)
            for pageIndex in loader.pages.indices {
                try Task.checkCancellation()
                analyses.append(
                    try MangaPageProcessor.analyze(
                        loader.imageData(at: pageIndex)
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
        await loadOCRRegions(
            for: Array(Set(displayedPages.map(\.sourcePageIndex))).sorted()
        )
    }

    func loadOCRRegions(for requestedIndices: [Int]) async {
        let requestedIndices = requestedIndices.filter {
            $0 >= 0 && $0 < sourcePageCount
        }
        guard !requestedIndices.isEmpty else { return }

        do {
            for pageIndex in requestedIndices where mokuroRegionsByPage[pageIndex] == nil {
                try Task.checkCancellation()
                guard let loader else { throw MangaPageLoaderError.pageUnavailable }
                let regions = try await Task.detached(priority: .userInitiated) {
                    try loader.mokuroRegions(at: pageIndex)
                }.value
                try Task.checkCancellation()
                if let regions {
                    mokuroRegionsByPage[pageIndex] = regions
                }
            }
        } catch is CancellationError {
            return
        } catch {
            showOCRStatus(error.localizedDescription)
            return
        }

        guard isOCREnabled else { return }
        let pagePaths = loader?.pages.map(\.path) ?? []
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
                guard isOCREnabled else { return }
                ocrRegionsByPage[pageIndex] = regions
            }
        }
    }

    func recognizeAllPages() async {
        guard isOCREnabled,
              !isOCRScanPaused,
              sourcePageCount > 0,
              let loader else {
            return
        }

        do {
            let usesMokuro = try await Task.detached(priority: .userInitiated) {
                try loader.hasMokuroMetadata()
            }.value
            if usesMokuro {
                await loadVisibleOCRRegions()
                return
            }
        } catch is CancellationError {
            return
        } catch {
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

        let pagePaths = loader.pages.map(\.path)
        let sourcePageIndex = currentSourcePageIndex
        let pageOrder = Array(sourcePageIndex..<sourcePageCount)
            + Array(0..<sourcePageIndex)
        var requestedNetworkPage = false

        do {
            for pageIndex in pageOrder {
                try Task.checkCancellation()
                guard isOCREnabled, activeOCRScanID == scanID,
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
                    ocrRegionsByPage[pageIndex] = regions
                    ocrCompletedPageCount += 1
                    continue
                }

                guard let data = await imageData(at: pageIndex) else {
                    try Task.checkCancellation()
                    throw MangaOCRError.imageUnavailable
                }
                requestedNetworkPage = true
                let regions = try await MangaOCRService.shared.recognizeText(
                    in: data,
                    key: key,
                    pagePaths: pagePaths
                )
                try Task.checkCancellation()
                guard isOCREnabled, activeOCRScanID == scanID else {
                    throw CancellationError()
                }
                ocrRegionsByPage[pageIndex] = regions
                ocrCompletedPageCount += 1
            }
            if requestedNetworkPage {
                showOCRStatus(String(localized: "Text recognition complete."))
            }
        } catch is CancellationError {
            return
        } catch {
            showOCRStatus(error.localizedDescription)
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
        guard let loader else { return nil }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try loader.imageData(at: pageIndex)
            }.value
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
        guard let loader else { return nil }
        do {
            let rendered = try await Task.detached(priority: .userInitiated) {
                try MangaPageProcessor.renderedImage(
                    from: loader.imageData(at: page.sourcePageIndex),
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

    func setCover(to pageIndex: Int) {
        guard let loader,
              loader.pages.indices.contains(pageIndex) else {
            showOCRStatus(String(localized: "The selected manga page could not be used as a cover."))
            return
        }
        let itemID = item.id
        Task {
            do {
                let imageData = try await Task.detached(priority: .userInitiated) {
                    try loader.imageData(at: pageIndex)
                }.value
                try await MangaLibraryStore.shared.setCover(
                    itemID: itemID,
                    imageData: imageData
                )
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
              let loader,
              loader.pages.indices.contains(pageIndex),
              let imageData = await imageData(at: pageIndex) else {
            return MiningContext(
                sentence: sentence,
                documentTitle: item.title,
                coverURL: nil
            )
        }
        let page = loader.pages[pageIndex]
        return MiningContext(
            sentence: sentence,
            documentTitle: item.title,
            coverURL: nil,
            manga: MangaMiningContext(
                pageIndex: pageIndex,
                imageData: imageData,
                imageExtension: URL(fileURLWithPath: page.path).pathExtension
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
        let sourcePaths = loader?.pages.map(\.path) ?? []
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
            itemID: item.id,
            pageIndex: pageIndex,
            pagePath: pagePaths[pageIndex],
            modifiedAt: item.modifiedAt
        )
    }

    private func persistProgress() {
        let itemID = item.id
        let pageIndex = currentSourcePageIndex
        let updatedAt = Date()
        Task {
            await MangaLibraryStore.shared.updateProgress(
                itemID: itemID,
                pageIndex: pageIndex,
                updatedAt: updatedAt
            )
        }
    }
}
