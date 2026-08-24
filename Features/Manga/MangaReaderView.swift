import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MangaReaderView: View {
    @Environment(UserConfig.self) private var userConfig
    @AppStorage("mangaGoogleOCRDisclosureAccepted")
    private var hasAcceptedGoogleOCRDisclosure = false
    @State private var profileRepository = ProfileRepository.shared
    @State private var viewModel: MangaReaderViewModel
    @State private var continuousScrollPosition: Int?
    @State private var showsGoogleOCRDisclosure = false
    @State private var showsPageNavigator = false
    @State private var showsZoomControls = false
    @State private var popupCoordinateSpace = MangaReaderPopupCoordinateSpace()

    init(item: MangaLibraryItem, source: MangaLibrarySource) {
        _viewModel = State(initialValue: MangaReaderViewModel(item: item, source: source))
        _continuousScrollPosition = State(initialValue: item.currentPageIndex)
    }

    init(
        session: MangaReadingSession,
        pageProvider: any MangaPageContentProvider
    ) {
        _viewModel = State(
            initialValue: MangaReaderViewModel(
                session: session,
                pageProvider: pageProvider
            )
        )
        _continuousScrollPosition = State(
            initialValue: session.initialPageIndex
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                readerContent

                ForEach(viewModel.popupPresentation.popups) { popup in
                    popupView(popup, screenSize: geometry.size)
                }

                if viewModel.isRecognizingText {
                    HStack(spacing: 10) {
                        ProgressView(value: viewModel.ocrProgress)
                            .frame(width: 96)
                        Text(
                            "OCR \(viewModel.ocrCompletedPageCount) / \(viewModel.ocrTotalPageCount)"
                        )
                        .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(1_000)
                } else if let message = viewModel.ocrStatusMessage {
                    Label(message, systemImage: "text.viewfinder")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(1_000)
                }
            }
            .background(
                MangaReaderCoordinateSpaceReader(
                    coordinateSpace: popupCoordinateSpace
                )
            )
        }
            .navigationTitle(viewModel.title)
            .toolbar {
                MangaReaderToolbar(
                    viewModel: viewModel,
                    showsPageNavigator: $showsPageNavigator,
                    showsZoomControls: $showsZoomControls,
                    onJumpToPage: jumpToPage,
                    onToggleOCR: toggleOCR
                )
            }
            .alert(
                "Unable to Open Manga",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Use Google Lens Text Recognition?",
                isPresented: $showsGoogleOCRDisclosure
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    hasAcceptedGoogleOCRDisclosure = true
                    viewModel.toggleOCR()
                }
            } message: {
                Text("Recognizing an entire manga sends a reduced copy of every page without Mokuro text to Google. Results are cached on this Mac so reopening does not recognize the same pages again. Google Lens requires an internet connection.")
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                viewModel.handleEscape() ? .handled : .ignored
            }
            .onKeyPress(.leftArrow) {
                viewModel.handleLeftArrow()
                syncContinuousPosition()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.handleRightArrow()
                syncContinuousPosition()
                return .handled
            }
            .onKeyPress(.pageUp) {
                viewModel.goBackward()
                syncContinuousPosition()
                return .handled
            }
            .onKeyPress(.pageDown) {
                viewModel.goForward()
                syncContinuousPosition()
                return .handled
            }
            .onChange(of: viewModel.layout) { _, layout in
                if layout == .continuous {
                    continuousScrollPosition = viewModel.currentPageIndex
                }
            }
            .onChange(
                of: profileRepository.index.globalActiveProfileId
            ) { _, _ in
                // Lookup state belongs to the Profile that created it. Close
                // it before the new Profile's Anki mapping becomes active.
                viewModel.closeOCRLookup()
            }
            .task(id: viewModel.visibleOCRRequestID) {
                await viewModel.loadVisibleOCRRegions()
            }
            .task(id: viewModel.pageProcessingRequestID) {
                await viewModel.preparePageProcessing()
                if viewModel.layout == .continuous {
                    continuousScrollPosition = viewModel.currentPageIndex
                }
            }
            .task(id: viewModel.fullOCRRequestID) {
                await viewModel.recognizeAllPages()
            }
    }

    @ViewBuilder
    private var readerContent: some View {
        if !viewModel.isContentAvailable {
            ContentUnavailableView {
                Label("Unable to Open Manga", systemImage: "exclamationmark.triangle")
            } description: {
                Text(viewModel.errorMessage ?? String(localized: "The manga source is no longer available."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoadingChapter || viewModel.isPreparingPages {
            ProgressView("Preparing Manga Pages…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            switch viewModel.layout {
            case .singlePage, .doublePage:
                MangaPagedReader(
                    viewModel: viewModel,
                    ocrRegions: viewModel.visibleOCRRegions,
                    showsOCRSelection: !viewModel.popupPresentation.popups.isEmpty,
                    onSetCover: coverUpdateHandler,
                    onDismissOCRSelection: viewModel.closeOCRLookup,
                    onOCRSelection: { region, rect in
                        viewModel.presentOCRLookup(
                            region: region,
                            anchorRect: rect,
                            userConfig: userConfig
                        )
                    }
                )
            case .continuous:
                MangaContinuousReader(
                    viewModel: viewModel,
                    scrollPosition: $continuousScrollPosition,
                    popupCoordinateSpace: popupCoordinateSpace,
                    showsOCRSelection: !viewModel.popupPresentation.popups.isEmpty,
                    onSetCover: coverUpdateHandler,
                    onDismissOCRSelection: viewModel.closeOCRLookup,
                    onOCRSelection: { region, rect in
                        viewModel.presentOCRLookup(
                            region: region,
                            anchorRect: rect,
                            userConfig: userConfig
                        )
                    }
                )
            }
        }
    }

    private var coverUpdateHandler: ((Int) -> Void)? {
        guard viewModel.allowsCoverUpdates else { return nil }
        return { pageIndex in
            viewModel.setCover(to: pageIndex)
        }
    }

    private func jumpToPage(_ pageIndex: Int) {
        viewModel.go(to: pageIndex)
        syncContinuousPosition()
    }

    private func toggleOCR() {
        if viewModel.isRecognizingText {
            viewModel.cancelOCRRecognition()
            return
        }
        if viewModel.isOCRRecognitionPaused {
            viewModel.resumeOCRRecognition()
            return
        }
        guard !viewModel.isOCREnabled,
              !hasAcceptedGoogleOCRDisclosure else {
            viewModel.toggleOCR()
            return
        }
        showsGoogleOCRDisclosure = true
    }

    private func syncContinuousPosition() {
        guard viewModel.layout == .continuous else { return }
        withAnimation(.smooth) {
            continuousScrollPosition = viewModel.currentPageIndex
        }
    }

    private func popupView(_ popup: PopupItem, screenSize: CGSize) -> some View {
        let popupID = popup.id
        return PopupView(
            userConfig: userConfig,
            isVisible: Binding(
                get: {
                    viewModel.popupPresentation.popups
                        .first(where: { $0.id == popupID })?
                        .showPopup ?? false
                },
                set: {
                    viewModel.popupPresentation.setVisibility(id: popupID, visible: $0)
                }
            ),
            selectionData: popup.currentSelection,
            lookupResults: popup.lookupResults,
            dictionaryStyles: popup.dictionaryStyles,
            screenSize: screenSize,
            isVertical: popup.isVertical,
            isFullWidth: false,
            centersOnSelection: true,
            coverURL: nil,
            documentTitle: viewModel.title,
            profileID: profileRepository.activeProfile.id,
            clearSelection: popup.clearSelection,
            onTextSelected: { selection in
                viewModel.popupPresentation.closeChildren(of: popupID)
                return viewModel.presentNestedLookup(
                    selection: selection,
                    userConfig: userConfig
                )
            },
            onTapOutside: {
                viewModel.popupPresentation.handleTapInsidePopup(id: popupID)
            },
            onSwipeDismiss: {
                viewModel.dismissPopup(id: popupID)
            },
            miningContextProvider: { sentence, _ in
                await viewModel.miningContext(sentence: sentence)
            }
        )
        .id(popupID)
    }

}

private struct MangaReaderToolbar: ToolbarContent {
    @Bindable var viewModel: MangaReaderViewModel
    @Binding var showsPageNavigator: Bool
    @Binding var showsZoomControls: Bool
    let onJumpToPage: (Int) -> Void
    let onToggleOCR: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button {
                    viewModel.handleLeftArrow()
                } label: {
                    Label(
                        viewModel.direction == .rightToLeft ? "Next Page" : "Previous Page",
                        systemImage: "chevron.left"
                    )
                }
                .disabled(
                    viewModel.direction == .rightToLeft
                        ? !viewModel.canGoForward
                        : !viewModel.canGoBackward
                )

                Button {
                    viewModel.handleRightArrow()
                } label: {
                    Label(
                        viewModel.direction == .rightToLeft ? "Previous Page" : "Next Page",
                        systemImage: "chevron.right"
                    )
                }
                .disabled(
                    viewModel.direction == .rightToLeft
                        ? !viewModel.canGoBackward
                        : !viewModel.canGoForward
                )
            }
            .controlGroupStyle(.navigation)
            .labelStyle(.iconOnly)
            .controlSize(.large)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.chapters.count > 1 {
                Menu {
                    Button {
                        Task { await viewModel.goToPreviousChapter() }
                    } label: {
                        Label("Previous Chapter", systemImage: "chevron.left")
                    }
                    .disabled(viewModel.currentChapterIndex == 0)

                    Button {
                        Task { await viewModel.goToNextChapter() }
                    } label: {
                        Label("Next Chapter", systemImage: "chevron.right")
                    }
                    .disabled(
                        viewModel.currentChapterIndex
                            >= viewModel.chapters.count - 1
                    )

                    Divider()

                    ForEach(Array(viewModel.chapters.enumerated()), id: \.element.id) {
                        index,
                        chapter in
                        Button {
                            Task { await viewModel.openChapter(at: index) }
                        } label: {
                            Label(
                                chapter.title,
                                systemImage: index
                                    == viewModel.currentChapterIndex
                                    ? "checkmark"
                                    : "book.pages"
                            )
                        }
                    }
                } label: {
                    Label("Chapters", systemImage: "list.bullet.rectangle")
                }
            }

            if !viewModel.allVisiblePagesUseMokuro {
                Button {
                    onToggleOCR()
                } label: {
                    if viewModel.isRecognizingText {
                        Label(
                            "Cancel Text Recognition",
                            systemImage: "xmark.circle"
                        )
                    } else if viewModel.isOCRRecognitionPaused {
                        Label(
                            "Resume Text Recognition",
                            systemImage: "play.circle"
                        )
                    } else {
                        Label(
                            viewModel.isOCREnabled
                                ? "Hide Recognized Text"
                                : "Recognize Entire Manga",
                            systemImage: viewModel.isOCREnabled
                                ? "text.viewfinder"
                                : "viewfinder"
                        )
                    }
                }
                .help(
                    viewModel.isRecognizingText
                        ? "Cancel Text Recognition"
                        : viewModel.isOCRRecognitionPaused
                            ? "Resume Text Recognition"
                            : "Recognize Entire Manga"
                )

                if viewModel.isOCRRecognitionPaused {
                    Button {
                        viewModel.toggleOCR()
                    } label: {
                        Label("Hide Recognized Text", systemImage: "eye.slash")
                    }
                    .help("Hide Recognized Text")
                }
            }

            Menu {
                ForEach(MangaReaderLayout.allCases) { layout in
                    Button {
                        viewModel.layout = layout
                    } label: {
                        Label(
                            LocalizedStringKey(layout.titleKey),
                            systemImage: viewModel.layout == layout
                                ? "checkmark"
                                : layout.systemImage
                        )
                    }
                }
            } label: {
                Label("Reading Layout", systemImage: viewModel.layout.systemImage)
            }

            Button {
                showsZoomControls.toggle()
            } label: {
                Label {
                    Text(verbatim: "\(viewModel.zoomPercentage)%")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            }
            .help("Page Zoom")
            .popover(isPresented: $showsZoomControls, arrowEdge: .top) {
                MangaZoomControls(viewModel: viewModel)
            }

            Menu {
                ForEach(MangaReadingDirection.allCases) { direction in
                    Button {
                        viewModel.direction = direction
                    } label: {
                        Label(
                            LocalizedStringKey(direction.titleKey),
                            systemImage: viewModel.direction == direction
                                ? "checkmark"
                                : direction.systemImage
                        )
                    }
                }
            } label: {
                Label("Reading Direction", systemImage: viewModel.direction.systemImage)
            }

            Menu {
                Toggle(
                    "Split Wide Pages",
                    isOn: $viewModel.splitsWidePages
                )

                Toggle(
                    "Crop White Borders",
                    isOn: $viewModel.cropsWhiteBorders
                )
            } label: {
                Label("Page Processing", systemImage: "crop")
            }

            Button {
                showsPageNavigator.toggle()
            } label: {
                Text(viewModel.pageLabel)
                    .monospacedDigit()
            }
            .help("Jump to Page")
            .popover(isPresented: $showsPageNavigator, arrowEdge: .top) {
                MangaPageNavigator(
                    viewModel: viewModel,
                    onJumpToPage: onJumpToPage
                )
            }
        }
    }
}

private struct MangaZoomControls: View {
    @Bindable var viewModel: MangaReaderViewModel

    @State private var sliderPercentage = 100.0
    @State private var percentageText = "100"
    @FocusState private var isPercentageFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Page Zoom", systemImage: "magnifyingglass")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    TextField("", text: $percentageText)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($isPercentageFieldFocused)
                        .frame(width: 58)
                        .mangaGlassNumericField()
                        .accessibilityLabel(Text("Zoom Percentage"))
                        .onSubmit(commitPercentageText)
                        .onChange(of: percentageText) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue {
                                percentageText = digits
                            }
                        }
                    Text(verbatim: "%")
                }
            }

            HStack(spacing: 10) {
                Text(verbatim: "\(MangaReaderPreferences.minimumZoomPercentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Slider(
                    value: $sliderPercentage,
                    in: Double(MangaReaderPreferences.minimumZoomPercentage)...Double(MangaReaderPreferences.maximumZoomPercentage),
                    step: 1
                ) { editing in
                    if editing {
                        isPercentageFieldFocused = false
                    } else {
                        apply(Int(sliderPercentage.rounded()))
                    }
                }
                .accessibilityLabel(Text("Page Zoom"))
                .onChange(of: sliderPercentage) { _, newValue in
                    percentageText = String(Int(newValue.rounded()))
                }

                Text(verbatim: "\(MangaReaderPreferences.maximumZoomPercentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear(perform: syncFromViewModel)
        .onChange(of: viewModel.zoomPercentage) { _, _ in
            guard !isPercentageFieldFocused else { return }
            syncFromViewModel()
        }
        .onChange(of: isPercentageFieldFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                commitPercentageText()
            }
        }
    }

    private func commitPercentageText() {
        guard let percentage = Int(percentageText) else {
            syncFromViewModel()
            return
        }
        apply(percentage)
    }

    private func apply(_ percentage: Int) {
        let clamped = MangaReaderPreferences.clampedZoomPercentage(percentage)
        viewModel.zoomPercentage = clamped
        sliderPercentage = Double(clamped)
        percentageText = String(clamped)
    }

    private func syncFromViewModel() {
        sliderPercentage = Double(viewModel.zoomPercentage)
        percentageText = String(viewModel.zoomPercentage)
    }
}

