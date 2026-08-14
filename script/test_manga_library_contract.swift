import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let section = try source("NativeMac/NativeMacSection.swift")
let detail = try source("NativeMac/NativeMacDetailView.swift")
let app = try source("NativeMac/HoshiNativeMacApp.swift")
let rootView = try source("NativeMac/NativeMacRootView.swift")
let sidebar = try source("NativeMac/NativeMacSidebarView.swift")
let project = try source("Niratan.xcodeproj/project.pbxproj")
let info = try source("HoshiReader-Info.plist")
let ankiModels = try source("Models/Anki.swift")
let ankiManager = try source("Core/AnkiManager.swift")
let models = try source("Models/Manga.swift")
let store = try source("Features/Manga/MangaLibraryStore.swift")
let loader = try source("Features/Manga/MangaPageLoader.swift")
let epub = try source("Features/Manga/MangaEPUBParser.swift")
let mokuro = try source("Features/Manga/MangaMokuroParser.swift")
let ocr = try source("Features/Manga/MangaOCRService.swift")
let pageProcessing = try source("Features/Manga/MangaPageProcessing.swift")
let library = try source("Features/Manga/MangaLibraryView.swift")
let libraryModel = try source("Features/Manga/MangaLibraryViewModel.swift")
let reader = try source("Features/Manga/MangaReaderView.swift")
let readerModel = try source("Features/Manga/MangaReaderViewModel.swift")
let pageProvider = try source("Features/Manga/MangaPageProvider.swift")
let suwayomiModel = try source("Models/Suwayomi.swift")
let suwayomiClient = try source("Features/Manga/SuwayomiClient.swift")
let suwayomiStore = try source("Features/Manga/SuwayomiConnectionStore.swift")
let suwayomiView = try source("Features/Manga/SuwayomiSourceView.swift")
let aidokuModel = try source("Models/Aidoku.swift")
let aidokuStore = try source("Features/Manga/AidokuGlobalStore.swift")
let aidokuView = try source("Features/Manga/AidokuSourceView.swift")
let aidokuPackage = try source("Libraries/AidokuRuntime/Package.swift")
let aidokuInstaller = try source("Libraries/AidokuRuntime/Sources/AidokuRuntime/AidokuPackageInstaller.swift")
let aidokuSanitizer = try source("Libraries/AidokuRuntime/Sources/AidokuRuntime/AidokuWasmSanitizer.swift")
let aidokuIconLoader = try source("Libraries/AidokuRuntime/Sources/AidokuRuntime/AidokuSourceIconLoader.swift")
let popupModels = try source("Features/Popup/PopupModels.swift")
let popupView = try source("Features/Popup/PopupView.swift")
let nativeReader = try source("NativeMac/NativeReaderView.swift")
let videoPlayer = try source("Features/Video/VideoPlayerScreen.swift")
let dictionaryView = try source("Features/Dictionary/DictionarySearchView.swift")
let quickLookup = try source("NativeMac/QuickLookupPanelController.swift")
let textSelection = try source("Core/SelectionLookup/TextSelectionResolver.swift")
let presenter = try source("NativeMac/MangaWindowPresenter.swift")
let mangaCoordinator = try source("NativeMac/MangaWindowCoordinator.swift")
let localizations = try source("Localizable.xcstrings")

