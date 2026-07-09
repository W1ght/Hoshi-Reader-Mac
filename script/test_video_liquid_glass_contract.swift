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

func requireOrdered(_ source: String, _ snippets: [String], _ message: String) {
    var lowerBound = source.startIndex
    for snippet in snippets {
        guard let range = source.range(of: snippet, range: lowerBound..<source.endIndex) else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        lowerBound = range.upperBound
    }
}

func countOccurrences(_ source: String, of needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var lowerBound = source.startIndex
    while let range = source.range(of: needle, range: lowerBound..<source.endIndex) {
        count += 1
        lowerBound = range.upperBound
    }
    return count
}

let controls = try source("Features/Video/VideoControlsView.swift")
let subtitles = try source("Features/Video/Subtitles/SubtitleOverlayView.swift")
let interactiveSubtitles = try source("Features/Video/Subtitles/InteractiveSubtitleTextView.swift")
let subtitleController = try source("Features/Video/Subtitles/VideoSubtitleController.swift")
let transcriptView = try source("Features/Video/Subtitles/SubtitleTranscriptView.swift")
let subtitleModel = try source("Models/Subtitle.swift")
let inspector = try source("Features/Video/VideoInspectorView.swift")
let inspectorState = try source("Features/Video/VideoInspectorState.swift")
let miningHistorySidebar = try source("Features/Video/VideoMiningHistorySidebar.swift")
let studyListCard = (try? source("Features/Video/VideoStudyListCard.swift")) ?? ""
let ambientBackdrop = (try? source("Features/Video/VideoAmbientBackdrop.swift")) ?? ""
let ambientModel = (try? source("Features/Video/VideoAmbientBackdropModel.swift")) ?? ""
let mpvClient = try source("Features/Video/Playback/HSMpvClient.mm")
let playbackEngine = try source("Features/Video/Playback/PlaybackEngine.swift")
let playerViewModel = try source("Features/Video/VideoPlayerViewModel.swift")
let windowChrome = (try? source("Features/Video/VideoWindowChromeController.swift")) ?? ""
let videoMediaTypes = try source("Features/Video/VideoMediaTypes.swift")
let screen = try source("Features/Video/VideoPlayerScreen.swift")
let lookup = try source("Features/Video/VideoLookupCoordinator.swift")
let popupPresentation = try source("Features/Popup/PopupPresentationCoordinator.swift")
let popup = try source("Features/Popup/PopupView.swift")
let rootView = try source("NativeMac/NativeMacRootView.swift")
let detailView = try source("NativeMac/NativeMacDetailView.swift")
let app = try source("NativeMac/HoshiNativeMacApp.swift")
let presenter = try source("NativeMac/VideoWindowPresenter.swift")
let profilesView = try source("Features/Settings/ProfilesView.swift")
let profileCoordinator = (try? source("Core/ProfileActivationCoordinator.swift")) ?? ""