private struct MangaPageNavigator: View {
    @Bindable var viewModel: MangaReaderViewModel
    let onJumpToPage: (Int) -> Void

    @State private var pageText = ""
    @State private var sliderPage = 1.0
    @FocusState private var isPageFieldFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                pageButton(
                    title: "First Page",
                    systemImage: "backward.end.fill",
                    disabled: !viewModel.canGoBackward
                ) {
                    jump(to: 0)
                }

                pageButton(
                    title: "Previous Page",
                    systemImage: "backward.fill",
                    disabled: !viewModel.canGoBackward
                ) {
                    viewModel.goBackward()
                }

                TextField("", text: $pageText)
                    .font(.title3.monospacedDigit())
                    .focused($isPageFieldFocused)
                    .mangaGlassNumericField()
                    .accessibilityLabel(Text("Page Number"))
                    .onSubmit(commitPageText)
                    .onChange(of: pageText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue {
                            pageText = digits
                        }
                    }

                pageButton(
                    title: "Next Page",
                    systemImage: "forward.fill",
                    disabled: !viewModel.canGoForward
                ) {
                    viewModel.goForward()
                }

                pageButton(
                    title: "Last Page",
                    systemImage: "forward.end.fill",
                    disabled: !viewModel.canGoForward
                ) {
                    jump(to: viewModel.pageCount - 1)
                }
            }

            Slider(
                value: $sliderPage,
                in: 1...Double(max(1, viewModel.pageCount)),
                step: 1
            ) { editing in
                if !editing {
                    jump(to: Int(sliderPage.rounded()) - 1)
                }
            }
            .disabled(viewModel.pageCount <= 1)
            .accessibilityLabel(Text("Jump to Page"))
            .accessibilityValue(Text(viewModel.pageLabel))
        }
        .padding(18)
        .frame(width: 440)
        .onAppear(perform: syncControls)
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            syncControls()
        }
    }

    @ViewBuilder
    private func pageButton(
        title: LocalizedStringKey,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(disabled)
        .help(title)
    }

    private func commitPageText() {
        guard let requestedPage = Int(pageText) else {
            syncControls()
            return
        }
        jump(to: requestedPage - 1)
        isPageFieldFocused = false
    }

    private func jump(to pageIndex: Int) {
        guard viewModel.pageCount > 0 else { return }
        onJumpToPage(min(max(0, pageIndex), viewModel.pageCount - 1))
        syncControls()
    }

    private func syncControls() {
        let page = min(max(1, viewModel.currentPageIndex + 1), max(1, viewModel.pageCount))
        pageText = String(page)
        sliderPage = Double(page)
    }
}