require(
    section.contains("case manga")
        && detail.contains("MangaLibraryView(")
        && detail.contains("viewModel: mangaLibraryViewModel")
        && rootView.contains("@State private var mangaLibraryViewModel")
        && rootView.contains("return .hidden")
        && !rootView.contains("ToolbarItem(placement: .primaryAction)")
        && !rootView.contains(".frame(width: 1, height: 1)")
        && rootView.contains(
            ".frame(maxWidth: .infinity, maxHeight: .infinity)"
        )
        && sidebar.contains(
            ".contentMargins(.leading, 16, for: .scrollContent)"
        )
        && rootView.contains("mangaLibraryViewModel.load()")
        && libraryModel.contains("var hasLoadedCatalog = false")
        && library.contains("if !viewModel.hasLoadedCatalog")
        && rootView.contains("MangaWindowPresenter.shared.open("),
    "Manga must be a first-class native navigation section while the main split view fills the window inside the system-reserved toolbar safe area"
)
require(
    app.contains("@State private var mangaWindowCoordinator")
        && app.contains(".environment(mangaWindowCoordinator)"),
    "The dedicated manga reader window must receive scene-owned coordination"
)
require(
    project.contains("Manga.swift")
        && project.contains("Manga/MangaLibraryStore.swift")
        && project.contains("Manga/MangaEPUBParser.swift")
        && project.contains("Manga/MangaMokuroParser.swift")
        && project.contains("Manga/MangaOCRService.swift")
        && project.contains("Manga/MangaPageProcessing.swift")
        && project.contains("Manga/MangaReaderView.swift"),
    "Synchronized Xcode groups must explicitly include the new Manga files"
)
require(
    project.contains("Suwayomi.swift")
        && project.contains("Manga/SuwayomiClient.swift")
        && project.contains("Manga/SuwayomiConnectionStore.swift")
        && project.contains("Manga/SuwayomiSourceView.swift")
        && project.contains("Aidoku.swift")
        && project.contains("Manga/AidokuGlobalStore.swift")
        && project.contains("Manga/AidokuSourceView.swift")
        && project.contains("AidokuRuntime")
        && !project.contains("Manga Source Runtime.xpc")
        && !project.contains("AidokuRunner"),
    "Manga external sources must expose Suwayomi plus the bounded local AidokuRuntime without prohibited helper runtimes"
)
require(
    library.contains("case local")
        && library.contains("case online")
        && library.contains("@State private var remoteConnector: MangaRemoteConnector = .aidoku")
        && library.contains("MangaSourceBrowseView(")
        && library.contains("MangaSourcesView(")
        && suwayomiView.contains("Suwayomi Server")
        && suwayomiView.contains("Suwayomi Library")
        && suwayomiClient.contains(#"path: "source/list""#)
        && suwayomiClient.contains(#"path: "category""#)
        && suwayomiClient.contains("onlineFetch=true")
        && suwayomiClient.contains("chapter.mangaId")
        && suwayomiStore.contains(#""suwayomi.json""#)
        && suwayomiStore.contains("kSecClassGenericPassword")
        && library.contains("AidokuBrowseView(")
        && library.contains("AidokuSourcesView(")
        && library.contains("AidokuLibraryView(")
        && aidokuModel.contains("AidokuGlobalCatalog")
        && aidokuModel.contains("https://aidoku-community.github.io/sources/index.min.json")
        && aidokuModel.contains("mutating func seedBuiltInSourceLists() -> Bool")
        && aidokuStore.contains("catalog.seedBuiltInSourceLists()")
        && aidokuStore.contains("?.isBuiltIn != true")
        && aidokuView.contains("if list.isBuiltIn")
        && aidokuStore.contains("moe.shishamo.hoshi.aidoku")
        && aidokuView.contains("Show Adult Sources and Manga")
        && aidokuView.contains("request.configuration.localStorageKeys")
        && aidokuView.contains("window.localStorage.getItem(key)")
        && aidokuView.contains("AidokuWebLoginValues.mergedValues")
        && aidokuView.contains("values.merge(localStorage)")
        && aidokuPackage.contains("SwiftSoup")
        && aidokuPackage.contains("name: \"Wasm3\"")
        && aidokuInstaller.contains("maximumArchiveEntries")
        && aidokuInstaller.contains("missing required exports")
        && aidokuSanitizer.contains("maximumLinearMemoryBytes")
        && info.contains("<key>NSAllowsArbitraryLoads</key>")
        && !info.contains("<key>NSAllowsLocalNetworking</key>"),
    "Manga must expose local, Suwayomi, and Aidoku library/browse/source surfaces with their distinct persistence and runtime boundaries"
)
require(
    aidokuView.contains("var sourceSearchText = \"\"")
        && aidokuView.contains("AidokuSourceSearch.matches(")
        && aidokuView.contains("Search Aidoku Sources")
        && aidokuView.contains("AidokuSourceIconView(")
        && aidokuView.contains("installedSourceIconData(source)")
        && aidokuView.contains("availableSourceIconData(candidate)")
        && aidokuView.contains("LazyVStack(spacing: 0)")
        && aidokuStore.contains("AidokuSourceIconLoader(cacheDirectory:")
        && aidokuStore.contains("location: .installedSource(sourceDirectory)")
        && aidokuStore.contains("insecureTransportApproved: list.insecureTransportApproved")
        && aidokuIconLoader.contains("maximumEncodedBytes = 4 * 1_024 * 1_024")
        && aidokuIconLoader.contains("maximumDecodedBytes = 16 * 1_024 * 1_024")
        && aidokuIconLoader.contains("kCGImageSourceThumbnailMaxPixelSize: 256")
        && localizations.contains("No available Aidoku sources match the current filters."),
    "Aidoku source management must search local metadata and show bounded, cached package/list icons without eagerly loading every offscreen row"
)
require(
    suwayomiModel.contains("SuwayomiManga")
        && pageProvider.contains("MangaReadingSession")
        && pageProvider.contains("MangaRemoteReadingRequest")
        && pageProvider.contains("func load() async throws -> MangaRemoteReadingResult")
        && pageProvider.contains("MangaPageContentProvider")
        && pageProvider.contains("LocalMangaPageContentProvider")
        && pageProvider.contains("SuwayomiMangaPageContentProvider")
        && pageProvider.contains("AidokuMangaPageContentProvider")
        && pageProvider.contains("MangaPagePayloadContent")
        && pageProvider.contains("96 * 1_024 * 1_024")
        && readerModel.contains("let session: MangaReadingSession")
        && readerModel.contains("let pageProvider: any MangaPageContentProvider")
        && suwayomiView.contains("onOpen(try viewModel.prepareReading")
        && suwayomiView.contains("detailLoadID = loadID")
        && suwayomiView.contains("isLoadingDetails = true")
        && suwayomiView.contains("detailChapters = []")
        && suwayomiView.contains("detail = manga")
        && suwayomiView.contains(
            "self.detailLoadID == detailLoadID"
        )
        && suwayomiView.contains("self.detailLoadID = nil")
        && suwayomiView.contains("isCurrentConnection(")
        && suwayomiView.contains("var contentMode: ContentMode = .fill")
        && suwayomiView.contains(".aspectRatio(contentMode: contentMode)")
        && suwayomiView.contains("contentMode: .fit")
        && suwayomiView.contains(
            "var containerAspectRatio: CGFloat = 0.709"
        )
        && suwayomiView.contains(
            ".aspectRatio(containerAspectRatio, contentMode: .fit)"
        )
        && suwayomiView.contains("var showsBackground = true")
        && suwayomiView.contains("Color.clear")
        && suwayomiView.contains("containerAspectRatio: 4.0 / 3.0")
        && suwayomiView.contains("showsBackground: false")
        && suwayomiView.contains(".frame(maxWidth: .infinity)")
        && !suwayomiView.contains(".frame(width: 360, height: 330)")
        && suwayomiView.contains(".frame(minWidth: 960, minHeight: 680)")
        && suwayomiView.contains(".buttonStyle(.glassProminent)")
        && !suwayomiView.contains(
            "private struct MangaDetailGlassButtonStyle"
        )
        && localizations.contains(#""Add to Library""#)
        && localizations.contains(#""value": "加入书库""#)
        && localizations.contains(#""value": "移出书库""#)
        && library.contains("request: request")
        && mangaCoordinator.contains("case remoteRequest(MangaRemoteReadingRequest)")
        && presenter.contains("MangaRemoteReaderLoadingView")
        && presenter.contains("result = try await request.load()")
        && presenter.contains(#"ProgressView("Preparing Manga Pages…")"#)
        && presenter.contains(#"Button("Retry")"#)
        && reader.contains(#"Label("Chapters""#),
    "Local and Suwayomi manga must share the native Reader while remote requests open its window before network preparation"
)
require(
    library.contains(".pickerStyle(.segmented)")
        && !library.contains("NativeGlassSegmentedPicker(")
        && suwayomiView.contains("NativeGlassMenuPicker(")
        && suwayomiView.contains("NativeGlassSegmentedPicker(")
        && suwayomiView.contains(".nativeSettingsTextField()")
        && suwayomiView.contains(".buttonStyle(.glass")
        && suwayomiView.contains(".suwayomiErrorBanner(viewModel)")
        && !suwayomiView.contains(".suwayomiErrorAlert(viewModel)")
        && !suwayomiView.contains(
            """
            connectionState = .failed(error.localizedDescription)
                        errorMessage = error.localizedDescription
            """
        )
        && !suwayomiView.contains(".pickerStyle(.segmented)")
        && !suwayomiView.contains(".textFieldStyle(.roundedBorder)")
        && !suwayomiView.contains(".buttonStyle(.borderedProminent)")
        && suwayomiView.contains("activeSearchQuery")
        && suwayomiView.contains("selectedSource?.supportsLatest == true")
        && !suwayomiView.contains(
            ".fixedSize(horizontal: false, vertical: true)"
        )
        && !suwayomiView.contains(".padding(.top, 48)")
        && !suwayomiView.contains("maxHeight: .infinity,\n                alignment: .top"),
    "Manga source controls must use macOS 26 Liquid Glass, avoid fixed-size disconnected states that displace the main sidebar, and route Latest independently from submitted searches"
)
require(
    suwayomiView.contains(
        "minimum: BookshelfLayout.v050CoverWidth"
    )
        && suwayomiView.contains(
            "maximum: BookshelfLayout.v050CoverWidth"
        )
        && suwayomiView.contains("spacing: BookshelfLayout.rowSpacing")
        && suwayomiView.contains("ShelfBookCard(")
        && suwayomiView.contains("title: manga.title")
        && suwayomiView.contains("progress: nil")
        && suwayomiView.contains(
            "var containerAspectRatio: CGFloat = 0.709"
        )
        && suwayomiView.contains(
            ".aspectRatio(containerAspectRatio, contentMode: .fit)"
        )
        && !suwayomiView.contains(".frame(height: 230)"),
    "Manga browse and online-library posters must reuse the local shelf card width, spacing, cover ratio, and glass presentation without inventing remote reading progress"
)
require(
    models.contains(#"archiveExtensions: Set<String> = ["cbz", "epub", "zip"]"#)
        && models.contains("case epubArchive")
        && models.contains("MangaPagePairResolver"),
    "Manga must support CBZ/ZIP/EPUB and deterministic double-page ordering"
)
require(
    pageProcessing.contains("widePageAspectRatio")
        && pageProcessing.contains("splitsWidePages")
        && pageProcessing.contains("cropsWhiteBorders")
        && pageProcessing.contains("readingDirection == .rightToLeft")
        && reader.contains(#""Split Wide Pages""#)
        && reader.contains(#""Crop White Borders""#),
    "Manga must keep wide-page splitting and scan-border cropping inside its native page pipeline"
)
require(
    store.contains(".withSecurityScope")
        && store.contains(".securityScopeAllowOnlyReadAccess")
        && !store.contains(".copyItem(")
        && !store.contains(".moveItem("),
    "The local manga library must index user files non-destructively"
)
require(
    loader.contains("localizedStandardCompare")
        && loader.contains("maximumExpandedPageBytes")
        && loader.contains("isUnsafeArchivePath")
        && loader.contains("isIgnoredArchivePagePath"),
    "Page loading must use natural sorting and bounded, safe archive reads"
)
require(
    library.contains("panel.allowedContentTypes = MangaMediaTypes.importContentTypes")
        && library.contains("panel.canChooseDirectories = true")
        && library.contains("panel.canChooseFiles = true")
        && library.contains("presentMangaImporter()")
        && !library.contains("BookshelfFileDropTarget(")
        && library.contains(#"Label("Import Manga", systemImage: "plus")"#)
        && !library.contains("presentFolderImporter")
        && !library.contains("presentArchiveImporter")
        && !library.contains(#"Label("Add Manga Folder""#)
        && !library.contains(#"Label("Add Manga Archive""#)
        && library.contains(#""Choose a folder, CBZ, ZIP, or EPUB file.""#)
        && library.contains(#""Add a local folder, CBZ, ZIP, or EPUB file to start reading.""#)
        && models.contains("case imageFolder")
        && models.contains("case mokuroFolder")
        && models.contains(#"importedAs: "moe.shishamo.hoshi.cbz-archive""#)
        && models.contains("conformingTo: .zip")
        && info.contains("<string>moe.shishamo.hoshi.cbz-archive</string>")
        && info.contains("<string>public.zip-archive</string>")
        && info.contains("<string>cbz</string>")
        && store.contains("MangaMediaTypes.containerKind(for: root)")
        && store.contains("MangaMediaTypes.containerKind(for: candidate)")
        && store.contains("? .mokuroFolder : .imageFolder")
        && store.contains("kind = .mokuroFolder")
        && store.contains("case .imageFolder:")
        && store.contains("case .mokuroFolder:")
        && store.contains("case .folder:")
        && store.contains("case .noReadablePages:")
        && !store.contains("throw MangaLibraryStoreError.missingMokuroMetadata")
        && loader.contains("case .epubArchive:")
        && loader.contains(#""META-INF/container.xml""#)
        && loader.contains("MangaEPUBParser.packagePath(in: containerData)")
        && loader.contains("package.orderedImagePaths")
        && epub.contains("spineItemIDs")
        && epub.contains("linear")
        && epub.contains("imageReferences(in:")
        && epub.contains("resolve(reference:"),
    "Manga import must accept direct ordinary image folders, CBZ/ZIP, Mokuro and EPUB without restoring recursive parent-folder imports"
)
require(
    library.contains("showTitle: true")
        && library.contains("viewModel.recordOpened(item)")
        && libraryModel.contains("$0.lastReadAt != nil")
        && store.contains("func recordOpened(itemID: String"),
    "Manga must visibly label Unshelved and treat an opened unfinished title as Reading"
)
require(
    loader.contains("static func hasMokuroMetadata(")
        && loader.contains("struct MangaMokuroArchiveBook")
        && loader.contains("static func mokuroArchiveBooks(")
        && loader.contains("static func mokuroDirectoryURLs(")
        && loader.contains("archiveMetadataPath: String? = nil")
        && loader.contains("$0.metadataPath == archiveMetadataPath")
        && loader.contains("siblingImageRoot")
        && loader.contains("rootMatches.count == 1")
        && loader.contains("MangaMokuroParser.pagePaths(in: data)")
        && loader.contains("if kind == .zipArchive")
        && loader.contains(#"name.hasSuffix(".mokuro") || name == "mokuro.json""#)
        && loader.contains("maximumBytes: maximumMokuroMetadataBytes")
        && mokuro.contains("static func isMetadata(_ data: Data) -> Bool")
        && mokuro.contains("static func pagePaths(in data: Data) throws -> [String]")
        && store.contains("let books = try MangaPageLoader.mokuroArchiveBooks(at: root)")
        && store.contains("MangaPageLoader.mokuroDirectoryURLs(at: root)")
        && store.contains("func splitMergedMokuroSourcesIfNeeded()")
        && store.contains("case .mokuroFolder:")
        && libraryModel.contains("await store.splitMergedMokuroSourcesIfNeeded()")
        && store.contains("relativePath: book.metadataPath")
        && store.contains("preinspectedPages: pages")
        && store.contains("previousItems[id] ?? previousFallback"),
    "Mokuro imports must validate bounded metadata and split multi-book folders/archives into isolated page lists"
)
let mokuroLoad = readerModel.range(of: "let regions = payload.embeddedTextRegions")
let googleGate = readerModel.range(of: "guard isOCREnabled else { return }")
require(
    loader.contains(#"itemURL.appendingPathExtension("mokuro")"#)
        && loader.contains(#"itemURL.appendingPathExtension("json")"#)
        && loader.contains(#"itemURL.appendingPathComponent(".mokuro")"#)
        && loader.contains(#"itemURL.appendingPathComponent("mokuro.json")"#)
        && loader.contains("maximumMokuroMetadataBytes")
        && mokuro.contains(#"root["pages"]"#)
        && mokuro.contains(#"raw["lines_coords"]"#)
        && mokuro.contains("caseInsensitiveCompare(pageName)")
        && mokuroLoad != nil
        && googleGate != nil
        && mokuroLoad!.lowerBound < googleGate!.lowerBound
        && readerModel.contains("pageProvider.hasEmbeddedText(")
        && pageProvider.contains("loader.mokuroRegions(at: page.index)")
        && readerModel.contains("where mokuroRegionsByPage[pageIndex] == nil")
        && reader.contains("if !viewModel.allVisiblePagesUseMokuro"),
    "Mokuro metadata must resolve locally before Google OCR and enable lookup without the OCR toggle"
)
require(
    reader.contains("case .singlePage, .doublePage")
        && reader.contains("MangaContinuousReader")
        && reader.contains("allowsMagnification = true")
        && reader.contains("MangaSpreadDocumentView")
        && reader.contains("MangaCenteredClipView")
        && reader.contains("lastAppliedFitMagnification")
        && reader.contains("viewportSize != lastViewportSize")
        && reader.contains("maxMagnification = max(8, fit * 2)")
        && reader.contains("minMagnification = fit * 0.5")
        && reader.contains(#".onKeyPress(.escape)"#)
        && reader.contains("viewModel.handleEscape() ? .handled : .ignored")
        && reader.contains("handleLeftArrow()")
        && reader.contains("handleRightArrow()")
        && reader.contains("override func scrollWheel(with event: NSEvent)")
        && reader.contains("event.hasPreciseScrollingDeltas")
        && reader.contains("wheelNavigationCooldown")
        && reader.contains("MangaWheelNavigationAccumulator")
        && reader.contains("handleModifierWheelZoom")
        && reader.contains("onZoomScaleChange")
        && reader.contains("configureContinuousZoom(")
        && reader.contains("onContinuousZoomScaleChange?(targetScale)")
        && reader.contains("override func rightMouseDown(with event: NSEvent)")
        && reader.contains("private var ancestorScrollView: NSScrollView?")
        && reader.contains("candidate = view.superview")
        && reader.contains("NSPasteboard.general.writeObjects([image])")
        && reader.contains("NSSavePanel()")
        && reader.contains("NSSharingServicePicker(items: [image])")
        && reader.contains("onSetCover?(pageIndex)")
        && store.contains("func setCover(itemID: String, imageData: Data) throws")
        && store.contains(#""custom-\(Self.fnv1a64(itemID)).jpg""#)
        && reader.contains("super.scrollWheel(with: event)")
        && models.contains("MangaWheelNavigationResolver")
        && models.contains("MangaWheelZoomResolver")
        && readerModel.contains("func handleEscape() -> Bool")
        && readerModel.contains("guard !popupPresentation.popups.isEmpty else { return false }")
        && readerModel.contains(
            """
            func handleLeftArrow() {
                    if direction == .rightToLeft {
                        goForward()
                    } else {
                        goBackward()
                    }
                }
            """
        )
        && readerModel.contains(
            """
            func handleRightArrow() {
                    if direction == .rightToLeft {
                        goBackward()
                    } else {
                        goForward()
                    }
                }
            """
        ),
    "The reader must provide paged, double-page, continuous, resize-aware zoom, mouse-wheel paging at every zoom, modifier-wheel zoom, trackpad and right-button panning, page image actions, popup Escape dismissal, and direction-aware keyboard behavior"
)
require(
    models.contains(#"static let layoutKey = "mangaReaderLayout""#)
        && models.contains(#"static let directionKey = "mangaReadingDirection""#)
        && models.contains(#"static let zoomLevelKey = "mangaReaderZoomLevel""#)
        && !models.contains("enum MangaReaderZoomLevel")
        && readerModel.contains("MangaReaderPreferences.layout(in: preferences)")
        && readerModel.contains("MangaReaderPreferences.direction(in: preferences)")
        && readerModel.contains("MangaReaderPreferences.zoomPercentage(in: preferences)")
        && readerModel.contains("MangaReaderPreferences.save(layout: layout, in: preferences)")
        && readerModel.contains("MangaReaderPreferences.save(direction: direction, in: preferences)")
        && readerModel.contains("MangaReaderPreferences.save(")
        && !reader.contains(#"Picker("Reading Layout""#)
        && !reader.contains(#"Picker("Reading Direction""#)
        && reader.contains("viewModel.layout = layout")
        && reader.contains("viewModel.direction = direction")
        && reader.contains("MangaZoomControls(viewModel: viewModel)")
        && reader.contains("Slider(")
        && reader.contains(#"TextField("", text: $percentageText)"#)
        && reader.contains(#"TextField("", text: $pageText)"#)
        && reader.contains(".mangaGlassNumericField()")
        && reader.contains(".buttonStyle(.glass)")
        && reader.contains(".glassEffect(")
        && reader.contains(".frame(width: 440)")
        && reader.contains("apply(Int(sliderPercentage.rounded()))")
        && reader.contains("percentageText = String(Int(newValue.rounded()))")
        && !reader.contains("Zoom Presets")
        && reader.contains("MangaReaderPreferences.clampedZoomPercentage")
        && reader.contains("zoomScale: viewModel.zoomScale")
        && reader.contains("let pageWidth = basePageWidth * viewModel.zoomScale")
        && reader.contains("ScrollView([.horizontal, .vertical])")
        && reader.contains("let target = fit * requestedZoomScale")
        && reader.contains(#"? "checkmark""#),
    "Manga layout, direction, and persisted page zoom must expose a page-navigator-width macOS 26 glass slider that commits after dragging plus numeric input without zoom presets"
)
require(
    reader.contains("MangaPageNavigator(")
        && reader.contains(#".popover(isPresented: $showsPageNavigator, arrowEdge: .top)"#)
        && reader.contains(#"systemImage: "backward.end.fill""#)
        && reader.contains(#"systemImage: "backward.fill""#)
        && reader.contains(#"systemImage: "forward.fill""#)
        && reader.contains(#"systemImage: "forward.end.fill""#)
        && reader.contains("TextField(\"\", text: $pageText)")
        && reader.contains("Slider(")
        && reader.contains("onSubmit(commitPageText)"),
    "Manga page navigation must use a compact native popover with boundary buttons, validated input, and a slider instead of a page-length menu"
)
require(
    reader.contains("ScrollViewReader { scrollProxy in")
        && reader.contains("MangaContinuousPageFramePreferenceKey")
        && reader.contains("topVisiblePageIndex(")
        && reader.contains("requestedScrollTarget = pageIndex")
        && reader.contains("scrollProxy.scrollTo(pageIndex, anchor: .top)")
        && !reader.contains(".scrollTargetBehavior(.viewAligned"),
    "Continuous Manga reading must preserve native free scrolling and avoid view-aligned lazy targets that crash Accessibility end scrolling"
)
require(
    reader.contains("ControlGroup {")
        && reader.contains(".controlGroupStyle(.navigation)")
        && reader.contains(#"systemImage: "chevron.left""#)
        && reader.contains(#"systemImage: "chevron.right""#)
        && reader.contains("viewModel.handleLeftArrow()")
        && reader.contains("viewModel.handleRightArrow()")
        && reader.contains("viewModel.direction == .rightToLeft")
        && !reader.contains(#"systemImage: "chevron.backward""#)
        && !reader.contains(#"systemImage: "chevron.forward""#),
    "Manga toolbar page arrows must use one native navigation control group whose physical left/right actions follow reading direction"
)
require(
    ocr.contains("https://lensfrontend-pa.googleapis.com/v1/crupload")
        && ocr.contains(#""application/x-protobuf""#)
        && ocr.contains(#""X-Goog-Api-Key""#)
        && ocr.contains("Task.detached(priority: .userInitiated)")
        && ocr.contains("maximumImageDimension")
        && ocr.contains("maximumResponseBytes")
        && ocr.contains("URLSessionConfiguration.ephemeral")
        && ocr.contains("error.code == .cancelled")
        && ocr.contains("MangaGoogleLensProtocol.decodeResponse")
        && ocr.contains("MangaOCRCacheKey")
        && ocr.contains(#""MangaOCR""#)
        && ocr.contains("applicationSupportDirectory")
        && ocr.contains("manifest.json")
        && ocr.contains("pagePaths: [String]")
        && ocr.contains("options: .atomic")
        && readerModel.contains("recognizeAllPages()")
        && readerModel.contains("Array(sourcePageIndex..<sourcePageCount)")
        && readerModel.contains("MangaOCRService.shared.cachedRegions")
        && readerModel.contains("let pagePaths = ocrPageIdentities")
        && readerModel.contains("payloadForOCR(at: pageIndex)")
        && readerModel.contains("maximumAttempts: Int = 3")
        && readerModel.contains("hasFailedPages = true")
        && readerModel.contains("Text recognition finished with some pages pending.")
        && readerModel.contains("itemID: ocrCacheItemID")
        && !readerModel.contains("payloadIdentityByPage")
        && pageProvider.contains("let ocrCacheIdentity: String")
        && pageProvider.contains("ocrCacheIdentity: identity")
        && pageProvider.contains("inFlightPageRequests")
        && pageProvider.contains("request.task.cancel()")
        && suwayomiClient.contains("request.timeoutInterval = 120")
        && readerModel.contains("func cancelOCRRecognition()")
        && readerModel.contains("func resumeOCRRecognition()")
        && readerModel.contains("Completed pages remain available.")
        && reader.contains("ocrCompletedPageCount")
        && reader.contains("Cancel Text Recognition")
        && reader.contains("Resume Text Recognition"),
    "Manga OCR must scan from the current page, isolate slow-page failures, coalesce remote image loads, and persist validated per-page results"
)
require(
    reader.contains("mangaGoogleOCRDisclosureAccepted")
        && reader.contains("Use Google Lens Text Recognition?")
        && reader.contains("sends a reduced copy of every page without Mokuro text to Google")
        && reader.contains("Results are cached on this Mac"),
    "Google Lens OCR must disclose whole-manga upload and local caching before its first request"
)
require(
    reader.contains("MangaOCRTextRegion")
        && reader.contains("MangaSpreadDocumentView")
        && reader.contains("MangaContinuousPageCanvas")
        && reader.contains("popupCoordinateSpace.topLeadingRect")
        && reader.contains("viewModel.loadOCRRegions(")
        && reader.contains("page.sourcePageIndex")
        && reader.contains("view.setFitsSinglePageToBounds()")
        && readerModel.contains("func loadOCRRegions(for requestedIndices: [Int])")
        && readerModel.contains("func lookupRegions(for page: MangaPresentationPage)")
        && !readerModel.contains("guard layout != .continuous else { return }")
        && !reader.contains(".disabled(viewModel.layout == .continuous)")
        && reader.contains("drawOCRTextOverlay")
        && reader.contains("$0.region.blockID == selected.region.blockID")
        && reader.contains("Dictionary(grouping: activeRegions, by: \\.region.lineID)")
        && reader.contains("NSColor.white.withAlphaComponent(0.72)")
        && reader.contains("drawHorizontalOCRText")
        && reader.contains("drawVerticalOCRText")
        && reader.contains("mouseMoved(with event:")
        && reader.contains("let localRect = self.convert(")
        && reader.contains("self.bounds.height - localRect.maxY")
        && !reader.contains("let localRect = self.contentView.convert(")
        && reader.contains("onDismissOCRSelection")
        && !reader.contains("mangaPopupCloseButton")
        && reader.contains("PopupView(")
        && reader.contains("onOCRSelection")
        && !reader.contains("import WebKit")
        && readerModel.contains("PopupPresentationCoordinator")
        && readerModel.contains("TextSelectionResolver.lookupCandidate")
        && readerModel.contains("sentence: region.sentence")
        && readerModel.contains("miningContext: .text(\n                region.sentence"),
    "Manga OCR must reveal complete native text blocks and reuse the shared popup/mining path in paged and continuous layouts"
)
require(
    reader.contains("let anchorRect = blockRect(for: displayRegion.region)")
        && reader.contains("isVertical: popup.isVertical")
        && reader.contains("centersOnSelection: true")
        && readerModel.contains("isVertical: region.isVertical")
        && popupModels.contains("var centersOnSelection: Bool = false")
        && popupModels.contains("? selectionRect.midX")
        && popupModels.contains("? selectionRect.midY")
        && popupView.contains("centersOnSelection: Bool = false")
        && !nativeReader.contains("centersOnSelection:")
        && !videoPlayer.contains("centersOnSelection:")
        && !dictionaryView.contains("centersOnSelection:")
        && !quickLookup.contains("centersOnSelection:"),
    "Manga popup placement must use the complete oriented block while other lookup surfaces retain default placement"
)
require(
    ankiModels.contains("struct MangaMiningContext")
        && ankiModels.contains("var manga: MangaMiningContext? = nil")
        && readerModel.contains("lookupPageIndex = region.pageIndex")
        && readerModel.contains("func miningContext(sentence: String) async -> MiningContext")
        && readerModel.contains("pageReferences[pageIndex]")
        && readerModel.contains("MangaMiningContext(")
        && reader.contains("coverURL: nil")
        && reader.contains("miningContextProvider:")
        && ankiManager.contains("if let manga = context.manga")
        && ankiManager.contains(#""hoshi_manga_page""#),
    "Manga mining must route the hit page image through the shared Anki picture pipeline"
)
require(
    textSelection.contains("TextSelectionResolver")
        && textSelection.contains("contentLanguage: ContentLanguageProfile"),
    "Reader surfaces must share one language-aware text selection boundary"
)
require(
    presenter.contains("collectionBehavior.insert(.fullScreenPrimary)")
        && presenter.contains("NSWindow.FrameAutosaveName")
        && presenter.contains(".environment(userConfig)")
        && presenter.contains("window.title = item.displayTitle")
        && presenter.contains("ShortcutManager(registry: .application)"),
    "The manga reader must use a dedicated native, fullscreen-capable persistent window"
)
require(
    store.contains("managedCoverURL(for: path)")
        && store.contains("guard let coverURL = managedCoverURL(for: path) else { continue }")
        && loader.contains("Self.contains(resolvedItemURL, inside: sourceURL)"),
    "Manga must constrain app-owned cover deletion and decoded item paths to their managed roots"
)

for (path, text) in [
    ("Features/Manga/MangaLibraryView.swift", library),
    ("Features/Manga/MangaReaderView.swift", reader),
    ("Features/Manga/SuwayomiSourceView.swift", suwayomiView),
] {
    for forbidden in [
        ".material", ".regularMaterial", ".thinMaterial", ".ultraThinMaterial",
        "NativeGlassPageBackground",
    ] {
        require(
            !text.localizedCaseInsensitiveContains(forbidden),
            "\(path) must not use Material or legacy page backgrounds: \(forbidden)"
        )
    }
}
require(
    library.contains(".glassEffect(")
        && library.contains(".buttonStyle(.glass")
        && library.contains(".toolbar {")
        && library.contains("toolbarContent")
        && library.contains("ToolbarItemGroup(placement: .navigation)")
        && library.contains("ToolbarItemGroup(placement: .primaryAction)")
        && !library.contains("ToolbarSpacer(")
        && library.contains(".pickerStyle(.segmented)")
        && library.contains(".onChange(of: homeSection)")
        && library.contains(".onChange(of: librarySurface)")
        && library.contains("if isSelecting && showsLocalLibraryActions")
        && library.contains(
            """
            ZStack {
                        libraryPage
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            """
        )
        && library.contains("showsLocalLibraryActions")
        && !library.contains("localLibraryActions")
        && !library.contains("libraryHeader")
        && !library.contains("NativeGlassSegmentedPicker(")
        && !library.contains("GlassEffectContainer(spacing: 8)")
        && !library.contains("ViewThatFits(in: .horizontal)")
        && !library.contains("refreshWindowLayout()")
        && !library.contains("window.setFrame(")
        && !library.contains(".searchable(")
        && !library.contains(#"Label("Manage Manga Sources""#)
        && !library.contains("externaldrive.badge.minus")
        && !library.contains(#"Label("Refresh Manga Library""#)
        && !library.contains(#"systemImage: "arrow.clockwise""#)
        && !library.contains(".formStyle(.grouped)")
        && library.contains(#"NativeReaderSheetPanel("Manage Manga Shelves""#)
        && !libraryModel.contains("var searchText"),
    "Manga library surfaces must fill the detail host while navigation and local-library actions use the same native macOS toolbar structure as the novel bookshelf"
)
require(
    suwayomiView.contains("connectionLoadID = loadID")
        && suwayomiView.contains("activeOperationID")
        && suwayomiView.contains("private func beginOperation()")
        && suwayomiView.contains("isCurrentOperation(operationID)")
        && suwayomiView.contains("profileID: profileID")
        && suwayomiView.contains("loadID: loadID")
        && suwayomiView.contains("connectedProfileID == profileID")
        && suwayomiView.contains("client === expectedClient")
        && suwayomiView.contains("detailConnectionIdentity")
        && suwayomiView.contains("coverRequestID(for manga:")
        && suwayomiView.contains(
            ".task(id: viewModel.coverRequestID(for: manga))"
        )
        && suwayomiView.contains(
            #""\(profileID)\u{1f}\(client.serverID)""#
        ),
    "Suwayomi connection, detail, and cached reading state must remain bound to one explicit Profile/server generation"
)
require(
    pageProvider.contains("maximumPageCacheBytes")
        && pageProvider.contains("maximumPageCacheFiles")
        && pageProvider.contains("String(prepared.fetchedAt)")
        && pageProvider.contains("String(prepared.pageCount)")
        && pageProvider.contains("[.modificationDate: Date()]")
        && pageProvider.contains("private static func pruneCache(")
        && pageProvider.contains("values.isSymbolicLink != true")
        && pageProvider.contains("try? data.write(to: diskURL")
        && readerModel.contains("let imageExtension = payload.fileExtension")
        && readerModel.contains("imageExtension: imageExtension")
        && readerModel.contains("session.profileID")
        && readerModel.contains("invalidateOCRForChapterChange()")
        && readerModel.contains("ocrContentGeneration = UUID()")
        && readerModel.contains("pendingProgressByChapter")
        && readerModel.contains("pendingProgressOrder")
        && readerModel.contains("completedProgressChapterIDs"),
    "Remote Manga pages, OCR, mining, chapter changes, and progress must use bounded isolated latest-state pipelines"
)
require(
    reader.contains(
        "profileID: profileRepository.activeProfile.id"
    )
        && reader.contains(
            "of: profileRepository.index.globalActiveProfileId"
        )
        && readerModel.contains(
            "let profile = ProfileRepository.shared.activeProfile"
        )
        && suwayomiClient.contains(
            "retried.timeoutInterval = request.timeoutInterval"
        )
        && suwayomiStore.contains(
            "retainsCredentialIdentity"
        )
        && suwayomiModel.contains(
            "var credentialID: String? = nil"
        )
        && suwayomiStore.contains(
            "storedConfiguration.credentialID = nextCredentialID"
        )
        && suwayomiStore.contains(
            "kSecAttrGeneric as String: Data(profileID.utf8)"
        )
        && suwayomiStore.contains(
            "private func pruneVersionedSecrets("
        )
        && suwayomiStore.contains(
            "try Task.checkCancellation()"
        )
        && suwayomiStore.contains(
            "where error.code == .fileNoSuchFile"
        )
        && suwayomiView.contains(
            "let savedConfiguration = try await store.save("
        ),
    "Manga lookup must follow the active Profile while Suwayomi retries and credential clearing preserve their security boundaries"
)

print("Manga library contract passed")
