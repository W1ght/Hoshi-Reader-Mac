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
let screen = try source("Features/Video/VideoPlayerScreen.swift")
let lookup = try source("Features/Video/VideoLookupCoordinator.swift")
let rootView = try source("NativeMac/NativeMacRootView.swift")

require(
    controls.contains("primaryControlGroup")
        && !controls.contains("secondaryControlStrip")
        && controls.contains("onToggleInspector")
        && !controls.contains("moreControlsMenu"),
    "video controls should use a single-row OSC with a dedicated inspector toggle"
)
require(
    controls.contains("VideoFloatingGlassSurface")
        && controls.contains("glassEffect(.regular.interactive()"),
    "video controls should use a single interactive Liquid Glass surface"
)
require(
    controls.contains("Capsule(style: .continuous)"),
    "video controls should render as a compact single-row glass pill"
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
        && subtitles.contains("let maskHiddenOpacity: Double"),
    "subtitle overlay should receive text-only subtitle mask configuration"
)
require(
    subtitles.contains("@State private var isHovering = false")
        && subtitles.contains(".onHover { hovering in")
        && subtitles.contains("private var maskedBlurRadius: CGFloat")
        && subtitles.contains("private var maskedOpacity: Double")
        && subtitles.contains(".blur(radius: maskedBlurRadius)")
        && subtitles.contains(".opacity(maskedOpacity)"),
    "subtitle overlay should reveal masked subtitles on hover using blur or opacity text effects"
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
        && !screen.contains("model.selectTrack(type: .subtitle, id: nil)"),
    "external subtitle imports should be loaded into mpv instead of disabling subtitle tracks"
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
        && interactiveSubtitles.contains("return nil"),
    "interactive subtitle views should pass through clicks outside rendered text so they do not block controls or inspector"
)
require(
    screen.contains("onTapOutside: {")
        && screen.contains("lookup.closeAll(player: model)"),
    "video popup outside taps should close the popup stack and restore video playback state"
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
    lookup.contains("Logger(subsystem: \"de.manhhao.hoshi\", category: \"VideoLookup\")")
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
        && screen.contains("maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity"),
    "video screen should wire subtitle mask user preferences into the transparent subtitle overlay"
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
        && inspector.contains("case transcript"),
    "video inspector should provide IINA-style tabs for episodes, video, audio, subtitles and transcript"
)
require(
    inspector.contains("VideoInspectorGlassSurface")
        && inspector.contains("NativeGlassSegmentedPicker(")
        && inspector.contains("VideoInspectorSectionGlassSurface")
        && inspector.contains("VideoInspectorGlassButtonStyle")
        && inspector.contains("SubtitleTranscriptView"),
    "video inspector should use shared glass segmented controls, glass sections, glass buttons and host the transcript view"
)
require(
    inspector.contains("subtitleMaskSection")
        && inspector.contains("subtitleMaskBlurRadius")
        && inspector.contains("subtitleMaskHiddenOpacity")
        && inspector.contains("Mask subtitles until hover"),
    "video inspector should expose subtitle mask toggle, mode and strength controls in the Subtitles tab"
)
require(
    miningHistorySidebar.contains("struct VideoMiningHistorySidebar")
        && miningHistorySidebar.contains("frame(minWidth: 320, idealWidth: 340, maxWidth: 380)")
        && miningHistorySidebar.contains("onSeek(item.cueStart)")
        && miningHistorySidebar.contains("NSPasteboard.general.setString")
        && miningHistorySidebar.contains("Clear Mining History"),
    "video mining history should be a fixed-width sidebar with seek, copy, delete and clear actions"
)
require(
    screen.contains("@State private var miningHistory = VideoMiningHistoryStore()")
        && screen.contains("onMiningStarted:")
        && screen.contains("miningHistory.recordPending")
        && screen.contains("onMiningFinished:")
        && screen.contains("miningHistory.update(")
        && screen.contains("Label(\"Mining History\", systemImage: \"clock.arrow.circlepath\")"),
    "video mining should record pending history items and update them from the Anki mining result"
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