private extension View {
    func mangaGlassNumericField() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(
                .regular.interactive(),
                in: .rect(cornerRadius: 10)
            )
    }
}

private struct MangaPagedReader: View {
    private static let contentInset: CGFloat = 12

    let viewModel: MangaReaderViewModel
    let ocrRegions: [Int: [MangaOCRTextRegion]]
    let showsOCRSelection: Bool
    let onSetCover: ((Int) -> Void)?
    let onDismissOCRSelection: () -> Void
    let onOCRSelection: (MangaOCRTextRegion, CGRect) -> Int?

    var body: some View {
        GeometryReader { proxy in
            MangaAsyncSpread(
                viewModel: viewModel,
                pages: viewModel.displayedPages
            ) { images in
                MangaZoomableCanvas(
                    images: images,
                    pageIndices: viewModel.displayedPageIndices,
                    sourcePageIndices: viewModel.displayedPages.map(
                        \.sourcePageIndex
                    ),
                    ocrRegions: ocrRegions,
                    showsOCRSelection: showsOCRSelection,
                    zoomScale: viewModel.zoomScale,
                    onSetCover: onSetCover,
                    onZoomScaleChange: { scale in
                        viewModel.zoomPercentage = Int((scale * 100).rounded())
                    },
                    onWheelNavigation: { navigation in
                        switch navigation {
                        case .backward:
                            viewModel.goBackward()
                        case .forward:
                            viewModel.goForward()
                        }
                    },
                    onDismissOCRSelection: onDismissOCRSelection,
                    onOCRSelection: { region, rect in
                        onOCRSelection(
                            region,
                            rect.offsetBy(
                                dx: Self.contentInset,
                                dy: Self.contentInset
                            )
                        )
                    }
                )
            }
            .padding(Self.contentInset)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
        }
    }
}