require(
    controls.contains("primaryControlGroup")
        && controls.contains("progressControlStrip")
        && controls.contains("onToggleInspector")
        && !controls.contains("moreControlsMenu"),
    "video controls should use a compact IINA-like OSC with a dedicated inspector toggle"
)
require(
    controls.contains("VStack(spacing: 5)")
        && controls.contains("private static let floatingControlsWidth: CGFloat = 690")
        && controls.contains("private static let floatingControlsHeight: CGFloat = 74")
        && controls.contains("private static let floatingIconSize: CGFloat = 26")
        && controls.contains(".frame(width: Self.floatingControlsWidth")
        && controls.contains(".frame(width: 84)")
        && controls.contains("private static let floatingProgressHorizontalInset: CGFloat = 58")
        && controls.contains("private static let compactProgressHorizontalInset: CGFloat = 0")
        && countOccurrences(controls, of: ".frame(maxWidth: .infinity)\n                .frame(height: 16)") >= 2
        && controls.contains(".padding(.horizontal, 12)")
        && controls.contains(".padding(.vertical, 7)")
        && !controls.contains(".frame(maxWidth: 960)"),
    "video controls should match an IINA-like compact two-row size instead of stretching across the video"
)
require(
    controls.contains("let profiles: [HoshiProfile]")
        && controls.contains("let selectedProfileID: String")
        && controls.contains("var onSelectProfile: (String) -> Void")
        && controls.contains("private var profileMenu: some View")
        && controls.contains("Image(systemName: \"person.crop.circle\")")
        && !controls.contains("Label(selectedProfile.displayName, systemImage: \"person.crop.circle\")")
        && controls.contains("ForEach(profiles)"),
    "video profile selection should be visible as an icon-only bottom playback control"
)
require(
    controls.contains("Picker(")
        && controls.contains("\"Video Profile\"")
        && controls.contains("selection: Binding<String>")
        && controls.contains(".tag(profile.id)")
        && controls.contains(".labelsHidden()"),
    "video profile menu should use a system picker so the selected Profile gets a checkmark in the expanded menu"
)
requireOrdered(
    controls,
    [
        "volumeControl",
        "Spacer(minLength: 0)",
        "episodeControls",
        "Spacer(minLength: 0)",
        "speedControlButton",
        "utilityControlGroup",
    ],
    "video utility controls should sit on the right side after playback controls"
)
requireOrdered(
    controls,
    [
        "private var utilityControlGroup",
        "miningHistoryButton",
        "openVideoButton",
        "profileMenu",
        "mineCurrentSubtitleButton",
        "inspectorButton",
        "fullScreenButton",
    ],
    "video utility control group should preserve the right-side action order"
)
require(
    controls.contains("var onSetSpeed: (Double) -> Void")
        && controls.contains("@State private var isSpeedPanelVisible = false")
        && controls.contains("@State private var speedInputText = \"\"")
        && controls.contains("private var speedControlButton: some View")
        && controls.contains("private var speedControlPanel: some View")
        && controls.contains("Label(\"Playback Speed\", systemImage: \"speedometer\")")
        && controls.contains("VideoPlaybackSpeed.label(snapshot.speed)")
        && controls.contains("VideoPlaybackSpeed.presetChoices")
        && controls.contains("Slider(")
        && controls.contains("VideoPlaybackSpeed.customInputLowerBound...VideoPlaybackSpeed.maximum")
        && controls.contains("TextField(\"Custom\", text: $speedInputText)")
        && controls.contains("commitSpeedInput()")
        && screen.contains("onSetSpeed: { speed in"),
    "video bottom controls should expose playback speed through a floating panel with presets, slider, and numeric input"
)
require(
    screen.contains("profiles: profileRepository.index.profiles")
        && screen.contains("selectedProfileID: resolvedVideoProfile.id")
        && screen.contains("onSelectProfile: { profileID in")
        && screen.contains("layout: userConfig.videoControlBarLayout")
        && screen.contains("private var videoControlsMetrics: VideoControlsMetrics")
        && !screen.contains("Menu {\n                    ForEach(profileRepository.index.profiles)"),
    "video screen should move the profile menu out of the top controls and keep drag bounds aligned"
)
require(
    screen.contains("private final class VideoPlayerModelStore: ObservableObject")
        && screen.contains("let model = VideoPlayerViewModel(engine: MpvPlayerEngine())")
        && screen.contains("@StateObject private var modelStore = VideoPlayerModelStore()")
        && screen.contains("private var model: VideoPlayerViewModel")
        && screen.contains("modelStore.model")
        && !screen.contains("@State private var model")
        && !screen.contains("State(initialValue: VideoPlayerViewModel(engine: MpvPlayerEngine()))")
        && !screen.contains("@State private var model = VideoPlayerViewModel(engine: MpvPlayerEngine())"),
    "video screen should own the mpv-backed player model through StateObject storage so SwiftUI view reinitialization does not allocate extra mpv clients"
)
require(
    controls.contains("let canMineCurrentSubtitle: Bool")
        && controls.contains("var onMineCurrentSubtitle: () -> Void")
        && controls.contains("Label(\"Mine Current Subtitle\", systemImage: \"tray.and.arrow.down\")")
        && controls.contains(".disabled(!canMineCurrentSubtitle)"),
    "video controls should expose an asbplayer-style mine-current-subtitle action"
)
require(
    controls.contains("var onToggleMiningHistory: () -> Void")
        && controls.contains("var onOpenVideo: () -> Void")
        && controls.contains("Label(\"Mining History\", systemImage: \"clock.arrow.circlepath\")")
        && controls.contains("Label(\"Open Video\", systemImage: \"film\")")
        && screen.contains("onToggleMiningHistory: {")
        && screen.contains("onOpenVideo: {")
        && !screen.contains("private var videoTopControls")
        && !screen.contains("VideoTopGlassButtonStyle"),
    "layout A should integrate history and open-video actions into one widened bottom control bar"
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
        && !controls.contains("controlVisibility"),
    "video controls should remain fixed in this phase and not add auto-hide behavior"
)
require(
    !subtitles.contains(".glassEffect(")
        && subtitles.contains("let backgroundDisabled: Bool")
        && subtitles.contains("if !backgroundDisabled && normalizedBackgroundOpacity > 0")
        && !subtitles.contains("VideoSubtitleGlassSurface"),
    "subtitle overlay should remain transparent by default while allowing the explicit user-controlled background opacity setting"
)
require(
    subtitles.contains("let maskEnabled: Bool")
        && subtitles.contains("let maskMode: VideoSubtitleMaskMode")
        && subtitles.contains("let maskBlurRadius: Double")
        && subtitles.contains("let maskHiddenOpacity: Double")
        && subtitles.contains("let fontFamily: String")
        && subtitles.contains("let fontSize: Double")
        && subtitles.contains("let fontWeight: Int")
        && subtitles.contains("let shadowRadius: Double")
        && subtitles.contains("let isLookupPopupVisible: Bool"),
    "subtitle overlay should receive text-only subtitle mask and appearance configuration"
)
require(
    controls.contains("subtitleBottomClearance: 142")
        && controls.contains("subtitleBottomClearance: 72")
        && subtitles.contains("let bottomClearance: CGFloat")
        && subtitles.contains(".padding(.bottom, bottomClearance + verticalPositionOffset)")
        && !subtitles.contains("private let subtitleBottomClearance: CGFloat = 142"),
    "subtitle overlay should sit above the active playback control surface while allowing user vertical-position adjustment"
)
require(
    interactiveSubtitles.contains("let fontFamily: String")
        && interactiveSubtitles.contains("let fontSize: Double")
        && interactiveSubtitles.contains("let fontWeight: Int")
        && interactiveSubtitles.contains("private func subtitleFont() -> NSFont")
        && interactiveSubtitles.contains(".systemFont(ofSize: size, weight: subtitleFontWeight())")
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
        && screen.contains("openVideo(mediaURL, subtitleURL: subtitleURL)")
        && screen.contains("autoloadSubtitleIfAvailable(for: mediaURL)"),
    "video surface should accept dropped media and subtitle files while reusing the primary video/subtitle import paths"
)
require(
    videoMediaTypes.contains("supportedExtensions")
        && videoMediaTypes.contains("\"m4b\"")
        && videoMediaTypes.contains("\"m4a\"")
        && videoMediaTypes.contains("\"mp3\"")
        && videoMediaTypes.contains("\"flac\"")
        && videoMediaTypes.contains("\"opus\"")
        && videoMediaTypes.contains("\"m2ts\""),
    "video imports should expose mpv-oriented media extensions including audio books and audio-only files"
)
require(
    screen.contains("model.loadExternalSubtitle(url)")
        && screen.contains("loadPrimarySubtitle(from: url, loadIntoMpv: true)"),
    "external subtitle imports should be loaded into mpv instead of disabling subtitle tracks during import"
)
require(
    screen.contains("restoreRememberedSubtitleSelectionOrAutoload(for: mediaURL)")
        && screen.contains("VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL)")
        && screen.contains("loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: false)")
        && screen.contains("loadPrimarySubtitle(from: url, loadIntoMpv: true)"),
    "video import should auto-load same-folder subtitle sidecars through the same primary subtitle path as manual imports"
)
require(
    screen.contains("restoreRememberedSubtitleSelectionOrAutoload")
        && screen.contains(".onChange(of: model.loadGeneration)")
        && screen.contains(".onChange(of: model.snapshot.isLoaded)")
        && screen.contains("VideoSubtitleRestoreResolver.resolve(")
        && screen.contains("model.consumePendingSubtitleSelection()")
        && screen.contains("model.rememberSubtitleSelection("),
    "video should restore and persist the per-file subtitle selection through playback history"
)
require(
    screen.contains("openPlaylistEpisode(url)")
        && screen.contains("private func openPlaylistEpisode(_ url: URL)")
        && screen.contains("lookup.closeAll(player: model)")
        && screen.contains("subtitles.clear()")
        && screen.contains("model.selectPlaylistItem(url)"),
    "episode selection should clear stale lookup/subtitle state before restoring the selected episode subtitles"
)
require(
    screen.contains("guard model.errorMessage == nil else")
        && screen.contains("shouldSkipNextAutomaticSubtitleRestore = false"),
    "failed explicit media loads must not leak subtitle-restore suppression into the next video"
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
    interactiveSubtitles.contains("private func performLookup(at point: CGPoint)")
        && interactiveSubtitles.contains("override func mouseDown(with event: NSEvent)")
        && interactiveSubtitles.contains("performLookup(at: point)")
        && interactiveSubtitles.contains("scheduleShiftHoverLookup(at: point)"),
    "Video click and Shift-hover lookup must reuse one point-to-character selection path"
)
require(
    interactiveSubtitles.contains("NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)")
        && interactiveSubtitles.contains("return event")
        && interactiveSubtitles.contains("NSEvent.removeMonitor")
        && interactiveSubtitles.contains("override func viewDidMoveToWindow()")
        && interactiveSubtitles.contains("deinit")
        && interactiveSubtitles.contains(".mouseMoved"),
    "Video Shift-hover modifier observation must be non-consuming and bound to the subtitle view lifecycle"
)
require(
    interactiveSubtitles.contains("let hoverLookupDelayMs: Int")
        && subtitles.contains("let hoverLookupDelayMs: Int")
        && screen.contains("hoverLookupDelayMs: userConfig.desktopLookupHoverDelayMs"),
    "Video Shift-hover must use the existing configurable Mac hover delay"
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
        && screen.contains("@State private var lastPlaybackChromePointerLocation: CGPoint?")
        && screen.contains("@State private var playbackChromeDragOffset: CGSize = .zero")
        && screen.contains("@State private var playbackChromeStoredOffset: CGSize = .zero")
        && screen.contains("@State private var playbackChromeAutoHideTask: Task<Void, Never>?")
        && screen.contains("@Environment(\\.scenePhase) private var scenePhase")
        && screen.contains(".onChange(of: scenePhase)")
        && screen.contains("playerSurfaceHoverChanged(hovering)")
        && screen.contains(".onContinuousHover { phase in")
        && screen.contains("handleVideoPointerMovement(phase)")
        && screen.contains("let pointerLocation = NSEvent.mouseLocation")
        && screen.contains("guard lastPlaybackChromePointerLocation != pointerLocation else")
        && screen.contains("lastPlaybackChromePointerLocation = NSEvent.mouseLocation")
        && screen.contains("TapGesture(count: 1)")
        && screen.contains("togglePlaybackFromPointer()")
        && screen.contains("private func schedulePlaybackChromeAutoHide()")
        && screen.contains(".onChange(of: isInspectorVisible)")
        && screen.contains("if inspectorVisible {")
        && screen.contains("revealPlaybackChrome(scheduleHide: false)")
        && screen.contains("schedulePlaybackChromeAutoHide()")
        && screen.contains("private func hidePlaybackChromeForPointerExit()")
        && screen.contains("private func clampedPlaybackChromeOffset")
        && screen.contains("playbackChromeStoredOffset = clampedPlaybackChromeOffset")
        && screen.contains("onDragChanged: { translation in")
        && screen.contains("onDragEnded: { translation in")
        && screen.contains(".position(playbackChromeBasePosition(in: geometry.size))")
        && screen.contains(".offset(playbackChromeCurrentOffset(in: geometry.size))")
        && screen.contains("Task.sleep(nanoseconds: 2_000_000_000)")
        && screen.contains("private func playbackChromeHoverChanged(_ hovering: Bool)")
        && !screen.contains("revealPlaybackChrome(scheduleHide: false)\n        } else {\n            schedulePlaybackChromeAutoHide()")
        && !screen.contains("!isPointerOverPlaybackChrome,\n              !hasActiveVideoPopup")
        && screen.contains("private var shouldShowPlaybackChrome: Bool"),
    "video playback chrome should appear on pointer movement, remain draggable, and hide after two seconds of inactivity even while the pointer rests over its controls"
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
    screen.contains("if model.currentURL != nil {\n                    VideoControlsView(")
        && screen.contains(".opacity(shouldShowPlaybackChrome ? 1 : 0)")
        && screen.contains(".allowsHitTesting(shouldShowPlaybackChrome)")
        && screen.contains(".accessibilityHidden(!shouldShowPlaybackChrome)")
        && !screen.contains(".transition(.move(edge: .bottom).combined(with: .opacity))"),
    "video playback chrome should fade at a stable position like IINA instead of moving in from the bottom"
)
require(
    presenter.contains("final class VideoWindowPresenter: NSObject, NSWindowDelegate")
        && presenter.contains("window.collectionBehavior.insert(.fullScreenPrimary)")
        && presenter.contains("window.titlebarAppearsTransparent = false")
        && !presenter.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)")
        && !app.contains(".toolbar(.hidden, for: .windowToolbar)"),
    "dedicated Video window should retain standard native traffic lights for system fullscreen"
)
require(
    !detailView.contains("VideoPlayerScreen")
        && detailView.contains("case .video:")
        && detailView.contains("VideoLibraryView(onOpenVideo:"),
    "main detail should expose the local video library while leaving playback lifecycle to the dedicated Video window"
)
require(
    screen.contains("let isActive: Bool")
        && (
            screen.contains(".onChange(of: isActive)")
                || screen.contains(".onChange(of: isActive, initial: true)")
        )
        && screen.contains("if isActive {")
        && screen.contains("registerKeyboardShortcuts()")
        && screen.contains("unregisterKeyboardShortcuts()"),
    "dedicated Video window should register shortcuts only while it is the active key window"
)
require(
    profileCoordinator.contains("enum ProfileActivationCoordinator")
        && profileCoordinator.contains("ProfileSettingsStore.shared.activate")
        && profileCoordinator.contains("DictionaryManager.shared.activateProfile")
        && profileCoordinator.contains("AnkiManager.shared.activateProfile"),
    "Profile activation should have one coordinator for Profile settings, dictionaries and Anki"
)
require(
    screen.contains("profileID: resolvedVideoProfile.id")
        && popup.contains("twoColumnLayout: effectiveTwoColumnLayout")
        && popup.contains("ProfileSettingsStore.shared.dictionarySettings("),
    "Video lookup popup should render dictionary layout from the selected Video Profile"
)
require(
    rootView.contains("@State private var profileRepository = ProfileRepository.shared")
        && rootView.contains("private func activateCurrentProfileContext()")
        && rootView.contains(".onChange(of: selection)")
        && rootView.contains(".onChange(of: isKeyWindow)")
        && rootView.contains(".onChange(of: profileRepository.index.globalActiveProfileId)")
        && presenter.contains("activateVideoProfileIfNeeded()")
        && presenter.contains(".onChange(of: profileRepository.storedVideoProfileID)"),
    "main and Video roots should activate their Profile context only when their window is key"
)
require(
    !screen.contains("ProfileSettingsStore.shared.activate")
        && !screen.contains("DictionaryManager.shared.activateProfile")
        && !screen.contains("AnkiManager.shared.activateProfile")
        && !profilesView.contains("ProfileSettingsStore.shared.activate")
        && !profilesView.contains("DictionaryManager.shared.activateProfile")
        && !profilesView.contains("AnkiManager.shared.activateProfile"),
    "Video and Profiles child views should persist selections without directly claiming shared Profile services"
)
require(
    screen.contains(".ignoresSafeArea(.container, edges: .top)"),
    "video playback surface should extend into the hidden toolbar safe area so the top strip can show video"
)
require(
    !screen.contains("ToolbarItemGroup(placement: .primaryAction)")
        && screen.contains("WindowDragGesture()")
        && !screen.contains("toggleSidebar()")
        && !screen.contains("videoTopControls"),
    "dedicated Video window should retain only a drag strip in the top content area"
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
    screen.contains("let isTranscriptSidebarTab = selectedStudySidebarTab == .transcript")
        && screen.contains("let isChaptersSidebarTab = selectedStudySidebarTab == .chapters")
        && screen.contains("let sidebarTranscript = isTranscriptSidebarTab")
        && screen.contains("let sidebarChapters = isChaptersSidebarTab")
        && screen.contains("let sidebarCurrentTime = (isTranscriptSidebarTab || isChaptersSidebarTab)")
        && screen.contains("transcript: sidebarTranscript")
        && screen.contains("chapters: sidebarChapters")
        && screen.contains("currentTime: sidebarCurrentTime"),
    "video history sidebar should not receive hot playback transcript/chapter/currentTime state while the history tab is selected"
)
require(
    screen.contains("private static let inspectorOverlayTrailingInset: CGFloat = 16")
        && screen.contains("private static let inspectorOverlayVerticalInset: CGFloat = 16")
        && screen.contains(".padding(.vertical, Self.inspectorOverlayVerticalInset)")
        && screen.contains(".padding(.trailing, Self.inspectorOverlayTrailingInset)"),
    "video inspector should be inset from the video window edge"
)
require(
    screen.contains("maskEnabled: userConfig.videoSubtitleMaskEnabled")
        && screen.contains("maskMode: userConfig.videoSubtitleMaskMode")
        && screen.contains("maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius")
        && screen.contains("maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity")
        && screen.contains("fontFamily: userConfig.videoSubtitleFontFamily")
        && screen.contains("fontSize: userConfig.videoSubtitleFontSize")
        && screen.contains("isLookupPopupVisible: hasVisibleVideoPopup"),
    "video screen should wire subtitle mask and appearance user preferences into the transparent subtitle overlay"
)
require(
    screen.contains("private var hasActiveVideoPopup: Bool")
        && screen.contains("!lookup.presentation.popups.isEmpty")
        && screen.contains("private var hasVisibleVideoPopup: Bool")
        && screen.contains("lookup.presentation.popups.contains { $0.showPopup }"),
    "video subtitle masks should reveal only for visible lookup popups while popup-stack lifecycle checks keep using the active stack"
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
        && inspector.contains("VideoInspectorSegmentedPicker(")
        && inspector.contains("minSegmentWidth: 62")
        && inspector.contains("fillsWidth: true")
        && !inspector.contains("NativeGlassSegmentedPicker(")
        && !inspector.contains("VideoInspectorSwiftUIGlassSegmentedControl")
        && !inspector.contains("ControlGroup {")
        && !inspector.contains(".buttonStyle(.glassProminent)")
        && !inspector.contains(".shadow(")
        && !inspector.contains("NSSegmentedControl")
        && inspector.contains("VideoInspectorSectionGlassSurface")
        && inspector.contains("VideoInspectorGlassButtonStyle")
        && !inspector.contains("SubtitleTranscriptView"),
    "video inspector should share the same NativeGlassSegmentedPicker style as the Appearance theme switch"
)
require(
    inspectorState.contains("struct VideoInspectorState: Equatable")
        && inspector.contains("let state: VideoInspectorState")
        && !inspector.contains("let snapshot: VideoPlaybackSnapshot")
        && playerViewModel.contains("var inspectorState = VideoInspectorState()")
        && playerViewModel.contains("let nextInspectorState = VideoInspectorState(snapshot: snapshot)")
        && inspector.contains("extension VideoInspectorView: Equatable")
        && screen.contains("VideoInspectorView(")
        && screen.contains("state: model.inspectorState")
        && screen.contains(".equatable()"),
    "video inspector should receive a stable state slice without playback currentTime so playback ticks do not rebuild the whole inspector"
)
require(
    countOccurrences(inspector, of: ".glassEffect(") == 1
        && inspector.contains("private static let subtitleFontFamilies: [String] ="),
    "video inspector should keep only one outer glass effect and cache font families to avoid per-tick glass/font work"
)
require(
    inspector.contains("NativeGlassMenuPicker(")
        && inspector.contains("selection: subtitleFontFamily")
        && inspector.contains("values: [\"\"] + Self.subtitleFontFamilies")
        && !inspector.contains("Picker(selection: subtitleFontFamily)"),
    "video inspector subtitle font control should match the Appearance font menu picker"
)
require(
    mpvClient.contains("HSMpvTimePositionStateEmitInterval")
        && mpvClient.contains("_lastTimePositionStateEmitClock")
        && mpvClient.contains("_lastEmittedStateTimePosition")
        && mpvClient.contains("shouldEmitTimePositionState")
        && mpvClient.contains("shouldEmitState = [self shouldEmitTimePositionState]")
        && mpvClient.contains("if (!shouldEmitState) {")
        && mpvClient.contains("return;"),
    "mpv time-pos should throttle SwiftUI state emission so video playback ticks do not rebuild inspector scroll content every frame"
)
require(
    inspector.contains("subtitleMaskSection")
        && inspector.contains("subtitleMaskBlurRadius")
        && inspector.contains("subtitleMaskHiddenOpacity")
        && inspector.contains("Mask subtitles until hover"),
    "video inspector should expose subtitle mask toggle, mode and strength controls in the Subtitles tab"
)
require(
    inspector.contains("private static let subtitleTimingMinimumMilliseconds = -10_000")
        && inspector.contains("private static let subtitleTimingMaximumMilliseconds = 10_000")
        && inspector.contains("private static let subtitleTimingLargeStepMilliseconds = 1_000")
        && inspector.contains("private static let subtitleTimingSmallStepMilliseconds = 50")
        && inspector.contains("subtitleTimingSection")
        && inspector.contains("Slider(")
        && inspector.contains("in: Double(Self.subtitleTimingMinimumMilliseconds)...Double(Self.subtitleTimingMaximumMilliseconds)")
        && inspector.contains("step: Double(Self.subtitleTimingSmallStepMilliseconds)")
        && inspector.contains("applySubtitleTimingMilliseconds(current - Self.subtitleTimingLargeStepMilliseconds)")
        && inspector.contains("applySubtitleTimingMilliseconds(current - Self.subtitleTimingSmallStepMilliseconds)")
        && inspector.contains("applySubtitleTimingMilliseconds(current + Self.subtitleTimingSmallStepMilliseconds)")
        && inspector.contains("applySubtitleTimingMilliseconds(current + Self.subtitleTimingLargeStepMilliseconds)")
        && inspector.contains("TextField(\"Offset\", text: $subtitleTimingInputText)")
        && inspector.contains("Image(systemName: \"keyboard\")"),
    "video subtitle timing should expose millisecond slider/input controls with +/-1000ms and +/-50ms actions over -10000...10000ms"
)
require(
    screen.contains("VideoShortcutActions.subtitleEarlier.id")
        && screen.contains("adjustSubtitleDelayWithOSD(by: -0.05)")
        && screen.contains("VideoShortcutActions.subtitleLater.id")
        && screen.contains("adjustSubtitleDelayWithOSD(by: 0.05)")
        && screen.contains("adjustAudioDelayWithOSD(by: -0.5)")
        && screen.contains("adjustAudioDelayWithOSD(by: 0.5)"),
    "video subtitle timing shortcuts should use 50ms steps while audio timing keeps 500ms steps"
)
require(
    mpvClient.contains("mpv_set_property_string(_handle, \"sub-visibility\", \"no\")")
        && mpvClient.contains("shouldRenderNativeImageSubtitles ? \"yes\" : \"no\"")
        && !mpvClient.contains("cues.count > 0 ? \"no\" : \"yes\""),
    "mpv should never restore native text subtitles during cue gaps while still supporting selected bitmap tracks"
)
require(
    mpvClient.contains("std::atomic<uint64_t> _loadGeneration")
        && mpvClient.contains("_loadGeneration.fetch_add(1")
        && mpvClient.contains("isCurrentLoadGeneration")
        && mpvClient.contains("guardedLoadGeneration"),
    "mpv callbacks queued by an older episode load must be discarded before they can overwrite the new episode restore state"
)
require(
    miningHistorySidebar.contains("struct VideoMiningHistorySidebar")
        && miningHistorySidebar.contains("static let minWidth: CGFloat = 320")
        && miningHistorySidebar.contains("static let defaultWidth: CGFloat = 340")
        && miningHistorySidebar.contains("static let maxWidth: CGFloat = 560")
        && miningHistorySidebar.contains("frame(minWidth: Self.minWidth, idealWidth: Self.defaultWidth, maxWidth: .infinity)")
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
        && miningHistorySidebar.contains("VideoStudyListCard {\n            onJump(item)")
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
    studyListCard.contains("struct VideoStudyListCard")
        && studyListCard.contains("VideoStudyListCardSurface")
        && studyListCard.contains("backgroundTint")
        && studyListCard.contains("onHover")
        && !studyListCard.contains(".glassEffect(")
        && !studyListCard.contains("withAnimation(.smooth(duration: 0.16))"),
    "video study lists should use lightweight row tint instead of per-row glass or hover animation during playback scrolling"
)
require(
    miningHistorySidebar.contains("VideoStudyListCard(")
        && miningHistorySidebar.contains("LazyVStack(alignment: .leading, spacing: 8)")
        && miningHistorySidebar.contains("VideoStudySidebarBackground")
        && transcriptView.contains("VideoStudyListCard(")
        && transcriptView.contains("LazyVStack(spacing: 8)"),
    "mining history, transcript and chapters should use the same spaced card-list presentation"
)
require(
    transcriptView.contains("extension SubtitleTranscriptView: Equatable")
        && transcriptView.contains("lhs.currentRowID == rhs.currentRowID")
        && transcriptView.contains("private func followPlayback(")
        && transcriptView.contains("proxy.scrollTo(row.id, anchor: .center)")
        && !transcriptView.contains("withAnimation(.smooth(duration: 0.18))")
        && miningHistorySidebar.contains("SubtitleTranscriptView(")
        && miningHistorySidebar.contains(".equatable()"),
    "video transcript sidebar should skip playback ticks inside the same subtitle row and avoid animated auto-scroll"
)
require(
    ambientBackdrop.contains("struct VideoAmbientBackdrop")
        && ambientBackdrop.contains("VideoAmbientPresentation")
        && ambientBackdrop.contains("usesBlurredLetterbox: false")
        && ambientBackdrop.contains("workspaceCornerRadius: 0")
        && screen.contains("guard ambientPresentation.usesBlurredLetterbox else")
        && ambientModel.contains("playbackInterval: TimeInterval = 3.0"),
    "windowed playback should disable current-frame ambient blur while keeping the isolated preview path dormant"
)
require(
    playbackEngine.contains("captureAmbientPreview(maximumDimension:")
        && mpvClient.contains("screenshot-raw")
        && mpvClient.contains("mpv_command_ret")
        && mpvClient.contains("dispatch_sync(_ambientPreviewQueue")
        && windowChrome.contains("private(set) var isFullScreen")
        && screen.contains("VideoAmbientBackdrop("),
    "ambient preview plumbing should stay behind the playback boundary and drain before shutdown even while the UI disables it"
)
require(
    mpvClient.contains("screenshot-to-file")
        && mpvClient.contains("\"video\"")
        && !ambientBackdrop.contains("captureScreenshot"),
    "mining screenshots should remain on mpv's video-only capture path instead of capturing the ambient UI"
)
require(
    screen.contains("@State private var miningHistory = VideoMiningHistoryStore()")
        && screen.contains("mineCurrentSubtitle()")
        && screen.contains("miningHistory.record(")
        && screen.contains("VideoMiningHistoryNavigationResolver.resolve(")
        && screen.contains("copyMiningHistorySubtitle(")
        && screen.contains("showMiningHistoryNotice(.copied)")
        && screen.contains("VideoShortcutActions.mineCurrentSubtitle.id")
        && controls.contains("Label(\"Mining History\", systemImage: \"clock.arrow.circlepath\")"),
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
    screen.contains("let sidebarPendingABLoopStart = isTranscriptSidebarTab")
        && screen.contains("let sidebarABLoop = isTranscriptSidebarTab ? model.snapshot.abLoop : nil")
        && screen.contains("pendingABLoopStart: sidebarPendingABLoopStart")
        && screen.contains("abLoop: sidebarABLoop")
        && screen.contains("model.setABLoopStart(at: time)")
        && screen.contains("model.setABLoopEnd(at: time)")
        && miningHistorySidebar.contains("let pendingABLoopStart: TimeInterval?")
        && miningHistorySidebar.contains("let abLoop: VideoABLoop?")
        && miningHistorySidebar.contains("onSetTranscriptABLoopStart")
        && miningHistorySidebar.contains("onSetTranscriptABLoopEnd")
        && transcriptView.contains("abLoopMarkerButton(\"A\"")
        && transcriptView.contains("abLoopMarkerButton(\"B\"")
        && transcriptView.contains("onSetABLoopStart(row.startTime)")
        && transcriptView.contains("onSetABLoopEnd(row.endTime)"),
    "video transcript rows should expose A/B loop markers and wire them to playback state"
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
    "video inspector should not fall back to material segmented pickers or bordered buttons"
)

print("Video Liquid Glass contract tests passed")
