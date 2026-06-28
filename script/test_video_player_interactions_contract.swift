import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func maybeSource(_ path: String) -> String? {
    try? source(path)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let controls = try source("Features/Video/VideoControlsView.swift")
let subtitles = try source("Features/Video/Subtitles/SubtitleOverlayView.swift")
let screen = try source("Features/Video/VideoPlayerScreen.swift")
let lookupCoordinator = try source("Features/Video/VideoLookupCoordinator.swift")
let playbackEngine = try source("Features/Video/Playback/PlaybackEngine.swift")
let mpvEngine = try source("Features/Video/Playback/MpvPlayerEngine.swift")
let clientHeader = try source("Features/Video/Playback/HSMpvClient.h")
let clientImplementation = try source("Features/Video/Playback/HSMpvClient.mm")
let thumbnailStore = maybeSource("Features/Video/VideoThumbnailStore.swift")

require(
    subtitles.contains("let isPlaybackPaused: Bool")
        && subtitles.contains("isHovering || isLookupPopupVisible || isPlaybackPaused")
        && screen.contains("isPlaybackPaused: !model.snapshot.isPlaying"),
    "video subtitle masks should reveal while playback is paused"
)

require(
    !controls.contains("VideoVolumeScrollBridge")
        && screen.contains("VideoSurfaceScrollBridge(")
        && screen.contains("isEnabled: shouldHandleVideoSurfaceVolumeScroll")
        && screen.contains("onScroll: { delta in")
        && screen.contains("adjustVolume(by: delta)")
        && screen.contains("private var shouldHandleVideoSurfaceVolumeScroll: Bool")
        && screen.contains("model.currentURL != nil")
        && screen.contains("!hasActiveVideoPopup")
        && !screen.contains("&& !isInspectorVisible")
        && !screen.contains("&& !isMiningHistoryVisible")
        && screen.contains("NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)")
        && screen.contains("excludedRects: videoSurfaceVolumeScrollExcludedRects(in: geometry.size)")
        && screen.contains("VideoInspectorOverlayFramePreferenceKey")
        && screen.contains("inspectorOverlayFrame")
        && screen.contains("excludedRects.contains(where: { $0.contains(localPoint) })")
        && !screen.contains("excludedRects.contains { $0.contains(localPoint) }")
        && screen.contains("VideoVolumeScrollDelta.adjustment(")
        && screen.contains("event.hasPreciseScrollingDeltas")
        && screen.contains(".allowsHitTesting(false)"),
    "video surface should support mouse wheel and precise touchpad volume scrolling while study sidebar or inspector are open without stealing inspector scroll"
)

require(
    screen.contains("hasPreciseScrollingDeltas: Bool")
        && screen.contains("return deltaY > 0 ? Self.wheelStep : -Self.wheelStep")
        && screen.contains("let preciseDelta = deltaY * Self.preciseScale"),
    "video surface volume scroll normalization should use notched steps for mouse wheels and smooth deltas for touchpads"
)

require(
    !controls.contains("NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)"),
    "video controls should not own the wheel monitor because scrolling over the video surface drives volume"
)

require(
    playbackEngine.contains("struct VideoTimelinePreview: Equatable")
        && thumbnailStore?.contains("actor VideoThumbnailScheduler") == true
        && !playbackEngine.contains("captureTimelinePreviewPNGData(at time: TimeInterval")
        && !mpvEngine.contains("func captureTimelinePreviewPNGData("),
    "video timeline preview should keep time-only hover previews while library thumbnails remain isolated in VideoThumbnailScheduler"
)

require(
    controls.contains("let timelinePreview: VideoTimelinePreview?")
        && controls.contains("var onTimelinePreviewTimeChanged: (TimeInterval?) -> Void")
        && controls.contains("let layout: VideoControlBarLayout")
        && controls.contains("let availableWidth: CGFloat")
        && controls.contains("static func metrics(for layout: VideoControlBarLayout) -> VideoControlsMetrics")
        && controls.contains("compactBottomControls")
        && controls.contains("floatingControls")
        && controls.contains("compactBottomScrim")
        && controls.contains("activeChromeWidth")
        && controls.contains("bottomInset: 0")
        && controls.contains(".frame(width: activeChromeWidth, height: Self.metrics(for: .compactBottom).chromeSize.height, alignment: .bottom)")
        && !controls.contains(".padding(.bottom, 4)")
        && !controls.contains(".padding(.bottom, 8)")
        && !controls.contains("VideoCompactControlSurface")
        && controls.contains("timelineProgressControl")
        && controls.contains("VideoProgressHoverBridge(")
        && controls.contains("timelinePreviewBubble")
        && controls.contains("VideoProgressFramePreferenceKey")
        && controls.contains(".zIndex(20)")
        && controls.contains("onTimelinePreviewTimeChanged(time)")
        && controls.contains("Text(VideoTimeFormatter.string(from: preview.time))")
        && !controls.contains("timelinePreviewImage")
        && !controls.contains("previewImage(from:")
        && !controls.contains("NSImage(data:")
        && !controls.contains("Image(systemName: \"photo\")"),
    "video controls should keep the time preview without rendering frame thumbnail placeholders when previews are disabled"
)

require(
    screen.contains("VideoControlsView.metrics(for: userConfig.videoControlBarLayout)")
        && screen.contains("layout: userConfig.videoControlBarLayout")
        && screen.contains("availableWidth: geometry.size.width")
        && screen.contains("playbackChromeSize(in: size)")
        && screen.contains("playbackChromeBottomEdgeInset")
        && screen.contains("bottomClearance: videoControlsMetrics.subtitleBottomClearance")
        && screen.contains("bottomInset: videoControlsMetrics.popupBottomInset")
        && screen.contains("private var videoControlsMetrics: VideoControlsMetrics"),
    "video screen should make playback chrome, popup, and subtitle clearance layout-aware"
)

require(
    subtitles.contains("let bottomClearance: CGFloat")
        && subtitles.contains(".padding(.bottom, bottomClearance + verticalPositionOffset)")
        && !subtitles.contains("private let subtitleBottomClearance: CGFloat = 142"),
    "video subtitle overlay should receive bottom clearance from the active control layout"
)

require(
    screen.contains("@State private var timelinePreview: VideoTimelinePreview?")
        && screen.contains("timelinePreview: timelinePreview")
        && screen.contains("onTimelinePreviewTimeChanged: { time in")
        && screen.contains("updateTimelinePreview(at: time)")
        && !screen.contains("startTimelinePreviewPrewarmIfAvailable()")
        && !screen.contains("timelinePreviewPrewarmTask")
        && !screen.contains("timelinePreviewDemandTask")
        && !screen.contains("model.engine.captureTimelinePreviewPNGData")
        && screen.contains("clearTimelinePreview(clearCache: true)"),
    "video screen should avoid CPU-heavy thumbnail generation during normal playback"
)

require(
    screen.contains("suspendVideoThumbnailsForVideoSession()")
        && screen.contains("resumeVideoThumbnailsForVideoSession()")
        && screen.contains("await VideoThumbnailScheduler.shared.suspend(reason: .playback)")
        && screen.contains("await VideoThumbnailScheduler.shared.resume(reason: .playback)")
        && screen.contains("if newURL != nil {")
        && screen.contains(".onDisappear {")
        && !screen.contains("if isPlaying {\n                    suspendVideoThumbnailsFor")
        && !screen.contains("if !model.snapshot.isPlaying {\n                    resumeVideoThumbnailsFor"),
    "video sessions should suspend library thumbnail generation from media open until the player closes, independent of pause/play state"
)

require(
    lookupCoordinator.contains("suspendVideoThumbnailsForLookupIfNeeded()")
        && lookupCoordinator.contains("resumeVideoThumbnailsForLookupIfNeeded()")
        && lookupCoordinator.contains("await VideoThumbnailScheduler.shared.suspend(reason: .lookup)")
        && lookupCoordinator.contains("await VideoThumbnailScheduler.shared.resume(reason: .lookup)")
        && lookupCoordinator.contains("guard self.presentation.popups.isEmpty else")
        && lookupCoordinator.contains("resumePlaybackAfterPopupIfNeeded(player: player)"),
    "video lookup popups should preemptively suspend library thumbnails until the popup stack closes"
)

print("Video player interaction contract tests passed")