private struct MangaAsyncSpread<Content: View>: View {
    let viewModel: MangaReaderViewModel
    let pages: [MangaPresentationPage]
    @ViewBuilder let content: ([NSImage]) -> Content

    @State private var images: [NSImage] = []

    var body: some View {
        Group {
            if images.count == pages.count {
                content(images)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: pages) {
            images = []
            var loadedImages: [NSImage] = []
            for page in pages {
                guard let image = await viewModel.renderedImage(for: page),
                      !Task.isCancelled else {
                    return
                }
                loadedImages.append(image)
            }
            images = loadedImages
        }
    }
}

private struct MangaContinuousReader: View {
    let viewModel: MangaReaderViewModel
    @Binding var scrollPosition: Int?
    let popupCoordinateSpace: MangaReaderPopupCoordinateSpace
    let showsOCRSelection: Bool
    let onSetCover: ((Int) -> Void)?
    let onDismissOCRSelection: () -> Void
    let onOCRSelection: (MangaOCRTextRegion, CGRect) -> Int?

    @State private var visiblePageIndex: Int?
    @State private var requestedScrollTarget: Int?

    var body: some View {
        GeometryReader { geometry in
            let basePageWidth = min(max(320, geometry.size.width - 24), 1_400)
            let pageWidth = basePageWidth * viewModel.zoomScale

            ScrollViewReader { scrollProxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.presentationPages) { page in
                            MangaAsyncPage(viewModel: viewModel, page: page) { image in
                                MangaContinuousPageCanvas(
                                    image: image,
                                    pageIndex: page.index,
                                    sourcePageIndex: page.sourcePageIndex,
                                    ocrRegions: viewModel.lookupRegions(for: page),
                                    showsOCRSelection: showsOCRSelection,
                                    popupCoordinateSpace: popupCoordinateSpace,
                                    zoomScale: viewModel.zoomScale,
                                    onZoomScaleChange: { scale in
                                        viewModel.zoomPercentage = Int((scale * 100).rounded())
                                    },
                                    onSetCover: onSetCover,
                                    onDismissOCRSelection: onDismissOCRSelection,
                                    onOCRSelection: onOCRSelection
                                )
                                    .frame(width: pageWidth)
                                    .aspectRatio(
                                        image.size.width / max(image.size.height, 1),
                                        contentMode: .fit
                                    )
                            }
                            .id(page.index)
                            .frame(width: pageWidth)
                            .frame(minHeight: 160)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: MangaContinuousPageFramePreferenceKey.self,
                                        value: [
                                            page.index: proxy.frame(
                                                in: .named(MangaContinuousPageFramePreferenceKey.coordinateSpace)
                                            ),
                                        ]
                                    )
                                }
                            }
                            .task(id: viewModel.lookupRequestID(for: page)) {
                                await viewModel.loadOCRRegions(
                                    for: [page.sourcePageIndex]
                                )
                            }
                        }
                    }
                    .frame(
                        width: max(geometry.size.width, pageWidth + 24),
                        alignment: .top
                    )
                }
                .coordinateSpace(name: MangaContinuousPageFramePreferenceKey.coordinateSpace)
                .onPreferenceChange(MangaContinuousPageFramePreferenceKey.self) { frames in
                    guard let pageIndex = topVisiblePageIndex(
                        in: frames,
                        viewportHeight: geometry.size.height
                    ) else {
                        return
                    }
                    if let requestedScrollTarget {
                        guard pageIndex == requestedScrollTarget else { return }
                        self.requestedScrollTarget = nil
                    }
                    visiblePageIndex = pageIndex
                    if scrollPosition != pageIndex {
                        scrollPosition = pageIndex
                    }
                    viewModel.go(to: pageIndex)
                }
                .onChange(of: scrollPosition) { _, pageIndex in
                    guard let pageIndex, pageIndex != visiblePageIndex else { return }
                    requestedScrollTarget = pageIndex
                    scrollProxy.scrollTo(pageIndex, anchor: .top)
                }
                .onAppear {
                    guard let pageIndex = scrollPosition else { return }
                    requestedScrollTarget = pageIndex
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(pageIndex, anchor: .top)
                    }
                }
            }
        }
        .background(Color.black)
    }

    private func topVisiblePageIndex(
        in frames: [Int: CGRect],
        viewportHeight: CGFloat
    ) -> Int? {
        let visibleFrames = frames.filter {
            $0.value.maxY > 0 && $0.value.minY < viewportHeight
        }
        if let crossingTop = visibleFrames
            .filter({ $0.value.minY <= 1 && $0.value.maxY > 1 })
            .max(by: { $0.value.minY < $1.value.minY }) {
            return crossingTop.key
        }
        return visibleFrames.min(by: {
            abs($0.value.minY) < abs($1.value.minY)
        })?.key
    }
}

private struct MangaContinuousPageFramePreferenceKey: PreferenceKey {
    static let coordinateSpace = "manga-continuous-pages"
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect],
        nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

@MainActor
private final class MangaReaderPopupCoordinateSpace {
    weak var rootView: NSView?

    func topLeadingRect(_ rect: CGRect, from sourceView: NSView) -> CGRect {
        guard let rootView,
              sourceView.window === rootView.window else {
            return rect
        }
        let converted = rootView.convert(rect, from: sourceView)
        let y = rootView.isFlipped
            ? converted.minY
            : rootView.bounds.height - converted.maxY
        return CGRect(
            x: converted.minX,
            y: y,
            width: converted.width,
            height: converted.height
        )
    }
}

