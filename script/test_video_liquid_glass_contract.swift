import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let controls = try source("Features/Video/VideoControlsView.swift")
let subtitles = try source("Features/Video/Subtitles/SubtitleOverlayView.swift")
let interactiveSubtitles = try source("Features/Video/Subtitles/InteractiveSubtitleTextView.swift")
let subtitleController = try source("Features/Video/Subtitles/VideoSubtitleController.swift")
let transcriptView = try source("Features/Video/Subtitles/SubtitleTranscriptView.swift")
let subtitleModel = try source("Models/Subtitle.swift")
let inspector = try source("Features/Video/VideoInspectorView.swift")
let miningHistorySidebar = try source("Features/Video/VideoMiningHistorySidebar.swift")
let mpvClient = try source("Features/Video/Playback/HSMpvClient.mm")
let screen = try source("Features/Video/VideoPlayerScreen.swift")
let lookup = try source("Features/Video/VideoLookupCoordinator.swift")
let popupPresentation = try source("Features/Popup/PopupPresentationCoordinator.swift")
let popup = try source("Features/Popup/PopupView.swift")
let rootView = try source("NativeMac/NativeMacRootView.swift")
let detailView = try source("NativeMac/NativeMacDetailView.swift")

require(
    controls.contains("primaryControlGroup")
        && controls.contains("progressControlStrip")
        && controls.contains("onToggleInspector")
        && !controls.contains("moreControlsMenu"),
    "video controls should use a compact IINA-like OSC with a dedicated inspector toggle"
)
require(
    controls.contains("VStack(spacing: 7)")
        && controls.contains(".frame(width: 680)")
        && controls.contains(".frame(width: 84)")
        && controls.contains(".frame(width: 330)")
        && controls.contains(".padding(.horizontal, 14)")
        && controls.contains(".padding(.vertical, 8)")
        && !controls.contains(".frame(maxWidth: 960)"),
    "video controls should match an IINA-like compact two-row size instead of stretching across the video"
)
require(
    controls.contains("let profiles: [HoshiProfile]")
        && controls.contains("let selectedProfileID: String")
        && controls.contains("var onSelectProfile: (String) -> Void")
        && controls.contains("private var profileMenu: some View")
        && controls.contains("Label(selectedProfile.displayName, systemImage: \"person.crop.circle\")")
        && controls.contains("ForEach(profiles)"),
    "video profile selection should be visible in the bottom playback controls"
)
require(
    screen.contains("profiles: profileRepository.index.profiles")
        && screen.contains("selectedProfileID: resolvedVideoProfile.id")
        && screen.contains("onSelectProfile: { profileID in")
        && screen.contains("private static let playbackChromeSize = CGSize(width: 680")
        && !screen.contains("Menu {\n                    ForEach(profileRepository.index.profiles)"),
    "video screen should move the profile menu out of the top controls and keep drag bounds aligned"
)
require(
    controls.contains("let canMineCurrentSubtitle: Bool")
        && controls.contains("var onMineCurrentSubtitle: () -> Void")
        && controls.contains("Label(\"Mine Current Subtitle\", systemImage: \"tray.and.arrow.down\")")
        && controls.contains(".disabled(!canMineCurrentSubtitle)"),
    "video controls should expose an asbplayer-style mine-current-subtitle action"
)
require(
    controls.contains("var onDragChanged: (CGSize) -> Void")
        && controls.contains("var onDragEnded: (CGSize) -> Void")
        && controls.contains("private var controlDragSurface: some View")
        && controls.contains("DragGesture(minimumDistance: 2, coordinateSpace: .global)")
        && controls.contains("Color.black.opacity(0.001)")
        && controls.contains(".contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))"),
    "video controls should use an IINA-like stable global drag coordinate space instead of moving local coordinates"
)
require(
    controls.contains(".background {\n            controlDragSurface")
        && !controls.contains("ZStack {\n            controlDragSurface"),
    "video control drag surface should follow the compact control content size instead of expanding to the player height"
)
require(
    controls.contains("VideoFloatingGlassSurface")
        && controls.contains("glassEffect(.regular.interactive()"),
    "video controls should use a single interactive Liquid Glass surface"
)
require(
    controls.contains("RoundedRectangle(cornerRadius: 12, style: .continuous)"),
    "video controls should render as a compact IINA-like rounded rectangle"
)
require(
    controls.contains(".thinMaterial"),
    "video controls should keep a pre-macOS 26 material fallback"
)
require(
    !controls.contains("autoHide")
        && !controls.contains("controlVisibility")
        && !controls.contains("onHover"),
    "video controls should remain fixed in this phase and not add auto-hide behavior"
)
require(
    !subtitles.contains(".glassEffect(")
        && !subtitles.contains(".background(")
        && !subtitles.contains("VideoSubtitleGlassSurface"),
    "subtitle overlay should remain transparent without a background frame"
)
require(
    subtitles.contains("let maskEnabled: Bool")
        && subtitles.contains("let maskMode: VideoSubtitleMaskMode")
        && subtitles.contains("let maskBlurRadius: Double")
        && subtitles.contains("let maskHiddenOpacity: Double")
        && subtitles.contains("let fontFamily: String")
        && subtitles.contains("let fontSize: Double")
        && subtitles.contains("let isLookupPopupVisible: Bool"),
    "subtitle overlay should receive text-only subtitle mask and appearance configuration"
)
require(
    subtitles.contains("private let subtitleBottomClearance: CGFloat = 142")
        && subtitles.contains(".padding(.bottom, subtitleBottomClearance)")
        && !subtitles.contains(".padding(.bottom, 84)"),
    "subtitle overlay should sit above the default compact playback control surface"
)
require(
    interactiveSubtitles.contains("let fontFamily: String")
        && interactiveSubtitles.contains("let fontSize: Double")
        && interactiveSubtitles.contains("private func subtitleFont() -> NSFont")
        && interactiveSubtitles.contains(".systemFont(ofSize: size, weight: .bold)")
        && !interactiveSubtitles.contains(".systemFont(ofSize: 20, weight: .medium)"),
    "interactive subtitle text should use configurable asbplayer-style font settings instead of the old hard-coded 20pt font"
)
require(
    subtitles.contains("@State private var isHovering = false")
        && subtitles.contains(".onHover { hovering in")
        && subtitles.contains("private var maskedBlurRadius: CGFloat")
        && subtitles.contains("private var maskedOpacity: Double")
        && subtitles.contains("private var isMaskRevealed: Bool")
        && subtitles.contains("isHovering || isLookupPopupVisible")
        && subtitles.contains(".blur(radius: maskedBlurRadius)")
        && subtitles.contains(".opacity(maskedOpacity)"),
    "subtitle overlay should reveal masked subtitles on hover or while a lookup popup is open using blur or opacity text effects"
)
require(
    subtitleController.contains("Task.detached")
        && subtitleController.contains("loadGeneration")
        && subtitleController.contains("applyPrimarySubtitleLoad")
        && !subtitleController.contains("applySecondarySubtitleLoad")
        && !subtitleController.contains("loadSecondary("),
    "external primary subtitle imports should parse off the main actor and ignore stale load completions without reintroducing secondary subtitle state"
)
require(
    screen.contains("enum VideoFileImportKind")
        && screen.contains("@State private var pendingFileImportKind: VideoFileImportKind?")
        && screen.contains("@State private var activeFileImportKind: VideoFileImportKind?")
        && screen.contains(".fileImporter(")
        && screen.contains("allowedContentTypes: (pendingFileImportKind ?? activeFileImportKind)?.allowedContentTypes(")
        && screen.contains("guard let kind = activeFileImportKind ?? pendingFileImportKind else { return }")
        && screen.contains("handleFileImport(result, kind: kind)")
        && !screen.contains("let panel = NSOpenPanel()")
        && !screen.contains("panel.runModal()"),
    "video inspector imports should use the same state-driven SwiftUI file importer path as the stable top controls path"
)
require(
    screen.contains(".onDrop(of: [.fileURL]")
        && screen.contains("handleDroppedFileURLs(")
        && screen.contains("loadDroppedMedia(")
        && screen.contains("loadDroppedSubtitle(")
        && screen.contains("isMediaFile(")
        && screen.contains("isSubtitleFile(")
        && screen.contains("loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)")
        && screen.contains("model.open(mediaURL)")
        && screen.contains("autoloadSubtitleIfAvailable(for: mediaURL)"),
    "video surface should accept dropped media and subtitle files while reusing the primary video/subtitle import paths"
)
require(
    screen.contains("mpvMediaExtensions")
        && screen.contains("\"m4b\"")
        && screen.contains("\"m4a\"")
        && screen.contains("\"mp3\"")
        && screen.contains("\"flac\"")
        && screen.contains("\"opus\"")
        && screen.contains("\"m2ts\""),
    "video imports should expose mpv-oriented media extensions including audio books and audio-only files"
)
require(
    screen.contains("model.loadExternalSubtitle(url)")
        && screen.contains("loadPrimarySubtitle(from: url, loadIntoMpv: true)"),
    "external subtitle imports should be loaded into mpv instead of disabling subtitle tracks during import"
)
require(
    screen.contains("autoloadSubtitleIfAvailable(for: url)")
        && screen.contains("VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL)")
        && screen.contains("loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: false)")
        && screen.contains("loadPrimarySubtitle(from: url, loadIntoMpv: true)"),
    "video import should auto-load same-folder subtitle sidecars through the same primary subtitle path as manual imports"
)
require(
    !subtitles.contains("secondaryCues")
        && !inspector.contains("Open Secondary Subtitles")
        && !screen.contains("secondarySubtitle")
        && !screen.contains("secondarySubtitleName"),
    "video should keep secondary subtitle UI/state out of the current phase so primary subtitle import and lookup remain stable"
)
require(
    interactiveSubtitles.contains("PassThroughSubtitleScrollView")
        && interactiveSubtitles.contains("containsInteractiveText(at:")
        && interactiveSubtitles.contains("var onHoverChanged: ((Bool) -> Void)?")
        && interactiveSubtitles.contains("NSTrackingArea")
        && interactiveSubtitles.contains("mouseEntered(with event: NSEvent)")
        && interactiveSubtitles.contains("mouseExited(with event: NSEvent)")
        && interactiveSubtitles.contains("return nil"),
    "interactive subtitle views should pass through clicks outside rendered text while still reporting hover for subtitle masks"
)
require(
    interactiveSubtitles.contains("syncDocumentViewFrame()")
        && interactiveSubtitles.contains("textView.textContainer?.heightTracksTextView = true")
        && interactiveSubtitles.contains("textView.isVerticallyResizable = false")
        && interactiveSubtitles.contains("contentView.scroll(to: .zero)"),
    "interactive subtitle text should pin the AppKit document view to its visible row and avoid first-layout scroll drift"
)
require(
    subtitles.contains("onHoverChanged: { hovering in")
        && subtitles.contains("isHovering = hovering"),
    "subtitle mask rows should receive hover from the AppKit subtitle view instead of relying only on SwiftUI hover"
)
require(
    screen.contains("onTapOutside: {")
        && screen.contains("lookup.presentation.handleTapInsidePopup(id: popupID)")
        && popupPresentation.contains("func handleTapInsidePopup(id: UUID)")
        && popupPresentation.contains("closeChildren(of: id)"),
    "tapping inside a video popup should use shared popup-stack semantics and close only its descendants"
)
require(
    screen.contains("if shouldShowVideoDismissLayer")
        && screen.contains("Color.clear")
        && screen.contains(".contentShape(Rectangle())")
        && screen.contains("dismissVideoOverlaysFromCanvas()")
        && screen.contains(".zIndex(2.5)")
        && screen.contains("private var shouldShowVideoDismissLayer: Bool")
        && screen.contains("hasActiveVideoPopup || isInspectorVisible")
        && screen.contains("private func dismissVideoPopupsIfNeeded()"),
    "video should install a transparent dismiss layer above subtitles so non-subtitle clicks close active lookup popups or the inspector"
)
require(
    screen.contains("onToggleInspector: {")
        && screen.contains("onToggleFullScreen: {")
        && screen.contains("dismissVideoPopupsThen")
        && !screen.contains(".simultaneousGesture("),
    "video controls and inspector interactions should defer until subtitle lookup popups finish closing without broad inspector tap gestures"
)
require(
    (
        screen.contains(".onTapGesture(count: 2)")
            || screen.contains("TapGesture(count: 2)")
    )
        && screen.contains("toggleFullScreenFromPointer()"),
    "video canvas should use double-click to toggle full screen without moving that behavior into the control bar"
)
require(
    screen.contains("@State private var isPlaybackChromeVisible = true")
        && screen.contains("@State private var isPointerInsidePlayerSurface = true")
        && screen.contains("@State private var isPointerOverPlaybackChrome = false")
        && screen.contains("@State private var playbackChromeDragOffset: CGSize = .zero")
        && screen.contains("@State private var playbackChromeStoredOffset: CGSize = .zero")
        && screen.contains("@State private var playbackChromeAutoHideTask: Task<Void, Never>?")
        && screen.contains("@Environment(\\.scenePhase) private var scenePhase")
        && screen.contains(".onChange(of: scenePhase)")
        && screen.contains("playerSurfaceHoverChanged(hovering)")
        && screen.contains(".onContinuousHover { phase in")
        && screen.contains("handleVideoPointerMovement(phase)")
        && screen.contains("TapGesture(count: 1)")
        && screen.contains("togglePlaybackFromPointer()")
        && screen.contains("private func schedulePlaybackChromeAutoHide()")
        && screen.contains("private func hidePlaybackChromeForPointerExit()")
        && screen.contains("private func clampedPlaybackChromeOffset")
        && screen.contains("playbackChromeStoredOffset = clampedPlaybackChromeOffset")
        && screen.contains("onDragChanged: { translation in")
        && screen.contains("onDragEnded: { translation in")
        && screen.contains(".position(playbackChromeBasePosition(in: geometry.size))")
        && screen.contains(".offset(playbackChromeCurrentOffset(in: geometry.size))")
        && screen.contains("Task.sleep(nanoseconds: 3_000_000_000)")
        && screen.contains("private func playbackChromeHoverChanged(_ hovering: Bool)")
        && screen.contains("private var shouldShowPlaybackChrome: Bool"),
    "video playback chrome should appear on pointer movement, be draggable within the video surface, auto-hide after a short delay, hide on app/window exit and stay visible while hovered or overlays are active"
)
require(
    screen.contains("var dragTransaction = Transaction(animation: nil)")
        && screen.contains("dragTransaction.disablesAnimations = true")
        && screen.contains("withTransaction(dragTransaction) {")
        && screen.contains("playbackChromeDragOffset = translation")
        && screen.contains("withAnimation(.smooth(duration: 0.18)) {")
        && screen.contains("playbackChromeStoredOffset = finalOffset"),
    "video playback chrome should track drag updates without animation and restore smooth animation only when the drag ends"
)
require(
    screen.contains("VideoShortcutActions.previousSubtitleCue.id")
        && screen.contains("seekRelativeSubtitleCue(offset: -1)")
        && screen.contains("VideoShortcutActions.nextSubtitleCue.id")
        && screen.contains("seekRelativeSubtitleCue(offset: 1)")
        && screen.contains("VideoShortcutActions.toggleSubtitlesVisible.id")
        && screen.contains("toggleSubtitlesVisible()")
        && screen.contains("VideoShortcutActions.cycleSubtitleTrack.id")
        && screen.contains("cycleSubtitleTrack()")
        && screen.contains("VideoShortcutActions.volumeDown.id")
        && screen.contains("adjustVolume(by: -5)")
        && screen.contains("VideoShortcutActions.volumeUp.id")
        && screen.contains("adjustVolume(by: 5)"),
    "video screen should wire subtitle navigation, subtitle visibility, subtitle track cycling and volume shortcuts"
)
require(
    lookup.contains("Logger(subsystem: \"moe.shishamo.hoshi\", category: \"VideoLookup\")")
        && lookup.contains("isClosingPopupStack")
        && lookup.contains("pendingCloseCompletions")
        && lookup.contains("Ignoring reentrant closeAll"),
    "video lookup popup dismissal should be logged and protected against reentrant close animations"
)
require(
    screen.contains("alignment: .bottom"),
    "video controls should float over the video instead of occupying a full-width bar"
)
require(
    rootView.contains("private var isWindowToolbarVisible: Bool")
        && rootView.contains("selectedSection == .video")
        && rootView.contains("return false"),
    "video should hide the system window toolbar so playback is not pushed down by top chrome"
)
require(
    detailView.contains("VideoPlayerScreen(isActive: section == .video)")
        && detailView.contains(".opacity(section == .video ? 1 : 0)")
        && detailView.contains(".allowsHitTesting(section == .video)")
        && detailView.contains("if section != .video")
        && !detailView.contains("case .video:\n                VideoPlayerScreen()"),
    "video detail should keep the player alive across sidebar section switches while disabling interaction when hidden"
)
require(
    screen.contains("let isActive: Bool")
        && screen.contains(".onChange(of: isActive)")
        && screen.contains("if isActive {")
        && screen.contains("registerKeyboardShortcuts()")
        && screen.contains("unregisterKeyboardShortcuts()"),
    "persistent video detail should register shortcuts only while the Video section is active"
)
require(
    screen.contains(".ignoresSafeArea(.container, edges: .top)"),
    "video playback surface should extend into the hidden toolbar safe area so the top strip can show video"
)
require(
    !screen.contains("ToolbarItemGroup(placement: .primaryAction)")
        && screen.contains("videoTopControls")
        && screen.contains("WindowDragGesture()")
        && screen.contains("toggleSidebar()")
        && screen.contains("#selector(NSSplitViewController.toggleSidebar(_:))")
        && screen.contains("VideoTopGlassButtonStyle"),
    "video top chrome should be replaced by a small floating glass sidebar/open-video control and a drag strip"
)
require(
    screen.contains(".frame(height: 24)")
        && screen.contains(".frame(width: 26, height: 26)")
        && screen.contains(".padding(.top, 8)")
        && !screen.contains(".frame(height: 42)")
        && !screen.contains(".frame(width: 32, height: 32)")
        && !screen.contains(".padding(.top, 12)"),
    "video top chrome should use a genuinely smaller drag strip and visible button footprint"
)
require(
    screen.contains("ZStack(alignment: .trailing)")
        && screen.contains("inspectorOverlay")
        && screen.contains(".transition(.move(edge: .trailing).combined(with: .opacity))")
        && screen.contains("HStack(spacing: 0)")
        && screen.contains("VideoMiningHistorySidebar(")
        && screen.contains("@State private var isMiningHistoryVisible = false"),
    "video inspector should still overlay the video while mining history uses a separate fixed sidebar that pushes the video"
)
require(
    screen.contains(".padding(.vertical, 16)")
        && screen.contains(".padding(.trailing, 16)"),
    "video inspector should be inset from the video window edge"
)
require(
    screen.contains("maskEnabled: userConfig.videoSubtitleMaskEnabled")
        && screen.contains("maskMode: userConfig.videoSubtitleMaskMode")
        && screen.contains("maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius")
        && screen.contains("maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity")
        && screen.contains("fontFamily: userConfig.videoSubtitleFontFamily")
        && screen.contains("fontSize: userConfig.videoSubtitleFontSize")
        && screen.contains("isLookupPopupVisible: hasActiveVideoPopup"),
    "video screen should wire subtitle mask and appearance user preferences into the transparent subtitle overlay"
)
require(
    !controls.contains(".background(.regularMaterial)"),
    "video controls should not use the old full-width regularMaterial bar"
)
require(
    inspector.contains("struct VideoInspectorView")
        && inspector.contains("enum VideoInspectorTab")
        && inspector.contains("case episodes")
        && inspector.contains("case video")
        && inspector.contains("case audio")
        && inspector.contains("case subtitles")
        && !inspector.contains("case transcript")
        && inspector.contains("onOpenTranscript")
        && !inspector.contains("onSeekToChapter")
        && !inspector.contains("inspectorSection(\"Chapters\""),
    "video inspector should route Transcript and Chapters into the study sidebar without duplicate chapter navigation"
)
require(
    inspector.contains("VideoInspectorGlassSurface")
        && inspector.contains("NativeGlassSegmentedPicker(")
        && inspector.contains("VideoInspectorSectionGlassSurface")
        && inspector.contains("VideoInspectorGlassButtonStyle")
        && !inspector.contains("SubtitleTranscriptView"),
    "video inspector should use shared glass controls without hosting the transcript view"
)
require(
    inspector.contains("subtitleMaskSection")
        && inspector.contains("subtitleMaskBlurRadius")
        && inspector.contains("subtitleMaskHiddenOpacity")
        && inspector.contains("Mask subtitles until hover"),
    "video inspector should expose subtitle mask toggle, mode and strength controls in the Subtitles tab"
)
require(
    mpvClient.contains("mpv_set_property_string(_handle, \"sub-visibility\", \"no\")")
        && mpvClient.contains("shouldRenderNativeImageSubtitles ? \"yes\" : \"no\"")
        && !mpvClient.contains("cues.count > 0 ? \"no\" : \"yes\""),
    "mpv should never restore native text subtitles during cue gaps while still supporting selected bitmap tracks"
)
require(
    miningHistorySidebar.contains("struct VideoMiningHistorySidebar")
        && miningHistorySidebar.contains("frame(minWidth: 320, idealWidth: 340, maxWidth: 380)")
        && miningHistorySidebar.contains("ScrollViewReader")
        && miningHistorySidebar.contains("enum VideoStudySidebarTab")
        && miningHistorySidebar.contains("case chapters")
        && miningHistorySidebar.contains("let chapters: [VideoChapter]")
        && miningHistorySidebar.contains("NativeGlassSegmentedPicker")
        && miningHistorySidebar.contains("SubtitleTranscriptView")
        && miningHistorySidebar.contains("chapterList")
        && miningHistorySidebar.contains("currentChapterID")
        && miningHistorySidebar.contains("onSeekChapter(chapter.id)")
        && miningHistorySidebar.contains("No Chapters")
        && miningHistorySidebar.contains("Button {\n                onJump(item)")
        && miningHistorySidebar.contains("Label(\"Copy Subtitle\", systemImage: \"doc.on.doc\")")
        && miningHistorySidebar.contains("Label(\"Delete\", systemImage: \"trash\")")
        && miningHistorySidebar.contains("onCopy(item)")
        && !miningHistorySidebar.contains("onContinueMining")
        && !miningHistorySidebar.contains("Menu")
        && !miningHistorySidebar.contains("Image(systemName: \"ellipsis\")")
        && miningHistorySidebar.contains("confirmationDialog")
        && miningHistorySidebar.contains("Clear Mining History"),
    "video study sidebar should switch between mining history, transcript and chapters while preserving direct history actions"
)
require(
    screen.contains("@State private var miningHistory = VideoMiningHistoryStore()")
        && screen.contains("mineCurrentSubtitle()")
        && screen.contains("miningHistory.record(")
        && screen.contains("VideoMiningHistoryNavigationResolver.resolve(")
        && screen.contains("copyMiningHistorySubtitle(")
        && screen.contains("showMiningHistoryNotice(.copied)")
        && screen.contains("VideoShortcutActions.mineCurrentSubtitle.id")
        && screen.contains("Label(\"Mining History\", systemImage: \"clock.arrow.circlepath\")"),
    "video mining should save, copy and restore current subtitles through the shared player flow"
)
require(
    !popup.contains("onMiningStarted")
        && !popup.contains("onMiningFinished")
        && !screen.contains("onMiningStarted:")
        && !screen.contains("onMiningFinished:"),
    "shared Popup mining should no longer expose Video-only history result hooks"
)
require(
    transcriptView.contains("@State private var rowWindow = SubtitleTranscriptWindow()")
        && transcriptView.contains("transcript.rows(in: rowWindow.visibleRange)")
        && transcriptView.contains("extendWindowIfNeeded(forVisibleOffset:")
        && transcriptView.contains("rowWindow.followPlayback("),
    "video transcript should dynamically render a nearby row window and extend it during playback or scrolling"
)
require(
    !subtitleModel.contains("struct SubtitleTranscript: Equatable")
        && subtitleModel.contains("let changeToken: ChangeToken")
        && subtitleModel.contains("struct ChangeToken: Equatable"),
    "subtitle transcript should expose a cheap change token and avoid whole-array Equatable comparisons"
)
require(
    !transcriptView.contains("onChange(of: transcript.rows)")
        && transcriptView.contains("onChange(of: transcript.changeToken)"),
    "video transcript should track a cheap transcript change token instead of comparing the full row array"
)
require(
    transcriptView.contains("@State private var focusedRowID")
        && transcriptView.contains("row.id != focusedRowID || rowWindow.visibleRange != previousRange"),
    "video transcript should avoid re-scrolling the list on every playback tick while the focused row is unchanged"
)
require(
    !inspector.contains(".pickerStyle(.segmented)")
        && !inspector.contains(".buttonStyle(.bordered)"),
    "video inspector should not fall back to plain segmented pickers or bordered buttons for the glass UI"
)

print("Video Liquid Glass contract tests passed")
