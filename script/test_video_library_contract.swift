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

private let rootView = try source("NativeMac/NativeMacRootView.swift")
private let sidebarView = try source("NativeMac/NativeMacSidebarView.swift")
private let detailView = try source("NativeMac/NativeMacDetailView.swift")
private let project = try source("Hoshi Reader.xcodeproj/project.pbxproj")
private let localization = try source("Localizable.xcstrings")
private let store = try source("Features/Video/VideoLibraryStore.swift")
private let thumbnailStore = try? source("Features/Video/VideoThumbnailStore.swift")
private let viewModel = try source("Features/Video/VideoLibraryViewModel.swift")
private let playerScreen = try source("Features/Video/VideoPlayerScreen.swift")
private let buildScript = try source("script/build_and_run_native.sh")
private let manualFixtureScript = try? source("script/verify_video_library_manual_fixture.sh")

require(
    !rootView.contains("isSelectingVideoFile")
        && !rootView.contains("lastNonVideoSection")
        && !rootView.contains("handleVideoFileImport")
        && !rootView.contains("VideoMediaTypes.contentTypes")
        && !rootView.contains("selection = lastNonVideoSection")
        && !rootView.contains("return lastNonVideoSection"),
    "Video sidebar selection should render the library page instead of immediately opening the file picker"
)
require(
    sidebarView.contains("List(selection: $selection)")
        && sidebarView.contains("ForEach(NativeMacSection.allCases)")
        && sidebarView.contains("HStack(spacing: 10)")
        && sidebarView.contains(".tag(section)")
        && sidebarView.contains(".listStyle(.sidebar)")
        && !sidebarView.contains("private func sidebarButton")
        && !sidebarView.contains(".buttonStyle(.plain)")
        && !sidebarView.contains(".accessibilityAction"),
    "Native main sidebar should keep the system List sidebar style from v0.6.0beta7 while Video selection renders the detail page"
)
require(
    detailView.contains("case .video:")
        && detailView.contains("VideoLibraryView(")
        && !detailView.contains("case .video:\n                EmptyView()"),
    "Native detail should render VideoLibraryView for the Video section"
)
require(
    detailView.contains("let onOpenVideo: (URL, URL?) -> Void")
        && rootView.contains("private func openVideoWindow(with url: URL, subtitleURL: URL? = nil)")
        && rootView.contains("VideoWindowPresenter.shared.open(")
        && rootView.contains("subtitleURL: subtitleURL")
        && rootView.contains("coordinator: videoWindowCoordinator"),
    "Native Video library open routing should carry an optional bound subtitle into the dedicated player window"
)
require(
    rootView.contains(".toolbar(.visible, for: .windowToolbar)")
        && !rootView.contains(".toolbar(.hidden, for: .windowToolbar)")
        && !rootView.contains("isWindowToolbarVisible ? .visible : .hidden")
        && !rootView.contains("if selectedSection == .video {\n            return false\n        }"),
    "Video library should keep the native window toolbar visible so traffic lights and the sidebar toggle remain available"
)
require(
    buildScript.contains("INSTANCE_ID=\"${HOSHI_APP_INSTANCE_ID:-}\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"${HOSHI_DERIVED_DATA_PATH:-}\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"$ROOT_DIR/.build/xcode-derived-data-$INSTANCE_ID\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"$ROOT_DIR/.build/xcode-derived-data\"")
        && buildScript.contains("-scheme \"$SCHEME_NAME\"")
        && buildScript.contains("-sdk macosx")
        && buildScript.contains("-derivedDataPath \"$DERIVED_DATA_PATH\"")
        && buildScript.contains("APP_BUNDLE=\"$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app\"")
        && buildScript.contains("matching_app_pids()")
        && !buildScript.contains("pkill -x \"$APP_NAME\"")
        && !buildScript.contains("-showBuildSettings")
        && !buildScript.contains("-destination \"generic/platform=macOS\"")
        && !buildScript.contains("simctl")
        && !buildScript.contains("DERIVED_DATA_GLOB")
        && !buildScript.contains("ls -dt $DERIVED_DATA_GLOB"),
    "build_and_run_native.sh should build macOS natively without simulator/device enumeration and launch the current project build product"
)
for file in [
    "Video/VideoLibraryStore.swift",
    "Video/VideoLibraryViewModel.swift",
    "Video/VideoLibraryView.swift",
] {
    require(project.contains(file), "project membership exceptions should include \(file)")
}
require(
    project.contains("Video/VideoThumbnailStore.swift"),
    "project membership exceptions should include the restored thumbnail store"
)
for key in [
    "Add Video Folder",
    "Add Smart Collection",
    "%@ left",
    "Clear Progress",
    "Continue Watching",
    "No Videos in Progress",
    "No Video Folders",
    "Partially watched videos will appear here.",
    "Play from Beginning",
    "Recent",
    "All Videos",
    "Folders",
    "Finished",
    "Mark as Watched",
    "Manage Sources",
    "Manual",
    "Missing",
    "Needs Review",
    "New Smart Collection",
    "No Videos Need Review",
    "Parent Folder",
    "Path",
    "Preview Matches",
    "Reveal in Finder",
    "Reveal Source in Finder",
    "Rule Field",
    "Rule Text",
    "Search Videos",
    "Smart",
    "Smart Collections",
    "Sort Videos",
    "Tag",
    "Unfinished",
    "Unwatched",
    "Watched",
    "%d in progress",
    "%d missing",
    "%d videos",
    "Last Scanned",
    "Add Collection",
    "Auto Subtitle",
    "Bind Subtitle",
    "Bound Subtitle",
    "Clear Selected Progress",
    "Clear Subtitle",
    "Collection Actions",
    "Collections",
    "Delete Collection",
    "Delete Collection?",
    "Details",
    "Display Title",
    "Favorite",
    "Favorite videos will appear here.",
    "Favorites",
    "List",
    "Mark Selected Watched",
    "Missing videos will appear here until their source is refreshed.",
    "Never scanned",
    "New Collection",
    "No Favorite Videos",
    "No Finished Videos",
    "No Missing Videos",
    "No Matching Videos",
    "No Unwatched Videos",
    "Organization",
    "Posters",
    "Remove Missing",
    "Save Metadata",
    "Refresh Source",
    "Refresh",
    "Remove",
    "Select a video to edit its local metadata.",
    "Series",
    "Untitled Collection",
    "Video Sources",
    "Video Library View",
    "Video Details",
    "Try a different search or filter.",
    "This removes the collection but keeps its videos in your library.",
    "Videos marked watched will appear here.",
    "Videos without playback progress will appear here.",
    "Videos outside manual and smart collections will appear here.",
] {
    require(localization.contains("\"\(key)\""), "Localizable.xcstrings should include \(key)")
}