private struct MangaReaderCoordinateSpaceReader: NSViewRepresentable {
    let coordinateSpace: MangaReaderPopupCoordinateSpace

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        coordinateSpace.rootView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        coordinateSpace.rootView = view
    }
}

private struct MangaContinuousPageCanvas: NSViewRepresentable {
    let image: NSImage
    let pageIndex: Int
    let sourcePageIndex: Int
    let ocrRegions: [MangaOCRTextRegion]
    let showsOCRSelection: Bool
    let popupCoordinateSpace: MangaReaderPopupCoordinateSpace
    let zoomScale: Double
    let onZoomScaleChange: (Double) -> Void
    let onSetCover: ((Int) -> Void)?
    let onDismissOCRSelection: () -> Void
    let onOCRSelection: (MangaOCRTextRegion, CGRect) -> Int?

    func makeNSView(context: Context) -> MangaSpreadDocumentView {
        let view = MangaSpreadDocumentView()
        view.setFitsSinglePageToBounds()
        return view
    }

    func updateNSView(_ view: MangaSpreadDocumentView, context: Context) {
        view.setImages(
            [image],
            pageIndices: [pageIndex],
            sourcePageIndices: [sourcePageIndex]
        )
        view.setOCRRegions(
            [pageIndex: ocrRegions],
            pageIndices: [pageIndex],
            showsSelection: showsOCRSelection,
            onDismissSelection: onDismissOCRSelection,
            onSelection: { [weak view] region, documentRect in
                guard let view else { return nil }
                return onOCRSelection(
                    region,
                    popupCoordinateSpace.topLeadingRect(
                        documentRect,
                        from: view
                    )
                )
            }
        )
        view.configureContinuousZoom(
            scale: zoomScale,
            onScaleChange: onZoomScaleChange
        )
        view.onSetCover = onSetCover
    }
}

private struct MangaAsyncPage<Content: View>: View {
    let viewModel: MangaReaderViewModel
    let page: MangaPresentationPage
    @ViewBuilder let content: (NSImage) -> Content

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: page) {
            image = nil
            guard let renderedImage = await viewModel.renderedImage(for: page),
                  !Task.isCancelled else {
                return
            }
            image = renderedImage
        }
    }
}

private struct MangaZoomableCanvas: NSViewRepresentable {
    let images: [NSImage]
    let pageIndices: [Int]
    let sourcePageIndices: [Int]
    let ocrRegions: [Int: [MangaOCRTextRegion]]
    let showsOCRSelection: Bool
    let zoomScale: Double
    let onSetCover: ((Int) -> Void)?
    let onZoomScaleChange: (Double) -> Void
    let onWheelNavigation: (MangaWheelNavigation) -> Void
    let onDismissOCRSelection: () -> Void
    let onOCRSelection: (MangaOCRTextRegion, CGRect) -> Int?

    func makeNSView(context: Context) -> MangaZoomScrollView {
        MangaZoomScrollView()
    }

    func updateNSView(_ scrollView: MangaZoomScrollView, context: Context) {
        scrollView.setContent(
            images: images,
            pageIndices: pageIndices,
            sourcePageIndices: sourcePageIndices,
            ocrRegions: ocrRegions,
            showsOCRSelection: showsOCRSelection,
            zoomScale: zoomScale,
            onSetCover: onSetCover,
            onZoomScaleChange: onZoomScaleChange,
            onWheelNavigation: onWheelNavigation,
            onDismissOCRSelection: onDismissOCRSelection,
            onOCRSelection: onOCRSelection
        )
    }
}

private final class MangaZoomScrollView: NSScrollView {
    private static let wheelNavigationCooldown: TimeInterval = 0.25

    private let spreadView = MangaSpreadDocumentView()
    private var wheelNavigationAccumulator = MangaWheelNavigationAccumulator()
    private var representedImages: [NSImage] = []
    private var lastViewportSize: NSSize = .zero
    private var lastAppliedFitMagnification: CGFloat?
    private var lastWheelNavigationTime: TimeInterval = -.infinity
    private var isUpdatingFit = false
    private var requestedZoomScale: CGFloat = 1
    private var onZoomScaleChange: ((Double) -> Void)?
    private var onWheelNavigation: ((MangaWheelNavigation) -> Void)?
    private var onDismissOCRSelection: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let centeredClipView = MangaCenteredClipView()
        centeredClipView.onBlankAreaMouseDown = { [weak self] in
            self?.onDismissOCRSelection?()
        }
        contentView = centeredClipView
        drawsBackground = true
        backgroundColor = .black
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.1
        maxMagnification = 8
        documentView = spreadView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard !representedImages.isEmpty, !isUpdatingFit else { return }
        let viewportSize = contentSize
        guard viewportSize.width > 0, viewportSize.height > 0,
              viewportSize != lastViewportSize else {
            return
        }
        let shouldFollowFit = lastAppliedFitMagnification.map {
            abs(magnification - $0) < 0.002
        } ?? true
        lastViewportSize = viewportSize
        updateFitMagnification(apply: shouldFollowFit)
    }

    override func scrollWheel(with event: NSEvent) {
        let zoomModifiers: NSEvent.ModifierFlags = [.command, .control]
        if !event.modifierFlags.intersection(zoomModifiers).isEmpty,
           event.modifierFlags.intersection([.option, .shift]).isEmpty,
           handleModifierWheelZoom(event) {
            return
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            wheelNavigationAccumulator.reset()
            super.scrollWheel(with: event)
            return
        }
        guard !event.hasPreciseScrollingDeltas else {
            wheelNavigationAccumulator.reset()
            super.scrollWheel(with: event)
            return
        }
        guard MangaWheelNavigationResolver.navigation(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: false
        ) != nil else {
            wheelNavigationAccumulator.reset()
            super.scrollWheel(with: event)
            return
        }
        guard event.timestamp - lastWheelNavigationTime >= Self.wheelNavigationCooldown else {
            wheelNavigationAccumulator.reset()
            return
        }
        guard let navigation = wheelNavigationAccumulator.consume(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        ) else {
            return
        }

        lastWheelNavigationTime = event.timestamp
        onDismissOCRSelection?()
        onWheelNavigation?(navigation)
    }

    func setContent(
        images: [NSImage],
        pageIndices: [Int],
        sourcePageIndices: [Int],
        ocrRegions: [Int: [MangaOCRTextRegion]],
        showsOCRSelection: Bool,
        zoomScale: Double,
        onSetCover: ((Int) -> Void)?,
        onZoomScaleChange: @escaping (Double) -> Void,
        onWheelNavigation: @escaping (MangaWheelNavigation) -> Void,
        onDismissOCRSelection: @escaping () -> Void,
        onOCRSelection: @escaping (MangaOCRTextRegion, CGRect) -> Int?
    ) {
        let nextZoomScale = CGFloat(zoomScale)
        let zoomChanged = abs(requestedZoomScale - nextZoomScale) > 0.001
        requestedZoomScale = nextZoomScale
        self.onZoomScaleChange = onZoomScaleChange
        self.onWheelNavigation = onWheelNavigation
        self.onDismissOCRSelection = onDismissOCRSelection
        spreadView.onSetCover = onSetCover
        spreadView.setOCRRegions(
            ocrRegions,
            pageIndices: pageIndices,
            showsSelection: showsOCRSelection,
            onDismissSelection: onDismissOCRSelection,
            onSelection: { [weak self] region, documentRect in
                guard let self else { return nil }
                let localRect = self.convert(
                    documentRect,
                    from: self.spreadView
                )
                let localY = self.isFlipped
                    ? localRect.minY
                    : self.bounds.height - localRect.maxY
                let topLeadingRect = CGRect(
                    x: localRect.minX,
                    y: localY,
                    width: localRect.width,
                    height: localRect.height
                )
                return onOCRSelection(region, topLeadingRect)
            }
        )
        let imagesChanged = !images.isEmpty
            && (representedImages.count != images.count
                || !zip(representedImages, images).allSatisfy({ $0.0 === $0.1 }))
        guard imagesChanged || zoomChanged else {
            return
        }
        if imagesChanged {
            wheelNavigationAccumulator.reset()
            representedImages = images
            spreadView.setImages(
                images,
                pageIndices: pageIndices,
                sourcePageIndices: sourcePageIndices
            )
        }
        layoutSubtreeIfNeeded()
        lastViewportSize = contentSize
        updateFitMagnification(apply: true)
    }

    private func handleModifierWheelZoom(_ event: NSEvent) -> Bool {
        let imageSize = spreadView.frame.size
        let viewportSize = contentSize
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return false
        }
        let fit = min(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        let currentScale = Double(magnification / max(fit, 0.001))
        guard let targetScale = MangaWheelZoomResolver.scale(
            currentScale: currentScale,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        ) else {
            return false
        }

        let pointInClipView = contentView.convert(event.locationInWindow, from: nil)
        let pointInDocument = spreadView.convert(pointInClipView, from: contentView)
        let targetMagnification = fit * CGFloat(targetScale)
        requestedZoomScale = CGFloat(targetScale)
        lastAppliedFitMagnification = targetMagnification
        setMagnification(targetMagnification, centeredAt: pointInDocument)
        onDismissOCRSelection?()
        onZoomScaleChange?(targetScale)
        return true
    }

    private func updateFitMagnification(apply: Bool) {
        let imageSize = spreadView.frame.size
        let viewportSize = contentSize
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }
        let fit = min(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        let target = fit * requestedZoomScale
        maxMagnification = max(8, fit * 2)
        minMagnification = fit * 0.5
        lastAppliedFitMagnification = target
        guard apply else {
            contentView.needsDisplay = true
            return
        }
        isUpdatingFit = true
        setMagnification(target, centeredAt: NSPoint(
            x: imageSize.width / 2,
            y: imageSize.height / 2
        ))
        isUpdatingFit = false
        contentView.needsDisplay = true
    }
}

private final class MangaSpreadDocumentView: NSView {
    private struct ContextPage {
        let index: Int
        let image: NSImage
        let frame: CGRect
    }

    private struct DisplayRegion {
        let region: MangaOCRTextRegion
        let rect: NSRect
    }

    private static let pageSpacing: CGFloat = 8
    private var images: [NSImage] = []
    private var pageIndices: [Int] = []
    private var sourcePageIndices: [Int] = []
    private var ocrRegions: [Int: [MangaOCRTextRegion]] = [:]
    private var displayRegions: [DisplayRegion] = []
    private var selectedRegionID: String?
    private var selectedMatchedLength = 0
    private var hoveredRegionID: String?
    private var onSelection: ((MangaOCRTextRegion, CGRect) -> Int?)?
    private var onDismissSelection: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var pageImageViews: [NSImageView] = []
    private var fitsSinglePageToBounds = false
    private var lastLayoutSize: NSSize = .zero
    private var contextPage: ContextPage?
    private var contextMenuAnchor = CGRect.zero
    private var sharingPicker: NSSharingServicePicker?
    private var continuousZoomScale: Double?
    private var onContinuousZoomScaleChange: ((Double) -> Void)?
    var onSetCover: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func setFitsSinglePageToBounds() {
        fitsSinglePageToBounds = true
    }

    func configureContinuousZoom(
        scale: Double,
        onScaleChange: @escaping (Double) -> Void
    ) {
        continuousZoomScale = scale
        onContinuousZoomScaleChange = onScaleChange
    }