let libraryView = try source("Features/Video/VideoLibraryView.swift")
if let contentRange = libraryView.range(of: "private var content: some View"),
   let contentEnd = libraryView[contentRange.lowerBound...].range(of: "private var libraryContent: some View")?.lowerBound {
    let contentBlock = libraryView[contentRange.lowerBound..<contentEnd]
    require(
        contentBlock.contains("VideoLibrarySidebarView(")
            && contentBlock.contains("viewModel: viewModel")
            && contentBlock.contains("VideoLibraryContentTitleBar(viewModel: viewModel)")
            && contentBlock.contains(".frame(width: 240)")
            && contentBlock.contains("NativeGlassPageBackground()")
            && !contentBlock.contains("VideoLibraryToolbarControls(viewModel: viewModel)")
            && !contentBlock.contains("VideoLibraryContentToolbar(viewModel: viewModel)")
            && !contentBlock.contains("onAddFolder: presentFolderImporter")
            && !contentBlock.contains("isReadyForSourceActions: isReadyForSourceActions")
            && !contentBlock.contains("ContentUnavailableView")
            && !contentBlock.contains("viewModel.isSelectingFolder = true"),
        "Video library shell should render a Settings-style secondary sidebar without a hard divider or top-level import prompt"
    )
} else {
    require(false, "Video library content shell should be present before libraryContent")
}
require(
    libraryView.contains("VideoLibrarySidebarView(")
        && libraryView.contains("viewModel: viewModel")
        && libraryView.contains("@State private var isReadyForSourceActions = false")
        && libraryView.contains("@State private var isManagingSources = false")
        && libraryView.contains("armSourceActions()")
        && libraryView.contains("onAddFolder: presentFolderImporter")
        && libraryView.contains("onManageSources: { isManagingSources = true }")
        && libraryView.contains(".sheet(isPresented: $isManagingSources)")
        && libraryView.contains("private func presentFolderImporter()")
        && libraryView.contains("guard isReadyForSourceActions else { return }")
        && libraryView.contains("NSOpenPanel()")
        && libraryView.contains("panel.canChooseDirectories = true")
        && libraryView.contains("panel.canChooseFiles = false")
        && libraryView.contains("panel.allowsMultipleSelection = true")
        && libraryView.contains("viewModel.addFolders(.success(panel.urls))")
        && !libraryView.contains("isPresented: $viewModel.isSelectingFolder")
        && !libraryView.contains("allowedContentTypes: [.folder]")
        && !viewModel.contains("var isSelectingFolder")
        && libraryView.contains("private struct VideoLibrarySidebarView")
        && libraryView.contains("List(selection: modeSelection)")
        && libraryView.contains("Section(\"Library\")")
        && libraryView.contains("Section(\"Organization\")")
        && libraryView.contains("VideoLibrarySourceToolbarButtons(")
        && !libraryView.contains("VideoLibrarySidebarSourceActions(")
        && !libraryView.contains(".safeAreaInset(edge: .bottom)")
        && !libraryView.contains("Text(\"Video Sources\")")
        && !libraryView.contains("Section(\"Video Sources\")")
        && libraryView.contains("sidebarRow(.continueWatching")
        && !libraryView.contains("VideoLibrarySidebarFilterToggle")
        && !libraryView.contains("Toggle(isOn: $viewModel.showUnfinishedOnly)")
        && !libraryView.contains("Label(\"Unfinished\"")
        && libraryView.contains("sidebarRow(.favorites")
        && libraryView.contains("sidebarRow(.series")
        && libraryView.contains("sidebarRow(.folders"),
    "Video library should keep browsing modes in a native secondary sidebar without the extra unfinished toggle row"
)
if let sourceActionsRange = libraryView.range(of: "private struct VideoLibrarySourceToolbarButtons"),
   let sourceActionsEnd = libraryView[sourceActionsRange.lowerBound...].range(of: "private struct VideoLibraryContentTitleBar")?.lowerBound {
    let sourceActions = libraryView[sourceActionsRange.lowerBound..<sourceActionsEnd]
    require(
        sourceActions.contains("HStack(spacing: 6)")
            && sourceActions.contains("Label(\"Refresh\"")
            && sourceActions.contains("Label(\"Add Video Folder\"")
            && sourceActions.contains("Label(\"Manage Sources\"")
            && sourceActions.contains("viewModel.refreshAllSources()")
            && sourceActions.contains("onAddFolder()")
            && sourceActions.contains("onManageSources()")
            && sourceActions.contains(".labelStyle(.iconOnly)")
            && sourceActions.contains(".buttonBorderShape(.circle)")
            && sourceActions.contains(".disabled(!viewModel.hasSources || viewModel.isScanning)")
            && sourceActions.contains(".disabled(!isReadyForSourceActions)")
            && sourceActions.contains(".disabled(!viewModel.hasSources)")
            && !sourceActions.contains(".buttonStyle(.borderless)")
            && !sourceActions.contains(".background(.thinMaterial)"),
        "Video source actions should be icon-only circular toolbar buttons without a custom material band"
    )
} else {
    require(false, "Video library source toolbar buttons should be present before the content title bar")
}
require(
    libraryView.contains("private struct VideoLibrarySourceToolbarButtons")
        && !libraryView.contains("private struct VideoLibrarySidebarSourceActions")
        && libraryView.contains("let onAddFolder: () -> Void")
        && libraryView.contains("let onManageSources: () -> Void")
        && libraryView.contains("let isReadyForSourceActions: Bool")
        && libraryView.contains("viewModel.refreshAllSources()")
        && libraryView.contains("Label(\"Refresh\"")
        && libraryView.contains("Label(\"Add Video Folder\"")
        && libraryView.contains("Label(\"Manage Sources\"")
        && libraryView.contains("onAddFolder()")
        && libraryView.contains("onManageSources()")
        && libraryView.contains(".disabled(!isReadyForSourceActions)")
        && !libraryView.contains("viewModel.isSelectingFolder = true"),
    "Video library source actions should live in native toolbar circular buttons instead of the secondary sidebar footer"
)
require(
    store.contains("enum VideoLibraryCollectionKind")
        && store.contains("struct VideoLibrarySmartRule")
        && store.contains("func createSmartCollection")
        && viewModel.contains("case needsReview")
        && viewModel.contains("func smartCollectionPreviewRows")
        && viewModel.contains("func createSmartCollection"),
    "Video library should include a lightweight smart collection model and Needs Review view-model support"
)
require(
    libraryView.contains("sidebarRow(.needsReview")
        && libraryView.contains("smartCollectionsSection")
        && libraryView.contains("Label(\"New Smart Collection\"")
        && libraryView.contains("Label(\"Add Smart Collection\"")
        && libraryView.contains("Text(\"Preview Matches\")")
        && libraryView.contains("VideoLibrarySmartRuleField"),
    "Video library UI should expose Needs Review and a first-pass smart collection editor"
)
require(
    viewModel.contains("var usesCollapsibleSections")
        && viewModel.contains("case .series, .folders, .collections:")
        && viewModel.contains("organization.folderPath")
        && libraryView.contains("@State private var expandedSectionIDs: Set<String> = []")
        && libraryView.contains("DisclosureGroup(isExpanded: sectionExpansionBinding(for: section))")
        && libraryView.contains("VideoLibraryDisclosureSectionLabel(")
        && libraryView.contains("count: section.rows.count"),
    "Video library grouped organization modes should support collapsible collection, series, and folder sections"
)
for forbidden in [
    "PythonKit",
    "import Python",
    "import JavaScriptCore",
    "node_modules",
    "Anitomy",
    "TMDb",
    "TVDb",
] {
    require(
        !store.contains(forbidden)
            && !viewModel.contains(forbidden)
            && !libraryView.contains(forbidden),
        "Video library smart collections should not introduce heavy parser or metadata dependencies: \(forbidden)"
    )
}
require(
    libraryView.contains(".toolbar {")
        && libraryView.contains("videoToolbarContent")
        && libraryView.contains("@ToolbarContentBuilder")
        && libraryView.contains("private var videoToolbarContent: some ToolbarContent")
        && libraryView.contains("ToolbarItemGroup(placement: .primaryAction)")
        && libraryView.contains("VideoLibrarySortToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibraryLayoutToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibrarySearchAndSourceToolbarControl(")
        && libraryView.contains("VideoLibrarySearchToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibrarySourceToolbarButtons(")
        && libraryView.contains("ToolbarSpacer(.fixed, placement: .primaryAction)")
        && libraryView.contains("VideoLibraryContentTitleBar(viewModel: viewModel)")
        && libraryView.contains("private struct VideoLibraryContentTitleBar")
        && libraryView.contains("Text(LocalizedStringKey(viewModel.displayMode.titleKey))")
        && libraryView.contains("TextField(\"Search Videos\"")
        && libraryView.contains("VideoLibrarySortPopUpButton(selection: $viewModel.sortOption)")
        && libraryView.contains("VideoLibraryLayoutSegmentedControl(selection: $viewModel.layoutMode)")
        && libraryView.contains("selection: $viewModel.layoutMode")
        && libraryView.contains("VideoLibrarySearchField(text: $viewModel.searchText)")
        && libraryView.contains("private struct VideoLibrarySortPopUpButton: NSViewRepresentable")
        && libraryView.contains("NSPopUpButton")
        && libraryView.contains("private struct VideoLibraryLayoutSegmentedControl: NSViewRepresentable")
        && libraryView.contains("NSSegmentedControl(")
        && !libraryView.contains("Picker(\"Video Layout\"")
        && !libraryView.contains("Picker(\"Sort Videos\"")
        && !libraryView.contains("private struct VideoLibraryToolbarControls")
        && !libraryView.contains("VideoLibraryToolbarControls(viewModel: viewModel)")
        && !libraryView.contains("private struct VideoLibraryContentToolbar")
        && !libraryView.contains("VideoLibraryContentToolbar(viewModel: viewModel)")
        && !libraryView.contains("VideoLibraryToolbarControlSurface")
        && !libraryView.contains("Picker(\"Video Library View\""),
    "Video library controls should keep sort, layout, search, and source actions in native toolbar groups with the beta9 native layout segmented control"
)
if let toolbarRange = libraryView.range(of: "private var videoToolbarContent: some ToolbarContent"),
   let toolbarEnd = libraryView[toolbarRange.lowerBound...].range(of: "@ViewBuilder\n    private var content")?.lowerBound {
    let toolbar = libraryView[toolbarRange.lowerBound..<toolbarEnd]
    let sortIndex = toolbar.range(of: "VideoLibrarySortToolbarControl(viewModel: viewModel)")?.lowerBound
    let layoutIndex = toolbar.range(of: "VideoLibraryLayoutToolbarControl(viewModel: viewModel)")?.lowerBound
    let searchAndSourceIndex = toolbar.range(of: "VideoLibrarySearchAndSourceToolbarControl(")?.lowerBound
    require(
        sortIndex != nil
            && layoutIndex != nil
            && searchAndSourceIndex != nil
            && sortIndex! < layoutIndex!
            && layoutIndex! < searchAndSourceIndex!,
        "Video library native toolbar groups should order sort, layout, then combined search/source actions"
    )
    require(
        toolbar.contains("ToolbarSpacer(.fixed, placement: .primaryAction)")
            && toolbar.contains("VideoLibraryLayoutToolbarControl(viewModel: viewModel)")
            && !toolbar.contains("showUnfinishedOnly")
            && !toolbar.contains("Label(\"Unfinished\"")
            && !toolbar.contains("HStack(spacing: 8) {")
            && !toolbar.contains("ScrollView(.horizontal")
            && !toolbar.contains("GlassEffectContainer(spacing: 8)")
            && !toolbar.contains("VideoLibraryToolbarControlSurface")
            && !toolbar.contains(".modifier(VideoLibraryHeaderGlassSurface())")
            && !toolbar.contains(".textFieldStyle(.roundedBorder)")
            && !toolbar.contains(".colorScheme(.dark)")
            && !toolbar.contains("Color(red: 0.08, green: 0.09, blue: 0.12)")
            && !toolbar.contains(".background(Color("),
        "Video library native toolbar should use separated system groups without adding one custom material strip"
    )
} else {
    require(false, "Video library native toolbar groups should be present before the section header surface")
}
require(
    libraryView.contains("private struct VideoLibrarySortToolbarControl")
        && libraryView.contains("private struct VideoLibraryLayoutToolbarControl")
        && libraryView.contains("private struct VideoLibrarySearchAndSourceToolbarControl")
        && libraryView.contains("private struct VideoLibrarySearchToolbarControl")
        && libraryView.contains("private struct VideoLibrarySortPopUpButton: NSViewRepresentable")
        && libraryView.contains("private struct VideoLibraryLayoutSegmentedControl: NSViewRepresentable")
        && libraryView.contains("NSSegmentedControl(")
        && libraryView.contains("trackingMode: .selectOne")
        && libraryView.contains("NSPopUpButton(frame: .zero, pullsDown: false)")
        && !libraryView.contains("NativeGlassSegmentedPicker(")
        && libraryView.contains("ToolbarItemGroup(placement: .primaryAction)")
        && libraryView.contains(".frame(minWidth: 90, idealWidth: 140, maxWidth: 180)")
        && !libraryView.contains("private struct VideoLibraryMediaToolbarSurface"),
    "Video library page header should use the beta9 native sort pop-up and AppKit layout segmented control"
)
if let combinedRange = libraryView.range(of: "private struct VideoLibrarySearchAndSourceToolbarControl"),
   let combinedEnd = libraryView[combinedRange.lowerBound...].range(of: "private struct VideoLibrarySearchToolbarControl")?.lowerBound {
    let combined = libraryView[combinedRange.lowerBound..<combinedEnd]
    let searchIndex = combined.range(of: "VideoLibrarySearchToolbarControl(viewModel: viewModel)")?.lowerBound
    let sourceIndex = combined.range(of: "VideoLibrarySourceToolbarButtons(")?.lowerBound
    require(
        combined.contains("HStack(spacing: 8)")
            && searchIndex != nil
            && sourceIndex != nil
            && searchIndex! < sourceIndex!,
        "Video library search and source actions should share one compact toolbar item so the circular buttons stay visible"
    )
} else {
    require(false, "Video library combined search/source toolbar control should be present before the search control")
}
require(
    !libraryView.contains("private struct VideoLibraryHeaderGlassSurface")
        && !libraryView.contains("private struct VideoLibrarySectionHeaderSurface")
        && !libraryView.contains("private struct VideoLibrarySectionHeader"),
    "Video library should not retain poster-only section header surfaces"
)
require(
    libraryView.contains("private struct VideoLibraryContentTitleBar")
        && libraryView.contains(".frame(height: 34)"),
    "Video library content title bar should stay compact so the native toolbar does not create excess top whitespace"
)
require(
    !libraryView.contains(".background(.bar)"),
    "Video library page header should not use the old opaque bar background"
)
require(
    libraryView.contains("if viewModel.selectedRow != nil {")
        && libraryView.contains("VideoLibraryInspectorView(viewModel: viewModel)"),
    "Video library details inspector should appear only after a video is selected"
)
require(
    thumbnailStore != nil
        && thumbnailStore!.contains("actor VideoThumbnailScheduler")
        && libraryView.contains("VideoThumbnailScheduler.shared")
        && libraryView.contains("VideoThumbnailImageView")
        && libraryView.contains("VideoLibraryPosterGridView")
        && libraryView.contains("VideoLibraryPosterCardView")
        && libraryView.contains("VideoLibraryPosterArtworkView")
        && libraryView.contains("VideoLibraryNeutralCardSurface")
        && libraryView.contains(".videoLibraryNeutralCardSurface(cornerRadius: 16)")
        && libraryView.contains("VideoLibraryBottomProgressBar")
        && libraryView.contains("thumbnailRequestMode: .generateIfMissing")
        && libraryView.contains("requestMode: .generateIfMissing")
        && !libraryView.contains("globallyGeneratedThumbnailItemIDs")
        && !libraryView.contains("sections.flatMap(\\.rows).prefix(8)")
        && libraryView.contains("requestMode.taskIdentity")
        && libraryView.contains("private var thumbnailTaskID: String")
        && !libraryView.contains("index < 8")
        && !libraryView.contains("generatesMissingThumbnail")
        && libraryView.contains("LazyVGrid"),
    "Video library should restore poster/list UI with visible thumbnails that generate when missing and mode-aware thumbnail tasks"
)
if let posterCardRange = libraryView.range(of: "private struct VideoLibraryPosterCardView"),
   let posterCardEnd = libraryView[posterCardRange.lowerBound...].range(of: "private struct VideoLibraryPosterArtworkView")?.lowerBound {
    let posterCard = libraryView[posterCardRange.lowerBound..<posterCardEnd]
    require(
        posterCard.contains(".videoLibraryNeutralCardSurface(cornerRadius: 16)")
            && !posterCard.contains(".nativeGlassCardSurface"),
        "Video poster cards should use the neutral card surface instead of a material glass background"
    )
} else {
    require(false, "Video poster card should be inspectable before poster artwork")
}
if let rowRange = libraryView.range(of: "private struct VideoLibraryRowView"),
   let rowEnd = libraryView[rowRange.lowerBound...].range(of: "private struct VideoLibraryDetailsButton")?.lowerBound {
    let rowView = libraryView[rowRange.lowerBound..<rowEnd]
    require(
        rowView.contains("VideoThumbnailImageView(")
            && rowView.contains("requestMode: .generateIfMissing")
            && rowView.contains("Text(row.sourceName)")
            && rowView.contains("Text(row.item.parentFolder)")
            && rowView.contains("Text(Self.fileSizeFormatter.string(fromByteCount: row.item.fileSize))")
            && rowView.contains("Text(modifiedAt, style: .date)")
            && rowView.contains("ProgressView(value: progress)")
            && rowView.contains("if let stateText")
            && rowView.contains("Text(row.displayTitle)")
            && !rowView.contains("Text(row.item.title)")
            && rowView.contains("VideoLibraryDetailsButton(onSelect: onSelect)"),
        "Video library list rows should be dense metadata rows with cache-only thumbnail placeholders, display titles, source, folder, size, modified date, progress/state, and trailing Details"
    )
} else {
    require(false, "Video library row view should be present before details button")
}
require(
    libraryView.contains("Label(\"Mark as Watched\"")
        && libraryView.contains("Label(\"Clear Progress\"")
        && libraryView.contains("Label(\"Play from Beginning\""),
    "Video library row context menu should expose playback state actions"
)
require(
    libraryView.contains("VideoLibraryInspectorView")
        && libraryView.contains("TextField(\"Display Title\"")
        && libraryView.contains("Toggle(\"Favorite\"")
        && libraryView.contains("TextField(\"Tags\"")
        && libraryView.contains("Label(\"Bind Subtitle\"")
        && libraryView.contains("Label(\"Clear Subtitle\"")
        && libraryView.contains("TextField(\"New Collection\"")
        && libraryView.contains("Label(\"Add Collection\"")
        && libraryView.contains("Label(\"Mark Selected Watched\"")
        && libraryView.contains("Label(\"Clear Selected Progress\"")
        && libraryView.contains("Label(\"Remove Missing\""),
    "Video library should expose a detail inspector for V3 metadata, subtitles, collections, and batch actions"
)
require(
    libraryView.contains("VideoLibraryInspectorCard")
        && libraryView.contains("VideoLibraryInspectorActionButtonStyle")
        && libraryView.contains("VideoLibraryInspectorInputSurface")
        && libraryView.contains(".videoLibraryInspectorInput()")
        && libraryView.contains(".videoLibraryNeutralCardSurface(cornerRadius: 14)")
        && libraryView.contains("GlassEffectContainer(spacing: 12)")
        && libraryView.contains("NativeGlassMenuPicker(")
        && libraryView.contains("selection: $smartCollectionRuleField")
        && !libraryView.contains("Picker(\"Rule Field\", selection: $smartCollectionRuleField)"),
    "Video library inspector should use neutral cards with macOS 26 inputs, action buttons, and menu picker instead of default material controls"
)
if let inspectorCardRange = libraryView.range(of: "private struct VideoLibraryInspectorCard"),
   let inspectorCardEnd = libraryView[inspectorCardRange.lowerBound...].range(of: "private struct VideoLibraryNeutralCardSurface")?.lowerBound {
    let inspectorCard = libraryView[inspectorCardRange.lowerBound..<inspectorCardEnd]
    require(
        inspectorCard.contains(".videoLibraryNeutralCardSurface(cornerRadius: 14)")
            && !inspectorCard.contains(".nativeGlassCardSurface"),
        "Video inspector cards should use the neutral card surface instead of a material glass background"
    )
} else {
    require(false, "Video inspector card should be inspectable before neutral card surface")
}
require(
    libraryView.contains("VideoLibraryDetailsButton(onSelect: onSelect)")
        && libraryView.contains("private struct VideoLibraryDetailsButton")
        && libraryView.contains("Button(action: onSelect)")
        && libraryView.contains(".help(\"Details\")")
        && libraryView.contains(".accessibilityLabel(Text(\"Details\"))"),
    "Video library rows should expose a visible Details control that selects without opening playback"
)
require(
    libraryView.contains("let onOpenVideo: (URL, URL?) -> Void")
        && libraryView.contains("viewModel.subtitleURLForOpening(row.item)")
        && libraryView.contains("viewModel.subtitleURLForOpening(item)"),
    "Video library list and poster item opening should pass manually bound subtitles to the player"
)
require(
    libraryView.contains("viewModel.sourceSummaries")
        && libraryView.contains("summary.itemCount")
        && libraryView.contains("summary.inProgressCount")
        && libraryView.contains("summary.missingCount")
        && libraryView.contains("Label(\"Refresh Source\"")
        && libraryView.contains("Label(\"Reveal Source in Finder\""),
    "Video source management should show source status counts and per-source actions"
)
require(
    libraryView.contains("ToolbarItemGroup(placement: .primaryAction)")
        && libraryView.contains("VideoLibrarySortToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibraryLayoutToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibrarySearchToolbarControl(viewModel: viewModel)")
        && libraryView.contains("VideoLibrarySearchAndSourceToolbarControl("),
    "Video library should place sort, layout, and search/source controls in native toolbar groups"
)
require(
    libraryView.contains("UserDefaults.didChangeNotification")
        && libraryView.contains("viewModel.refreshPlaybackHistory()"),
    "Video library should refresh Recent/progress when playback history changes"
)
require(
    viewModel.contains("playbackHistoryRevision")
        && viewModel.contains("func refreshPlaybackHistory()")
        && viewModel.contains("_ = playbackHistoryRevision"),
    "Video library view model should expose an observable playback history refresh revision"
)
require(
    viewModel.contains("case continueWatching")
        && viewModel.contains("case unwatched")
        && viewModel.contains("case finished")
        && viewModel.contains("case missing")
        && viewModel.contains("enum VideoLibraryLayoutMode")
        && viewModel.contains("layoutMode")
        && viewModel.contains("VideoLibrarySourceSummary")
        && viewModel.contains("sourceSummaries")
        && viewModel.contains("func refreshSource")
        && viewModel.contains("func markWatched")
        && viewModel.contains("func clearProgress")
        && viewModel.contains("func openFromBeginningURL"),
    "Video library view model should support smart filters, source summaries, and playback state actions without layout mode state"
)
require(
    viewModel.contains("func setCollectionMembership")
        && viewModel.contains("func removeCollection"),
    "Video library view model should support editing collection membership from the V3 inspector"
)
require(
    libraryView.contains("@State private var pendingCollectionDeletion: VideoLibraryCollection?")
        && libraryView.contains("VideoLibraryDisclosureSectionLabel(")
        && libraryView.contains("onDeleteCollection:")
        && libraryView.contains("VideoLibraryCollectionActionsMenu(onDeleteCollection: onDeleteCollection)")
        && libraryView.contains("private struct VideoLibraryCollectionActionsGlassEffect")
        && libraryView.contains(".menuStyle(.borderlessButton)")
        && libraryView.contains("Image(systemName: \"ellipsis\")")
        && libraryView.contains("GlassEffectContainer(spacing: 0)")
        && libraryView.contains(".glassEffect(.regular.interactive(), in: Circle())")
        && libraryView.contains("Label(\"Delete Collection\", systemImage: \"trash\")")
        && libraryView.contains(".alert(\"Delete Collection?\"")
        && libraryView.contains("This removes the collection but keeps its videos in your library."),
    "Video library collections view should expose a macOS 26 glass delete collection action with a no-video-deletion confirmation"
)
if let removeRange = store.range(of: "func removeCollection"),
   let removeEnd = store[removeRange.lowerBound...].range(of: "@discardableResult\n    func removeMissingItems")?.lowerBound {
    let removeBlock = store[removeRange.lowerBound..<removeEnd]
    require(
        !removeBlock.contains("removeItem(")
            && !removeBlock.contains("fileManager.remove")
            && !removeBlock.contains("catalog.items.removeAll"),
        "Video library collection deletion should not delete files or remove catalog video items"
    )
} else {
    require(false, "Video library store should keep an inspectable removeCollection implementation")
}
require(
    thumbnailStore?.contains("case cacheOnly") == true
        && thumbnailStore?.contains("case generateIfMissing") == true
        && thumbnailStore?.contains("var taskIdentity: String") == true
        && thumbnailStore?.contains("runningTask?.cancel()") == true
        && thumbnailStore?.contains("isCancelled: { Task.isCancelled }") == true
        && thumbnailStore?.contains("static let maximumConcurrentJobs = 1") == true
        && thumbnailStore?.contains("static let maximumDimension = 384") == true,
    "Video thumbnail store should enforce cache/generate request modes, mode identities, cancellable single concurrency, and 384px maximum thumbnails"
)
require(
    viewModel.contains("No Matching Videos")
        && viewModel.contains("Try a different search or filter."),
    "Video library view model should expose filtered empty-state copy"
)
require(
    playerScreen.contains("openVideo(request.url, subtitleURL: request.subtitleURL)"),
    "Video player should honor bound subtitles carried by external library open requests"
)
require(
    store.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL")
        && store.contains("ProcessInfo.processInfo.environment"),
    "Video library store should support a catalog override for disposable UI validation"
)
require(
    buildScript.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL")
        && buildScript.contains("--env"),
    "native launch script should pass the disposable Video library catalog override into the launched app"
)
require(
    manualFixtureScript?.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL") == true
        && manualFixtureScript?.contains("mktemp -d") == true
        && manualFixtureScript?.contains("--video --verify") == true,
    "Video library manual fixture script should launch Video with a disposable catalog"
)

print("Video library contract tests passed")