    func setImages(
        _ images: [NSImage],
        pageIndices: [Int],
        sourcePageIndices: [Int]
    ) {
        let imagesChanged = self.images.count != images.count
            || !zip(self.images, images).allSatisfy { $0.0 === $0.1 }
        guard imagesChanged
                || self.pageIndices != pageIndices
                || self.sourcePageIndices != sourcePageIndices else {
            return
        }
        self.images = images
        self.pageIndices = pageIndices
        self.sourcePageIndices = sourcePageIndices
        if !fitsSinglePageToBounds {
            let width = images.reduce(0) { $0 + $1.size.width }
                + Self.pageSpacing * CGFloat(max(0, images.count - 1))
            let height = images.map(\.size.height).max() ?? 0
            frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        rebuildPageImageViews()
        rebuildDisplayRegions()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard fitsSinglePageToBounds,
              bounds.size != lastLayoutSize else {
            return
        }
        lastLayoutSize = bounds.size
        rebuildPageImageViews()
        rebuildDisplayRegions()
        needsDisplay = true
    }

    func setOCRRegions(
        _ regions: [Int: [MangaOCRTextRegion]],
        pageIndices: [Int],
        showsSelection: Bool,
        onDismissSelection: @escaping () -> Void,
        onSelection: @escaping (MangaOCRTextRegion, CGRect) -> Int?
    ) {
        ocrRegions = regions
        self.pageIndices = pageIndices
        self.onSelection = onSelection
        self.onDismissSelection = onDismissSelection
        if regions.isEmpty || !showsSelection {
            selectedRegionID = nil
            selectedMatchedLength = 0
        }
        rebuildDisplayRegions()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !displayRegions.isEmpty else { return }
        drawOCRTextOverlay()
    }

    override func scrollWheel(with event: NSEvent) {
        let zoomModifiers: NSEvent.ModifierFlags = [.command, .control]
        guard let continuousZoomScale,
              !event.modifierFlags.intersection(zoomModifiers).isEmpty,
              event.modifierFlags.intersection([.option, .shift]).isEmpty,
              let targetScale = MangaWheelZoomResolver.scale(
                  currentScale: continuousZoomScale,
                  deltaX: event.scrollingDeltaX,
                  deltaY: event.scrollingDeltaY,
                  hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
              ) else {
            super.scrollWheel(with: event)
            return
        }
        self.continuousZoomScale = targetScale
        onDismissSelection?()
        onContinuousZoomScaleChange?(targetScale)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hitSlop = 4 / max(enclosingScrollView?.magnification ?? 1, 0.01)
        guard let displayRegion = displayRegions
            .filter({ $0.rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) })
            .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) else {
            selectedRegionID = nil
            selectedMatchedLength = 0
            onDismissSelection?()
            needsDisplay = true
            super.mouseDown(with: event)
            return
        }
        selectedRegionID = displayRegion.region.id
        let anchorRect = blockRect(for: displayRegion.region)
        selectedMatchedLength = onSelection?(displayRegion.region, anchorRect) ?? 0
        if selectedMatchedLength == 0 {
            selectedRegionID = nil
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(at: point),
              let window = event.window,
              let scrollView = ancestorScrollView else {
            super.rightMouseDown(with: event)
            return
        }

        let initialLocation = event.locationInWindow
        var previousLocation = initialLocation
        var isDragging = false
        while let nextEvent = window.nextEvent(
            matching: [.rightMouseDragged, .rightMouseUp]
        ) {
            switch nextEvent.type {
            case .rightMouseDragged:
                let location = nextEvent.locationInWindow
                if !isDragging {
                    let distance = hypot(
                        location.x - initialLocation.x,
                        location.y - initialLocation.y
                    )
                    if distance >= 4 {
                        isDragging = true
                        NSCursor.closedHand.push()
                        onDismissSelection?()
                    }
                }
                if isDragging {
                    pan(
                        scrollView,
                        windowDelta: CGPoint(
                            x: location.x - previousLocation.x,
                            y: location.y - previousLocation.y
                        )
                    )
                }
                previousLocation = location
            case .rightMouseUp:
                if isDragging {
                    NSCursor.pop()
                } else {
                    showContextMenu(for: page, event: event)
                }
                return
            default:
                continue
            }
        }
        if isDragging {
            NSCursor.pop()
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextHoveredID = hitRegion(at: point)?.region.id
        guard nextHoveredID != hoveredRegionID else { return }
        hoveredRegionID = nextHoveredID
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredRegionID != nil else { return }
        hoveredRegionID = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for displayRegion in displayRegions {
            addCursorRect(displayRegion.rect, cursor: .pointingHand)
        }
    }

    private func rebuildDisplayRegions() {
        var regions: [DisplayRegion] = []
        for (offset, pageFrame) in pageFrames.enumerated() {
            guard pageIndices.indices.contains(offset) else { continue }
            let pageIndex = pageIndices[offset]
            for region in ocrRegions[pageIndex] ?? [] {
                let normalized = region.normalizedBounds
                let rect = CGRect(
                    x: pageFrame.minX + normalized.minX * pageFrame.width,
                    y: pageFrame.minY + (1 - normalized.maxY) * pageFrame.height,
                    width: normalized.width * pageFrame.width,
                    height: normalized.height * pageFrame.height
                )
                guard rect.width > 0, rect.height > 0 else { continue }
                regions.append(DisplayRegion(region: region, rect: rect))
            }
        }
        displayRegions = regions
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
    }

    private func rebuildPageImageViews() {
        pageImageViews.forEach { $0.removeFromSuperview() }
        pageImageViews = []
        for (image, pageFrame) in zip(images, pageFrames) {
            let imageView = NSImageView(frame: pageFrame)
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageAlignment = .alignCenter
            addSubview(imageView)
            pageImageViews.append(imageView)
        }
    }

    private func page(at point: CGPoint) -> ContextPage? {
        for offset in pageFrames.indices where pageFrames[offset].contains(point) {
            guard images.indices.contains(offset),
                  sourcePageIndices.indices.contains(offset) else {
                continue
            }
            return ContextPage(
                index: sourcePageIndices[offset],
                image: images[offset],
                frame: pageFrames[offset]
            )
        }
        return nil
    }

    private var ancestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return enclosingScrollView
    }

    private func pan(_ scrollView: NSScrollView, windowDelta: CGPoint) {
        let scale = max(scrollView.magnification, 0.01)
        var origin = scrollView.contentView.bounds.origin
        origin.x -= windowDelta.x / scale
        if scrollView.documentView?.isFlipped == true {
            origin.y += windowDelta.y / scale
        } else {
            origin.y -= windowDelta.y / scale
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func showContextMenu(for page: ContextPage, event: NSEvent) {
        contextPage = page
        let point = convert(event.locationInWindow, from: nil)
        contextMenuAnchor = CGRect(x: point.x, y: point.y, width: 1, height: 1)

        let menu = NSMenu()
        menu.addItem(menuItem(
            title: String(localized: "Copy Page Image"),
            systemImage: "document.on.document",
            action: #selector(copyPageImage)
        ))
        menu.addItem(menuItem(
            title: String(localized: "Save Page Image…"),
            systemImage: "square.and.arrow.down",
            action: #selector(savePageImage)
        ))
        menu.addItem(menuItem(
            title: String(localized: "Share Page Image…"),
            systemImage: "square.and.arrow.up",
            action: #selector(sharePageImage)
        ))
        if onSetCover != nil {
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: String(localized: "Set as Manga Cover"),
                systemImage: "photo.badge.checkmark",
                action: #selector(setAsCover)
            ))
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func menuItem(
        title: String,
        systemImage: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        return item
    }

    @objc private func copyPageImage() {
        guard let image = contextPage?.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    @objc private func savePageImage() {
        guard let contextPage,
              let tiffData = contextPage.image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:]) else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let pageName = String(
            format: String(localized: "Page %lld"),
            Int64(contextPage.index + 1)
        )
        panel.nameFieldStringValue = "\(pageName).png"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try pngData.write(to: url, options: .atomic)
            } catch {
                NSApplication.shared.presentError(error)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc private func sharePageImage() {
        guard let image = contextPage?.image else { return }
        let picker = NSSharingServicePicker(items: [image])
        sharingPicker = picker
        picker.show(
            relativeTo: contextMenuAnchor,
            of: self,
            preferredEdge: .minY
        )
    }

    @objc private func setAsCover() {
        guard let pageIndex = contextPage?.index else { return }
        onSetCover?(pageIndex)
    }

    private var pageFrames: [CGRect] {
        if fitsSinglePageToBounds, let image = images.first {
            let widthScale = bounds.width / max(image.size.width, 1)
            let heightScale = bounds.height / max(image.size.height, 1)
            let scale = min(widthScale, heightScale)
            let size = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            return [CGRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )]
        }

        var frames: [CGRect] = []
        var x: CGFloat = 0
        for image in images {
            frames.append(CGRect(
                x: x,
                y: (bounds.height - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height
            ))
            x += image.size.width + Self.pageSpacing
        }
        return frames
    }

    /// Mirrors Mangatan/Chimahon's native canvas behavior: passive OCR regions
    /// remain invisible, while hovering or tapping reveals the complete OCR
    /// paragraph and the dictionary match receives a restrained accent highlight.
    private func hitRegion(at point: CGPoint) -> DisplayRegion? {
        let hitSlop = 4 / max(enclosingScrollView?.magnification ?? 1, 0.01)
        return displayRegions
            .filter({ $0.rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) })
            .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })
    }

    private func blockRect(for region: MangaOCRTextRegion) -> CGRect {
        displayRegions
            .lazy
            .filter {
                $0.region.pageIndex == region.pageIndex
                    && $0.region.blockID == region.blockID
            }
            .map(\.rect)
            .reduce(CGRect.null) { $0.union($1) }
    }

    private func drawOCRTextOverlay() {
        let visibleRegionID = selectedRegionID ?? hoveredRegionID
        guard let selected = displayRegions.first(where: {
            $0.region.id == visibleRegionID
        }) else {
            return
        }
        let activeRegions = displayRegions
            .filter {
                $0.region.pageIndex == selected.region.pageIndex
                    && $0.region.blockID == selected.region.blockID
            }
            .sorted { $0.region.utf16Offset < $1.region.utf16Offset }
        let matchRange = NSRange(
            location: selected.region.utf16Offset,
            length: selectedRegionID == nil ? 0 : selectedMatchedLength
        )
        let sentence = selected.region.sentence as NSString

        let lines = Dictionary(grouping: activeRegions, by: \.region.lineID)
            .values
            .sorted {
                ($0.map(\.region.utf16Offset).min() ?? 0)
                    < ($1.map(\.region.utf16Offset).min() ?? 0)
            }
        for lineRegions in lines {
            let ordered = lineRegions.sorted {
                $0.region.utf16Offset < $1.region.utf16Offset
            }
            guard let first = ordered.first,
                  let last = ordered.last else {
                continue
            }
            let lineRect = ordered
                .map(\.rect)
                .reduce(CGRect.null) { $0.union($1) }
            guard !lineRect.isNull, lineRect.width > 0, lineRect.height > 0 else {
                continue
            }

            NSColor.white.withAlphaComponent(0.72).setFill()
            NSBezierPath(rect: lineRect).fill()
            for displayRegion in ordered {
                let characterRange = sentence.rangeOfComposedCharacterSequence(
                    at: displayRegion.region.utf16Offset
                )
                if NSIntersectionRange(characterRange, matchRange).length > 0 {
                    NSColor.controlAccentColor.withAlphaComponent(0.45).setFill()
                    NSBezierPath(rect: displayRegion.rect).fill()
                }
            }

            let lastRange = sentence.rangeOfComposedCharacterSequence(
                at: last.region.utf16Offset
            )
            let lineRange = NSRange(
                location: first.region.utf16Offset,
                length: NSMaxRange(lastRange) - first.region.utf16Offset
            )
            let lineText = sentence.substring(with: lineRange)
            if selected.region.isVertical {
                drawVerticalOCRText(
                    sentence: sentence,
                    regions: ordered
                )
            } else {
                drawHorizontalOCRText(lineText, in: lineRect)
            }
        }
    }

    private func drawHorizontalOCRText(_ text: String, in rect: CGRect) {
        guard !text.isEmpty else { return }
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .regular),
                .foregroundColor: NSColor.black,
            ]
        )
        let textSize = attributedText.size()
        guard textSize.width > 0, textSize.height > 0 else { return }
        let scale = min(rect.width / textSize.width, rect.height / textSize.height)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scale(by: scale)
        transform.translateX(by: -textSize.width / 2, yBy: -textSize.height / 2)
        transform.concat()
        attributedText.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawVerticalOCRText(
        sentence: NSString,
        regions: [DisplayRegion]
    ) {
        for displayRegion in regions {
            let offset = displayRegion.region.utf16Offset
            guard offset >= 0, offset < sentence.length else { continue }
            let characterRange = sentence.rangeOfComposedCharacterSequence(at: offset)
            let text = sentence.substring(with: characterRange)
            let rect = displayRegion.rect
            let fontSize = max(8, min(rect.width * 0.82, rect.height * 0.95))
            let attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                    .foregroundColor: NSColor.black,
                ]
            )
            let textSize = attributedText.size()
            attributedText.draw(at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ))
        }
    }
}

private final class MangaCenteredClipView: NSClipView {
    var onBlankAreaMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onBlankAreaMouseDown?()
        super.mouseDown(with: event)
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        if documentView.frame.width < bounds.width {
            bounds.origin.x = (documentView.frame.width - bounds.width) / 2
        }
        if documentView.frame.height < bounds.height {
            bounds.origin.y = (documentView.frame.height - bounds.height) / 2
        }
        return bounds
    }
}
