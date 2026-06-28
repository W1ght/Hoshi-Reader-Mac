#if HOSHI_VIDEO
import AppKit
@preconcurrency import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let videoScreenLog = Logger(subsystem: "moe.shishamo.hoshi", category: "VideoScreen")

private nonisolated final class DroppedFileURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private final class VideoPlayerModelStore: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    let model = VideoPlayerViewModel(engine: MpvPlayerEngine())
}

struct VideoPlayerScreen: View {
    let isActive: Bool
    let openRequest: VideoWindowOpenRequest?
    let onConsumeOpenRequest: (UUID) -> Void
    let windowChrome: VideoWindowChromeController

    @Environment(UserConfig.self) private var userConfig
    @Environment(ShortcutManager.self) private var shortcutManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var modelStore = VideoPlayerModelStore()
    @State private var openGate = VideoWindowOpenGate()
    @State private var subtitles = VideoSubtitleController()
    @State private var lookup = VideoLookupCoordinator()
    @State private var miningHistory = VideoMiningHistoryStore()
    @State private var ambientBackdrop = VideoAmbientBackdropModel()
    @State private var profileRepository = ProfileRepository.shared
    @State private var isInspectorVisible = false
    @State private var isMiningHistoryVisible = false
    @State private var selectedStudySidebarTab: VideoStudySidebarTab = .history
    @State private var isPlaybackChromeVisible = true
    @State private var isPointerInsidePlayerSurface = true
    @State private var lastPlaybackChromePointerLocation: CGPoint?
    @State private var areSubtitlesVisible = true
    @State private var lastSelectedSubtitleTrackID: Int?
    @State private var playbackChromeDragOffset: CGSize = .zero
    @State private var playbackChromeStoredOffset: CGSize = .zero
    @State private var selectedInspectorTab: VideoInspectorTab = .subtitles
    @State private var shortcutRegistrationIDs: [UUID] = []
    @State private var pendingFileImportKind: VideoFileImportKind?
    @State private var activeFileImportKind: VideoFileImportKind?
    @State private var playbackChromeAutoHideTask: Task<Void, Never>?
    @State private var miningHistoryNotice: VideoMiningHistoryNotice?
    @State private var miningHistoryNoticeTask: Task<Void, Never>?
    @State private var pendingHistoryEmbeddedSubtitleTrackID: Int?
    @State private var subtitleTrackExtractionTask: Task<Void, Never>?
    @State private var activeSubtitleTrackExtractionKey: String?
    @State private var isLoadingPrimarySubtitle = false
    @State private var shouldSkipNextAutomaticSubtitleRestore = false
    @State private var timelinePreview: VideoTimelinePreview?
    @State private var timelinePreviewRequestedTime: TimeInterval?
    @AppStorage("videoStudySidebarWidth") private var studySidebarWidth: Double = Double(VideoMiningHistorySidebar.defaultWidth)
    @State private var studySidebarDragStartWidth: CGFloat?
    @State private var inspectorOverlayFrame: CGRect = .zero

    private static let playbackChromeSize = CGSize(
        width: 760,
        height: VideoControlsView.timelinePreviewChromeHeight
    )
    private static let playbackChromeEdgeInset: CGFloat = 16
    private static let playbackChromeBottomInset: CGFloat = 24
    private static let inspectorOverlayTrailingInset: CGFloat = 16
    private static let inspectorOverlayVerticalInset: CGFloat = 16
    private static let minimumVideoSurfaceWidth: CGFloat = 360
    private static let videoPlayerCoordinateSpace = "video-player"

    private static let subtitleFileExtensions = ["srt", "vtt", "ass", "ssa"]

    private let subtitleTypes: [UTType] = Self.subtitleFileExtensions.compactMap {
        UTType(filenameExtension: $0)
    }

    private var model: VideoPlayerViewModel {
        modelStore.model
    }

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        lifecycleFocusedContent
    }

    private var lifecycleFileImportContent: some View {
        observedContent
            .fileImporter(
                isPresented: fileImporterPresentation,
                allowedContentTypes: (pendingFileImportKind ?? activeFileImportKind)?.allowedContentTypes(
                    mediaTypes: VideoMediaTypes.contentTypes,
                    subtitleTypes: subtitleTypes
                ) ?? VideoMediaTypes.contentTypes,
                allowsMultipleSelection: false
            ) { result in
                guard let kind = activeFileImportKind ?? pendingFileImportKind else { return }
                pendingFileImportKind = nil
                activeFileImportKind = nil
                handleFileImport(result, kind: kind)
            }
    }

    private var lifecycleActiveContent: some View {
        lifecycleFileImportContent
            .onAppear {
                synchronizePlaybackPreferences()
                miningHistory.updateLimit(userConfig.videoMiningHistoryLimit)
                installEmbeddedSubtitleHandler()
                synchronizeSelectedSubtitleTrack()
                if isActive {
                    registerKeyboardShortcuts()
                }
                schedulePlaybackChromeAutoHide()
            }
            .onChange(of: isActive, initial: true) { _, isActive in
                if isActive {
                    registerKeyboardShortcuts()
                    revealPlaybackChrome(scheduleHide: true)
                    refreshAmbientBackdrop(reason: .load)
                } else {
                    unregisterKeyboardShortcuts()
                    ambientBackdrop.suspend(clear: false)
                }
            }
    }

    private var lifecyclePreferenceContent: some View {
        lifecycleActiveContent
            .onChange(of: userConfig.videoAutoPlayNext) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoRememberPlaybackPosition) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoHardwareDecodingEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoDeinterlacingEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoHDREnhancementEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoBrightness) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoContrast) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoSaturation) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoGamma) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoHue) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoMiningHistoryLimit) { _, limit in
                miningHistory.updateLimit(limit)
            }
    }

    private var lifecycleExternalInputContent: some View {
        lifecyclePreferenceContent
            .onChange(of: openRequest, initial: true) { _, request in
                handleExternalOpenRequest(request)
            }
    }

    private var lifecycleChromeContent: some View {
        lifecycleExternalInputContent
            .onChange(of: isInspectorVisible) { _, inspectorVisible in
                if inspectorVisible {
                    revealPlaybackChrome(scheduleHide: false)
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
            .onChange(of: shouldShowPlaybackChrome, initial: true) { _, isVisible in
                windowChrome.setChromeVisible(isVisible)
            }
            .onChange(of: videoWindowAspectRatio, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: isMiningHistoryVisible, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: studySidebarWidth, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: windowChrome.isFullScreen, initial: true) { _, isFullScreen in
                synchronizeVideoWindowLayout()
                if isFullScreen {
                    ambientBackdrop.suspend(clear: false)
                } else {
                    refreshAmbientBackdrop(reason: .load)
                }
            }
    }

    private var lifecycleModelContent: some View {
        lifecycleChromeContent
            .onChange(of: model.snapshot.tracks) { _, _ in
                restorePendingHistorySubtitleTrackIfAvailable()
                restoreRememberedSubtitleSelectionOrAutoload()
                synchronizeSelectedSubtitleTrack()
            }
            .onChange(of: model.snapshot.isLoaded) { _, isLoaded in
                guard isLoaded else { return }
                restoreRememberedSubtitleSelectionOrAutoload()
                refreshAmbientBackdrop(reason: .load)
                if !model.snapshot.isPlaying {
                    resumeVideoThumbnailsForPlayback()
                }
            }
            .onChange(of: model.snapshot.isPlaying) { wasPlaying, isPlaying in
                if isPlaying {
                    suspendVideoThumbnailsForPlayback()
                } else {
                    resumeVideoThumbnailsForPlayback()
                }
                if wasPlaying, !isPlaying {
                    refreshAmbientBackdrop(reason: .pause)
                }
            }
            .onChange(of: model.loadGeneration) { _, generation in
                ambientBackdrop.reset(for: generation)
                handleVideoLoadGeneration()
            }
    }

    private var lifecycleSceneContent: some View {
        lifecycleModelContent
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    hidePlaybackChromeForPointerExit()
                }
            }
    }

    private var lifecycleDisappearContent: some View {
        lifecycleSceneContent
            .onDisappear {
                unregisterKeyboardShortcuts()
                playbackChromeAutoHideTask?.cancel()
                miningHistoryNoticeTask?.cancel()
                subtitleTrackExtractionTask?.cancel()
                clearTimelinePreview(clearCache: true)
                ambientBackdrop.suspend(clear: true)
                resumeVideoThumbnailsForPlayback()
                model.engine.onEmbeddedSubtitleCuesChanged = nil
                lookup.closeAll(player: model)
                model.shutdown()
            }
    }

    private var lifecycleAlertContent: some View {
        lifecycleDisappearContent
            .alert("Video Error", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? subtitles.errorMessage ?? "")
            }
    }

    private var lifecycleFocusedContent: some View {
        lifecycleAlertContent
            .focusedSceneValue(\.videoPlaybackCommandContext, videoPlaybackCommandContext)
    }

    private var observedContent: some View {
        playerSurface
            .ignoresSafeArea(.container, edges: .top)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDroppedItems(providers)
            }
            .onChange(of: model.snapshot.currentTime) { oldTime, time in
                subtitles.update(
                    time: time,
                    subtitleDelay: model.snapshot.subtitleDelay
                )
                refreshAmbientBackdrop(
                    reason: abs(time - oldTime) > 1.5 ? .seek : .playback
                )
            }
            .onChange(of: model.snapshot.subtitleDelay) { _, delay in
                subtitles.update(
                    time: model.snapshot.currentTime,
                    subtitleDelay: delay
                )
            }
            .onChange(of: model.currentURL) { oldURL, newURL in
                subtitleTrackExtractionTask?.cancel()
                subtitleTrackExtractionTask = nil
                activeSubtitleTrackExtractionKey = nil
                clearTimelinePreview(clearCache: true)
                if newURL != nil {
                    suspendVideoThumbnailsForPlayback()
                    revealPlaybackChrome(scheduleHide: true)
                } else {
                    resumeVideoThumbnailsForPlayback()
                    playbackChromeAutoHideTask?.cancel()
                    isPlaybackChromeVisible = true
                }
            }
    }

    private var playerSurface: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                videoSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if isMiningHistoryVisible {
                    let sidebarWidth = clampedStudySidebarWidth(
                        CGFloat(studySidebarWidth),
                        availableSize: geometry.size
                    )
                    let isTranscriptSidebarTab = selectedStudySidebarTab == .transcript
                    let isChaptersSidebarTab = selectedStudySidebarTab == .chapters
                    let sidebarTranscript = isTranscriptSidebarTab
                        ? subtitles.transcript
                        : SubtitleTranscript(primary: nil, secondary: nil)
                    let sidebarChapters = isChaptersSidebarTab ? model.snapshot.chapters : []
                    let sidebarCurrentTime = (isTranscriptSidebarTab || isChaptersSidebarTab)
                        ? model.snapshot.currentTime
                        : 0
                    let sidebarPendingABLoopStart = isTranscriptSidebarTab
                        ? model.pendingABLoopStart
                        : nil
                    let sidebarABLoop = isTranscriptSidebarTab ? model.snapshot.abLoop : nil
                    let sidebarIsTranscriptLoading = isTranscriptSidebarTab
                        && subtitles.isTranscriptLoading
                    let sidebarTranscriptErrorMessage = isTranscriptSidebarTab
                        ? subtitles.transcriptErrorMessage
                        : nil

                    VideoMiningHistorySidebar(
                        selectedTab: $selectedStudySidebarTab,
                        items: miningHistory.items,
                        transcript: sidebarTranscript,
                        chapters: sidebarChapters,
                        currentTime: sidebarCurrentTime,
                        pendingABLoopStart: sidebarPendingABLoopStart,
                        abLoop: sidebarABLoop,
                        isTranscriptLoading: sidebarIsTranscriptLoading,
                        transcriptErrorMessage: sidebarTranscriptErrorMessage,
                        onClose: {
                            withAnimation(.smooth(duration: 0.22)) {
                                isMiningHistoryVisible = false
                            }
                        },
                        onJump: { item in
                            navigateToHistoryItem(item)
                        },
                        onSeekTranscript: { time in
                            dismissVideoPopupsIfNeeded()
                            model.seek(to: time + model.snapshot.subtitleDelay)
                        },
                        onSetTranscriptABLoopStart: { time in
                            dismissVideoPopupsIfNeeded()
                            model.setABLoopStart(at: time)
                        },
                        onSetTranscriptABLoopEnd: { time in
                            dismissVideoPopupsIfNeeded()
                            model.setABLoopEnd(at: time)
                        },
                        onSeekChapter: { chapterID in
                            dismissVideoPopupsIfNeeded()
                            model.seekToChapter(chapterID)
                        },
                        onCopy: { item in
                            copyMiningHistorySubtitle(item)
                        },
                        onDelete: { id in
                            miningHistory.delete(id: id)
                        },
                        onClear: {
                            miningHistory.clear()
                        }
                    )
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .leading) {
                        VideoStudySidebarResizeHandle()
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        if studySidebarDragStartWidth == nil {
                                            studySidebarDragStartWidth = sidebarWidth
                                        }

                                        let startWidth = studySidebarDragStartWidth ?? sidebarWidth
                                        let nextWidth = startWidth - value.translation.width
                                        studySidebarWidth = Double(
                                            clampedStudySidebarWidth(
                                                nextWidth,
                                                availableSize: geometry.size
                                            )
                                        )
                                    }
                                    .onEnded { _ in
                                        studySidebarWidth = Double(
                                            clampedStudySidebarWidth(
                                                CGFloat(studySidebarWidth),
                                                availableSize: geometry.size
                                            )
                                        )
                                        studySidebarDragStartWidth = nil
                                    }
                            )
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .onHover { hovering in
                playerSurfaceHoverChanged(hovering)
            }
            .animation(.smooth(duration: 0.22), value: isMiningHistoryVisible)
        }
    }

    private func clampedStudySidebarWidth(
        _ width: CGFloat,
        availableSize: CGSize
    ) -> CGFloat {
        let availableMaxWidth = max(
            VideoMiningHistorySidebar.minWidth,
            min(
                VideoMiningHistorySidebar.maxWidth,
                availableSize.width - Self.minimumVideoSurfaceWidth
            )
        )
        let clampedWidth = min(max(width, VideoMiningHistorySidebar.minWidth), availableMaxWidth)
        return VideoWindowAspectLayout.aspectFittingSidebarWidth(
            contentSize: availableSize,
            videoAspectRatio: windowChrome.isFullScreen ? nil : videoWindowAspectRatio,
            proposedWidth: clampedWidth,
            minWidth: VideoMiningHistorySidebar.minWidth,
            maxWidth: availableMaxWidth
        )
    }

    private var videoSurface: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                ZStack(alignment: .trailing) {
                    videoCanvas
                    if isInspectorVisible {
                        inspectorOverlay
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: VideoInspectorOverlayFramePreferenceKey.self,
                                        value: proxy.frame(in: .named(Self.videoPlayerCoordinateSpace))
                                    )
                                }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .zIndex(10)
                    }
                }
                .animation(.smooth(duration: 0.22), value: isInspectorVisible)
                .coordinateSpace(name: Self.videoPlayerCoordinateSpace)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ambientPresentation.workspaceCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    if ambientPresentation.workspaceCornerRadius > 0 {
                        RoundedRectangle(
                            cornerRadius: ambientPresentation.workspaceCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                    }
                }

                ForEach(lookup.presentation.popups) { popup in
                    popupView(popup, screenSize: geometry.size)
                }

                if let miningHistoryNotice {
                    videoMiningHistoryNotice(miningHistoryNotice)
                        .padding(.top, 42)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var ambientPresentation: VideoAmbientPresentation {
        VideoAmbientPresentation.resolve(isFullScreen: windowChrome.isFullScreen)
    }

    private var videoWindowAspectRatio: CGFloat? {
        VideoWindowAspectLayout.videoAspectRatio(
            displaySize: model.snapshot.videoDisplaySize,
            override: model.snapshot.aspectRatio,
            rotation: model.snapshot.rotation
        )
    }

    private func synchronizeVideoWindowLayout() {
        windowChrome.setVideoLayout(
            videoAspectRatio: videoWindowAspectRatio,
            studySidebarWidth: CGFloat(studySidebarWidth),
            isStudySidebarVisible: isMiningHistoryVisible && !windowChrome.isFullScreen
        )
    }

    private func refreshAmbientBackdrop(reason: VideoAmbientRefreshReason) {
        guard ambientPresentation.usesBlurredLetterbox else {
            ambientBackdrop.suspend(clear: true)
            return
        }
        ambientBackdrop.refresh(
            reason: reason,
            engine: model.engine,
            generation: model.loadGeneration,
            isLoaded: model.snapshot.isLoaded,
            isPlaying: model.snapshot.isPlaying,
            isActive: isActive && scenePhase == .active,
            isFullScreen: windowChrome.isFullScreen
        )
    }

    private func suspendVideoThumbnailsForPlayback() {
        Task {
            await VideoThumbnailScheduler.shared.suspend(reason: .playback)
        }
    }

    private func resumeVideoThumbnailsForPlayback() {
        Task {
            await VideoThumbnailScheduler.shared.resume(reason: .playback)
        }
    }

    private func updateTimelinePreview(at time: TimeInterval?) {
        guard let time,
              model.currentURL != nil,
              model.snapshot.duration > 0 else {
            clearTimelinePreview()
            return
        }

        let clampedTime = clampedTimelinePreviewTime(time)
        timelinePreviewRequestedTime = clampedTime
        timelinePreview = VideoTimelinePreview(time: clampedTime, pngData: nil)
    }

    private func clearTimelinePreview(clearCache _: Bool = false) {
        timelinePreviewRequestedTime = nil
        timelinePreview = nil
    }

    private func clampedTimelinePreviewTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        let duration = max(model.snapshot.duration, 0)
        guard duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }

    private var videoCanvas: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                MpvRenderView(
                    engine: model.engine as! MpvPlayerEngine,
                    onRenderReady: handleRenderReady
                )
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        handleVideoPointerMovement(phase)
                    }
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                toggleFullScreenFromPointer()
                            }
                            .exclusively(
                                before: TapGesture(count: 1)
                                    .onEnded {
                                        togglePlaybackFromPointer()
                                    }
                            )
                    )

                VideoAmbientBackdrop(
                    image: ambientBackdrop.image,
                    presentation: ambientPresentation
                )
                .zIndex(0.25)

                videoWindowDragStrip
                    .zIndex(0.5)

                if model.currentURL != nil {
                    VideoSurfaceScrollBridge(
                        isEnabled: shouldHandleVideoSurfaceVolumeScroll,
                        excludedRects: videoSurfaceVolumeScrollExcludedRects(in: geometry.size),
                        onScroll: { delta in
                            adjustVolume(by: delta)
                            revealPlaybackChrome(scheduleHide: true)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(1.5)
                }

                if shouldShowVideoDismissLayer {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissVideoOverlaysFromCanvas()
                        }
                        .zIndex(2.5)
                }

                if model.currentURL == nil {
                    ContentUnavailableView {
                        Label("No Video Open", systemImage: "play.rectangle")
                    } description: {
                        Text("Open a local video file to start watching.")
                    } actions: {
                        Button("Open Video") {
                            presentFileImporter(.video)
                        }
                    }
                    .foregroundStyle(.white)
                    .zIndex(2)
                } else if areSubtitlesVisible {
                    SubtitleOverlayView(
                        cues: subtitles.currentCues,
                        contextCues: subtitles.document?.cues ?? subtitles.currentCues,
                        scanLength: userConfig.scanLength,
                        hoverLookupDelayMs: userConfig.desktopLookupHoverDelayMs,
                        maskEnabled: userConfig.videoSubtitleMaskEnabled,
                        maskMode: userConfig.videoSubtitleMaskMode,
                        maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius,
                        maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity,
                        fontFamily: userConfig.videoSubtitleFontFamily,
                        fontSize: userConfig.videoSubtitleFontSize,
                        fontWeight: userConfig.videoSubtitleFontWeight,
                        shadowRadius: userConfig.videoSubtitleShadowRadius,
                        backgroundOpacity: userConfig.videoSubtitleBackgroundOpacity,
                        backgroundDisabled: userConfig.videoSubtitleBackgroundDisabled,
                        verticalPosition: userConfig.videoSubtitleVerticalPosition,
                        subtitleColor: userConfig.videoSubtitleColor,
                        lookupHighlightColor: userConfig.videoSubtitleLookupHighlightColor,
                        lookupHighlightTextColor: userConfig.videoSubtitleLookupHighlightTextColor,
                        isLookupPopupVisible: hasVisibleVideoPopup,
                        isPlaybackPaused: !model.snapshot.isPlaying
                    ) { cue, selection in
                        lookup.present(
                            selection: selection,
                            cue: cue,
                            player: model,
                            userConfig: userConfig,
                            replacingExisting: true
                        )
                    }
                    .zIndex(2)
                }

                if model.currentURL != nil {
                    VideoControlsView(
                        snapshot: model.snapshot,
                        timelinePreview: timelinePreview,
                        playlist: model.playlist,
                        profiles: profileRepository.index.profiles,
                        selectedProfileID: resolvedVideoProfile.id,
                        canMineCurrentSubtitle: canMineCurrentSubtitle,
                        isFullScreen: windowChrome.isFullScreen,
                        onTogglePlayback: {
                            model.togglePlayback()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSeek: { time in
                            model.seek(to: time)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onPrevious: {
                            model.playPrevious()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onNext: {
                            model.playNext()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSetVolume: { volume in
                            model.setVolume(volume)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleMuted: {
                            model.toggleMuted()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSetSpeed: { speed in
                            dismissVideoPopupsIfNeeded()
                            model.setSpeed(speed)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSelectProfile: { profileID in
                            selectVideoProfile(profileID)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleMiningHistory: {
                            revealPlaybackChrome(scheduleHide: false)
                            dismissVideoPopupsThen {
                                toggleMiningHistory()
                            }
                        },
                        onOpenVideo: {
                            revealPlaybackChrome(scheduleHide: true)
                            dismissVideoPopupsThen {
                                presentFileImporter(.video)
                            }
                        },
                        onMineCurrentSubtitle: {
                            mineCurrentSubtitle()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleInspector: {
                            revealPlaybackChrome(scheduleHide: false)
                            dismissVideoPopupsThen {
                                toggleInspector()
                            }
                        },
                        onToggleFullScreen: {
                            revealPlaybackChrome(scheduleHide: true)
                            dismissVideoPopupsThen {
                                toggleFullScreen()
                            }
                        },
                        onTimelinePreviewTimeChanged: { time in
                            updateTimelinePreview(at: time)
                            if time != nil {
                                revealPlaybackChrome(scheduleHide: false)
                            } else {
                                schedulePlaybackChromeAutoHide()
                            }
                        },
                        onDragChanged: { translation in
                            revealPlaybackChrome(scheduleHide: false)
                            var dragTransaction = Transaction(animation: nil)
                            dragTransaction.disablesAnimations = true
                            withTransaction(dragTransaction) {
                                playbackChromeDragOffset = translation
                            }
                        },
                        onDragEnded: { translation in
                            let finalOffset = clampedPlaybackChromeOffset(
                                CGSize(
                                    width: playbackChromeStoredOffset.width + translation.width,
                                    height: playbackChromeStoredOffset.height + translation.height
                                ),
                                in: geometry.size
                            )
                            withAnimation(.smooth(duration: 0.18)) {
                                playbackChromeStoredOffset = finalOffset
                                playbackChromeDragOffset = .zero
                            }
                            revealPlaybackChrome(scheduleHide: true)
                        }
                    )
                    .position(playbackChromeBasePosition(in: geometry.size))
                    .offset(playbackChromeCurrentOffset(in: geometry.size))
                    .onHover { hovering in
                        playbackChromeHoverChanged(hovering)
                    }
                    .opacity(shouldShowPlaybackChrome ? 1 : 0)
                    .allowsHitTesting(shouldShowPlaybackChrome)
                    .accessibilityHidden(!shouldShowPlaybackChrome)
                    .zIndex(3)
                }

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeInOut(duration: 0.16), value: shouldShowPlaybackChrome)
            .onPreferenceChange(VideoInspectorOverlayFramePreferenceKey.self) { frame in
                inspectorOverlayFrame = frame ?? .zero
            }
            .onChange(of: geometry.size) { _, size in
                playbackChromeStoredOffset = clampedPlaybackChromeOffset(playbackChromeStoredOffset, in: size)
                playbackChromeDragOffset = .zero
            }
        }
    }

    private var videoWindowDragStrip: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
            Spacer(minLength: 0)
        }
    }

    private var resolvedVideoProfile: HoshiProfile {
        profileRepository.resolve(.video(profileID: profileRepository.videoProfileID))
    }

    private func selectVideoProfile(_ profileID: String) {
        lookup.closeAll(player: model) {
            do {
                try profileRepository.setVideoProfile(profileID)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var inspectorOverlay: some View {
        VideoInspectorView(
            selectedTab: $selectedInspectorTab,
            state: model.inspectorState,
            playlist: model.playlist,
            currentURL: model.currentURL,
            primarySubtitleName: subtitles.document?.sourceURL.lastPathComponent,
            onSelectEpisode: { url in
                openPlaylistEpisode(url)
            },
            onSetSpeed: { speed in
                dismissVideoPopupsIfNeeded()
                model.setSpeed(speed)
            },
            onSetSubtitleDelay: { delay in
                dismissVideoPopupsIfNeeded()
                model.setSubtitleDelay(delay)
            },
            onSetAudioDelay: { delay in
                dismissVideoPopupsIfNeeded()
                model.setAudioDelay(delay)
            },
            onSetLoopMode: { mode in
                dismissVideoPopupsIfNeeded()
                model.setLoopMode(mode)
            },
            onSetABLoopStart: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopStart()
            },
            onSetABLoopEnd: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopEnd()
            },
            onClearABLoop: {
                dismissVideoPopupsIfNeeded()
                model.clearABLoop()
            },
            onSetAspectRatio: { aspectRatio in
                dismissVideoPopupsIfNeeded()
                model.setAspectRatio(aspectRatio)
            },
            onRotateClockwise: {
                dismissVideoPopupsIfNeeded()
                model.rotateClockwise()
            },
            onSelectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    if let id {
                        selectSubtitleTrack(id, rememberSelection: true)
                    } else {
                        applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                    }
                    return
                }
                model.selectTrack(type: type, id: id)
            },
            onOpenSubtitle: {
                dismissVideoPopupsIfNeeded()
                presentFileImporter(.primarySubtitle)
            },
            onClearPrimarySubtitle: {
                dismissVideoPopupsIfNeeded()
                applySubtitlesOff(clearPrimary: true, rememberSelection: true)
            },
            onOpenTranscript: {
                toggleTranscriptSidebar()
            },
            onClose: {
                dismissVideoPopupsIfNeeded()
                isInspectorVisible = false
            }
        )
        .equatable()
        .padding(.vertical, Self.inspectorOverlayVerticalInset)
        .padding(.trailing, Self.inspectorOverlayTrailingInset)
    }

    private var videoPlaybackCommandContext: VideoPlaybackCommandContext {
        VideoPlaybackCommandContext(
            snapshot: model.snapshot,
            playlist: model.playlist,
            currentURL: model.currentURL,
            areSubtitlesVisible: areSubtitlesVisible,
            primarySubtitleName: subtitles.document?.sourceURL.lastPathComponent,
            canMineCurrentSubtitle: canMineCurrentSubtitle,
            openVideo: {
                dismissVideoPopupsThen {
                    presentFileImporter(.video)
                }
            },
            playPause: {
                guard model.currentURL != nil else { return }
                model.togglePlayback()
            },
            previousEpisode: {
                guard model.playlist.previousURL != nil else { return }
                model.playPrevious()
            },
            nextEpisode: {
                guard model.playlist.nextURL != nil else { return }
                model.playNext()
            },
            setSpeed: { speed in
                dismissVideoPopupsIfNeeded()
                model.setSpeed(speed)
            },
            setAspectRatio: { aspectRatio in
                dismissVideoPopupsIfNeeded()
                model.setAspectRatio(aspectRatio)
            },
            rotateClockwise: {
                dismissVideoPopupsIfNeeded()
                model.rotateClockwise()
            },
            toggleFileLoop: {
                dismissVideoPopupsIfNeeded()
                model.setLoopMode(model.snapshot.loopMode == .file ? .none : .file)
            },
            setABLoopStart: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopStart()
            },
            setABLoopEnd: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopEnd()
            },
            clearABLoop: {
                dismissVideoPopupsIfNeeded()
                model.clearABLoop()
            },
            selectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    if let id {
                        selectSubtitleTrack(id, rememberSelection: true)
                    } else {
                        applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                    }
                    return
                }
                model.selectTrack(type: type, id: id)
            },
            toggleMuted: {
                model.toggleMuted()
            },
            adjustVolume: { delta in
                adjustVolume(by: delta)
            },
            adjustAudioDelay: { delta in
                model.adjustAudioDelay(by: delta)
            },
            resetAudioDelay: {
                model.setAudioDelay(0)
            },
            openSubtitles: {
                dismissVideoPopupsIfNeeded()
                presentFileImporter(.primarySubtitle)
            },
            clearPrimarySubtitle: {
                dismissVideoPopupsIfNeeded()
                applySubtitlesOff(clearPrimary: true, rememberSelection: true)
            },
            toggleSubtitlesVisible: {
                toggleSubtitlesVisible()
            },
            previousSubtitleCue: {
                _ = seekRelativeSubtitleCue(offset: -1)
            },
            nextSubtitleCue: {
                _ = seekRelativeSubtitleCue(offset: 1)
            },
            cycleSubtitleTrack: {
                _ = cycleSubtitleTrack()
            },
            adjustSubtitleDelay: { delta in
                model.adjustSubtitleDelay(by: delta)
            },
            resetSubtitleDelay: {
                model.setSubtitleDelay(0)
            },
            openTranscript: {
                toggleTranscriptSidebar()
            },
            mineCurrentSubtitle: {
                mineCurrentSubtitle()
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || subtitles.errorMessage != nil },
            set: { visible in
                if !visible {
                    model.errorMessage = nil
                    subtitles.errorMessage = nil
                }
            }
        )
    }

    private func handleFileImport(
        _ result: Result<[URL], any Error>,
        kind: VideoFileImportKind
    ) {
        switch kind {
        case .video:
            handleVideoImport(result)
        case .primarySubtitle:
            handleSubtitleImport(result)
        }
    }

    private func handleVideoImport(
        _ result: Result<[URL], any Error>
    ) {
        if let url = try? result.get().first {
            openVideo(url)
        }
    }

    private func openVideo(_ url: URL, subtitleURL: URL? = nil) {
        lookup.closeAll(player: model)
        subtitles.clear()
        shouldSkipNextAutomaticSubtitleRestore = subtitleURL != nil
        model.open(url)
        guard model.errorMessage == nil else {
            shouldSkipNextAutomaticSubtitleRestore = false
            return
        }
        if let subtitleURL {
            loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
        }
    }

    private func openPlaylistEpisode(_ url: URL) {
        lookup.closeAll(player: model)
        subtitles.clear()
        model.selectPlaylistItem(url)
    }

    private func handleExternalOpenRequest(_ request: VideoWindowOpenRequest?) {
        guard let request,
              let readyRequest = openGate.receive(request) else { return }
        openExternalRequest(readyRequest)
    }

    private func handleRenderReady() {
        guard let request = openGate.renderDidBecomeReady() else { return }
        openExternalRequest(request)
    }

    private func openExternalRequest(_ request: VideoWindowOpenRequest) {
        openVideo(request.url, subtitleURL: request.subtitleURL)
        onConsumeOpenRequest(request.id)
    }

    private func autoloadSubtitleIfAvailable(for mediaURL: URL) {
        guard let subtitleURL = VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) else {
            return
        }
        loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: false)
    }

    private func handleSubtitleImport(
        _ result: Result<[URL], any Error>
    ) {
        if let url = try? result.get().first {
            lookup.closeAll(player: model)
            loadPrimarySubtitle(from: url, loadIntoMpv: true)
        }
    }

    @discardableResult
    private func loadPrimarySubtitle(
        from url: URL,
        loadIntoMpv: Bool,
        rememberSelection: Bool = true
    ) -> Task<Void, Never> {
        cancelSubtitleTrackExtraction()
        isLoadingPrimarySubtitle = true
        if loadIntoMpv {
            model.loadExternalSubtitle(url)
        }
        let loadTask = subtitles.load(url)
        return Task { @MainActor in
            await loadTask.value
            isLoadingPrimarySubtitle = false
            if subtitles.document?.sourceURL.standardizedFileURL
                == url.standardizedFileURL {
                areSubtitlesVisible = true
                if rememberSelection {
                    model.rememberSubtitleSelection(
                        .external(path: url.standardizedFileURL.path)
                    )
                }
            }
            subtitles.update(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
        }
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let accumulator = DroppedFileURLAccumulator()

        for provider in fileProviders {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                defer { group.leave() }
                guard let url = Self.fileURL(from: item) else { return }
                accumulator.append(url.standardizedFileURL)
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                handleDroppedFileURLs(accumulator.urls())
            }
        }
        return true
    }

    private func handleDroppedFileURLs(_ urls: [URL]) {
        let mediaURL = urls.first(where: isMediaFile)
        let subtitleURL = urls.first(where: isSubtitleFile)

        if let mediaURL {
            loadDroppedMedia(mediaURL, subtitleURL: subtitleURL)
        } else if let subtitleURL {
            loadDroppedSubtitle(subtitleURL)
        }
    }

    private func loadDroppedMedia(_ mediaURL: URL, subtitleURL: URL?) {
        openVideo(mediaURL, subtitleURL: subtitleURL)
    }

    private func loadDroppedSubtitle(_ subtitleURL: URL) {
        guard model.currentURL != nil else { return }
        lookup.closeAll(player: model)
        loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
    }

    private func isMediaFile(_ url: URL) -> Bool {
        VideoMediaTypes.isMediaFile(url)
    }

    private func isSubtitleFile(_ url: URL) -> Bool {
        Self.subtitleFileExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated private static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private func popupView(_ popup: PopupItem, screenSize: CGSize) -> some View {
        let popupID = popup.id
        return PopupView(
            userConfig: userConfig,
            isVisible: Binding(
                get: {
                    lookup.presentation.popups
                        .first(where: { $0.id == popupID })?
                        .showPopup ?? false
                },
                set: { visible in
                    lookup.presentation.setVisibility(id: popupID, visible: visible)
                }
            ),
            selectionData: popup.currentSelection,
            lookupResults: popup.lookupResults,
            dictionaryStyles: popup.dictionaryStyles,
            screenSize: screenSize,
            isVertical: false,
            isFullWidth: false,
            bottomInset: 56,
            coverURL: nil,
            documentTitle: model.currentURL?.lastPathComponent,
            profileID: resolvedVideoProfile.id,
            clearSelection: popup.clearSelection,
            onTextSelected: { selection in
                lookup.presentation.closeChildren(of: popupID)
                return lookup.present(
                    selection: selection,
                    player: model,
                    userConfig: userConfig
                )
            },
            onTapOutside: {
                lookup.presentation.handleTapInsidePopup(id: popupID)
            },
            onSwipeDismiss: {
                lookup.dismiss(id: popupID, player: model)
            },
            miningContextProvider: { _, selectedContext in
                guard let cue = lookup.activeCue,
                      let videoURL = model.currentURL else {
                    return MiningContext(
                        sentence: popup.currentSelection?.sentence ?? "",
                        documentTitle: model.currentURL?.lastPathComponent,
                        coverURL: nil
                    )
                }
                let needsScreenshot = AnkiManager.shared.needsVideoScreenshot
                let needsAudioClip = AnkiManager.shared.needsVideoAudioClip
                let ankiMediaDirectory = (needsScreenshot || needsAudioClip)
                    ? await AnkiManager.shared.getMediaDirPath()
                    : nil
                return await VideoMiningCoordinator.context(
                    cue: cue,
                    selectedContext: selectedContext,
                    document: subtitles.document,
                    videoURL: videoURL,
                    engine: model.engine,
                    captureScreenshot: needsScreenshot,
                    captureAudioClip: needsAudioClip,
                    ankiMediaDirectory: ankiMediaDirectory
                )
            }
        )
        .id(popupID)
        .zIndex(Double(100 + (
            lookup.presentation.popups.firstIndex(where: { $0.id == popupID }) ?? 0
        )))
    }

    private func registerKeyboardShortcuts() {
        guard shortcutRegistrationIDs.isEmpty else { return }

        shortcutRegistrationIDs = [
            shortcutManager.register(
                scope: .popup,
                handlers: [
                    PopupShortcutActions.dismiss.id: {
                        guard let popup = lookup.presentation.popups.last else {
                            return false
                        }
                        lookup.dismiss(id: popup.id, player: model)
                        return true
                    }
                ]
            ),
            shortcutManager.register(
                scope: .video,
                handlers: [
                    VideoShortcutActions.playPause.id: {
                        guard model.currentURL != nil else { return false }
                        model.togglePlayback()
                        return true
                    },
                    VideoShortcutActions.seekBackward.id: {
                        guard model.currentURL != nil else { return false }
                        model.skip(by: -userConfig.videoSeekInterval)
                        return true
                    },
                    VideoShortcutActions.seekForward.id: {
                        guard model.currentURL != nil else { return false }
                        model.skip(by: userConfig.videoSeekInterval)
                        return true
                    },
                    VideoShortcutActions.previousEpisode.id: {
                        guard model.playlist.previousURL != nil else { return false }
                        model.playPrevious()
                        return true
                    },
                    VideoShortcutActions.nextEpisode.id: {
                        guard model.playlist.nextURL != nil else { return false }
                        model.playNext()
                        return true
                    },
                    VideoShortcutActions.decreaseSpeed.id: {
                        model.adjustSpeed(by: -VideoPlaybackSpeed.customStep)
                        return true
                    },
                    VideoShortcutActions.increaseSpeed.id: {
                        model.adjustSpeed(by: VideoPlaybackSpeed.customStep)
                        return true
                    },
                    VideoShortcutActions.resetSpeed.id: {
                        model.setSpeed(1)
                        return true
                    },
                    VideoShortcutActions.toggleMute.id: {
                        model.toggleMuted()
                        return true
                    },
                    VideoShortcutActions.volumeDown.id: {
                        adjustVolume(by: -5)
                        return true
                    },
                    VideoShortcutActions.volumeUp.id: {
                        adjustVolume(by: 5)
                        return true
                    },
                    VideoShortcutActions.mineCurrentSubtitle.id: {
                        mineCurrentSubtitle()
                        return true
                    },
                    VideoShortcutActions.previousSubtitleCue.id: {
                        seekRelativeSubtitleCue(offset: -1)
                    },
                    VideoShortcutActions.nextSubtitleCue.id: {
                        seekRelativeSubtitleCue(offset: 1)
                    },
                    VideoShortcutActions.toggleSubtitlesVisible.id: {
                        toggleSubtitlesVisible()
                        return true
                    },
                    VideoShortcutActions.cycleSubtitleTrack.id: {
                        cycleSubtitleTrack()
                    },
                    VideoShortcutActions.subtitleEarlier.id: {
                        model.adjustSubtitleDelay(by: -0.05)
                        return true
                    },
                    VideoShortcutActions.subtitleLater.id: {
                        model.adjustSubtitleDelay(by: 0.05)
                        return true
                    },
                    VideoShortcutActions.resetSubtitleTiming.id: {
                        model.setSubtitleDelay(0)
                        return true
                    },
                    VideoShortcutActions.audioEarlier.id: {
                        model.adjustAudioDelay(by: -0.5)
                        return true
                    },
                    VideoShortcutActions.audioLater.id: {
                        model.adjustAudioDelay(by: 0.5)
                        return true
                    },
                    VideoShortcutActions.toggleFileLoop.id: {
                        model.setLoopMode(
                            model.snapshot.loopMode == .file ? .none : .file
                        )
                        return true
                    },
                    VideoShortcutActions.setABLoopStart.id: {
                        model.setABLoopStart()
                        return true
                    },
                    VideoShortcutActions.setABLoopEnd.id: {
                        model.setABLoopEnd()
                        return true
                    },
                    VideoShortcutActions.toggleTranscript.id: {
                        toggleTranscriptSidebar()
                        return true
                    },
                    VideoShortcutActions.rotateClockwise.id: {
                        model.rotateClockwise()
                        return true
                    },
                    VideoShortcutActions.toggleFullScreen.id: {
                        guard windowChrome.hasWindow else { return false }
                        if windowChrome.isFullScreen {
                            exitFullScreen()
                            return true
                        }
                        dismissVideoPopupsThen {
                            toggleFullScreen()
                        }
                        return true
                    },
                    VideoShortcutActions.exitFocusMode.id: {
                        guard windowChrome.isFullScreen else {
                            return false
                        }
                        exitFullScreen()
                        return true
                    }
                ]
            ),
            shortcutManager.register(
                scope: .global,
                handlers: [
                    GlobalShortcutActions.open.id: {
                        dismissVideoPopupsThen {
                            presentFileImporter(.video)
                        }
                        return true
                    }
                ]
            )
        ]
    }

    private func unregisterKeyboardShortcuts() {
        shortcutRegistrationIDs.forEach(shortcutManager.unregister)
        shortcutRegistrationIDs.removeAll()
    }

    private func synchronizePlaybackPreferences() {
        model.autoPlayNext = userConfig.videoAutoPlayNext
        model.rememberPlaybackPosition = userConfig.videoRememberPlaybackPosition
        model.setHardwareDecodingEnabled(userConfig.videoHardwareDecodingEnabled)
        model.setDeinterlacingEnabled(userConfig.videoDeinterlacingEnabled)
        model.setHDREnhancementEnabled(userConfig.videoHDREnhancementEnabled)
        synchronizeVideoEqualizerPreferences()
    }

    private func synchronizeVideoEqualizerPreferences() {
        model.setVideoEqualizer(.brightness, value: userConfig.videoBrightness)
        model.setVideoEqualizer(.contrast, value: userConfig.videoContrast)
        model.setVideoEqualizer(.saturation, value: userConfig.videoSaturation)
        model.setVideoEqualizer(.gamma, value: userConfig.videoGamma)
        model.setVideoEqualizer(.hue, value: userConfig.videoHue)
    }

    private var fileImporterPresentation: Binding<Bool> {
        Binding(
            get: { pendingFileImportKind != nil },
            set: { isPresented in
                if !isPresented {
                    pendingFileImportKind = nil
                }
            }
        )
    }

    private func presentFileImporter(_ kind: VideoFileImportKind) {
        activeFileImportKind = kind
        pendingFileImportKind = kind
    }

    private func toggleFullScreen() {
        if windowChrome.isFullScreen {
            exitFullScreen()
            return
        }
        windowChrome.toggleFullScreen()
    }

    private func exitFullScreen() {
        guard windowChrome.isFullScreen else { return }
        windowChrome.exitFullScreen()
    }

    private func toggleFullScreenFromPointer() {
        guard model.currentURL != nil,
              lookup.presentation.popups.isEmpty else {
            return
        }
        revealPlaybackChrome(scheduleHide: true)
        toggleFullScreen()
    }

    private func togglePlaybackFromPointer() {
        guard model.currentURL != nil,
              lookup.presentation.popups.isEmpty else {
            return
        }
        model.togglePlayback()
        revealPlaybackChrome(scheduleHide: true)
    }

    private var shouldShowPlaybackChrome: Bool {
        model.currentURL == nil
            || (
                isPointerInsidePlayerSurface
                    && (
                        isPlaybackChromeVisible
                            || hasActiveVideoPopup
                            || isInspectorVisible
                            || isMiningHistoryVisible
                    )
            )
    }

    private func playbackChromeBasePosition(in size: CGSize) -> CGPoint {
        let halfHeight = Self.playbackChromeSize.height / 2
        let y = max(
            Self.playbackChromeEdgeInset + halfHeight,
            size.height - Self.playbackChromeBottomInset - halfHeight
        )
        return CGPoint(x: size.width / 2, y: y)
    }

    private func playbackChromeCurrentOffset(in size: CGSize) -> CGSize {
        clampedPlaybackChromeOffset(
            CGSize(
                width: playbackChromeStoredOffset.width + playbackChromeDragOffset.width,
                height: playbackChromeStoredOffset.height + playbackChromeDragOffset.height
            ),
            in: size
        )
    }

    private func playbackChromeFrame(in size: CGSize) -> CGRect {
        let center = playbackChromeBasePosition(in: size)
        let offset = playbackChromeCurrentOffset(in: size)
        return CGRect(
            x: center.x + offset.width - Self.playbackChromeSize.width / 2,
            y: center.y + offset.height - Self.playbackChromeSize.height / 2,
            width: Self.playbackChromeSize.width,
            height: Self.playbackChromeSize.height
        )
    }

    private func videoSurfaceVolumeScrollExcludedRects(in size: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        if shouldShowPlaybackChrome {
            rects.append(playbackChromeFrame(in: size))
        }
        if isInspectorVisible {
            let inspectorFrame = inspectorOverlayFrame.isEmpty
                ? inspectorOverlayFallbackFrame(in: size)
                : inspectorOverlayFrame
            let visibleInspectorFrame = inspectorFrame.intersection(
                CGRect(origin: .zero, size: size)
            )
            if !visibleInspectorFrame.isNull,
               visibleInspectorFrame.width > 0,
               visibleInspectorFrame.height > 0 {
                rects.append(visibleInspectorFrame)
            }
        }
        return rects
    }

    private func inspectorOverlayFallbackFrame(in size: CGSize) -> CGRect {
        let width = min(
            size.width,
            VideoInspectorView.maximumWidth + Self.inspectorOverlayTrailingInset
        )
        return CGRect(
            x: max(0, size.width - width),
            y: 0,
            width: width,
            height: size.height
        )
    }

    private func clampedPlaybackChromeOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let base = playbackChromeBasePosition(in: size)
        let halfWidth = Self.playbackChromeSize.width / 2
        let halfHeight = Self.playbackChromeSize.height / 2
        let minX = min(Self.playbackChromeEdgeInset + halfWidth, size.width / 2)
        let maxX = max(size.width - Self.playbackChromeEdgeInset - halfWidth, size.width / 2)
        let minY = min(Self.playbackChromeEdgeInset + halfHeight, size.height / 2)
        let maxY = max(size.height - Self.playbackChromeEdgeInset - halfHeight, size.height / 2)
        let x = min(max(base.x + offset.width, minX), maxX)
        let y = min(max(base.y + offset.height, minY), maxY)
        return CGSize(width: x - base.x, height: y - base.y)
    }

    private func handleVideoPointerMovement(_ phase: HoverPhase) {
        switch phase {
        case .active(_):
            let pointerLocation = NSEvent.mouseLocation
            guard lastPlaybackChromePointerLocation != pointerLocation else {
                return
            }
            lastPlaybackChromePointerLocation = pointerLocation
            isPointerInsidePlayerSurface = true
            revealPlaybackChrome(scheduleHide: true)
        case .ended:
            schedulePlaybackChromeAutoHide()
        }
    }

    private func revealPlaybackChrome(scheduleHide shouldScheduleAutoHide: Bool) {
        guard model.currentURL != nil else {
            isPlaybackChromeVisible = true
            playbackChromeAutoHideTask?.cancel()
            return
        }
        if !isPlaybackChromeVisible {
            withAnimation(.smooth(duration: 0.18)) {
                isPlaybackChromeVisible = true
            }
        }
        if shouldScheduleAutoHide {
            schedulePlaybackChromeAutoHide()
        } else {
            playbackChromeAutoHideTask?.cancel()
        }
    }

    private func hidePlaybackChrome() {
        playbackChromeAutoHideTask?.cancel()
        guard model.currentURL != nil,
              !hasActiveVideoPopup,
              timelinePreviewRequestedTime == nil,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            return
        }
        lastPlaybackChromePointerLocation = NSEvent.mouseLocation
        withAnimation(.smooth(duration: 0.18)) {
            isPlaybackChromeVisible = false
        }
    }

    private func playerSurfaceHoverChanged(_ hovering: Bool) {
        guard model.currentURL != nil else { return }
        isPointerInsidePlayerSurface = hovering
        if hovering {
            revealPlaybackChrome(scheduleHide: true)
        } else {
            hidePlaybackChromeForPointerExit()
        }
    }

    private func hidePlaybackChromeForPointerExit() {
        guard model.currentURL != nil else { return }
        guard timelinePreviewRequestedTime == nil else { return }
        playbackChromeAutoHideTask?.cancel()
        isPointerInsidePlayerSurface = false
        withAnimation(.smooth(duration: 0.18)) {
            isPlaybackChromeVisible = false
        }
    }

    private func playbackChromeHoverChanged(_ hovering: Bool) {
        guard model.currentURL != nil else { return }
        if hovering {
            revealPlaybackChrome(scheduleHide: true)
        } else {
            schedulePlaybackChromeAutoHide()
        }
    }

    private func schedulePlaybackChromeAutoHide() {
        playbackChromeAutoHideTask?.cancel()
        guard model.currentURL != nil,
              isPlaybackChromeVisible,
              !hasActiveVideoPopup,
              timelinePreviewRequestedTime == nil,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            return
        }
        playbackChromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            hidePlaybackChrome()
        }
    }

    private func adjustVolume(by delta: Double) {
        model.setVolume(model.snapshot.volume + delta)
    }

    private var canMineCurrentSubtitle: Bool {
        userConfig.videoMiningHistoryLimit > 0
            && model.currentURL != nil
            && subtitles.document != nil
            && !subtitles.currentCues.isEmpty
    }

    private func mineCurrentSubtitle() {
        guard userConfig.videoMiningHistoryLimit > 0 else {
            showMiningHistoryNotice(.disabled)
            return
        }
        guard let videoURL = model.currentURL,
              let document = subtitles.document,
              !subtitles.currentCues.isEmpty else {
            showMiningHistoryNotice(.noSubtitle)
            return
        }

        let embeddedTrackID = document.format == .embedded
            ? model.snapshot.tracks.first {
                $0.type == .subtitle && $0.isSelected
            }?.id
            : nil
        guard miningHistory.record(
            cues: subtitles.currentCues,
            document: document,
            videoURL: videoURL,
            embeddedSubtitleTrackID: embeddedTrackID
        ) != nil else {
            showMiningHistoryNotice(.disabled)
            return
        }
        showMiningHistoryNotice(.saved)
    }

    private func navigateToHistoryItem(_ item: VideoMiningHistoryItem) {
        let resolution = VideoMiningHistoryNavigationResolver.resolve(
            item: item,
            currentVideoURL: model.currentURL,
            subtitleDelay: model.snapshot.subtitleDelay
        )
        switch resolution {
        case .missingVideo:
            model.errorMessage = String(
                localized: "The saved video file is no longer available. Open it again to continue."
            )
        case .missingSubtitle:
            model.errorMessage = String(
                localized: "The saved subtitle file is no longer available. Open it again to continue."
            )
        case .legacySourceUnavailable:
            model.errorMessage = String(
                localized: "Open the matching video before using this older Mining History item."
            )
        case .ready(let destination):
            restoreHistoryDestination(destination)
        }
    }

    private func restoreHistoryDestination(_ destination: VideoMiningHistoryDestination) {
        let wasPlaying = model.snapshot.isPlaying
        let isChangingVideo = model.currentURL?.standardizedFileURL
            != destination.videoURL.standardizedFileURL
        dismissVideoPopupsIfNeeded()

        Task { @MainActor in
            if isChangingVideo {
                subtitles.clear()
                shouldSkipNextAutomaticSubtitleRestore = true
                model.open(destination.videoURL)
                guard model.errorMessage == nil else {
                    shouldSkipNextAutomaticSubtitleRestore = false
                    return
                }
                await Task.yield()
            }

            if let trackID = destination.embeddedSubtitleTrackID {
                pendingHistoryEmbeddedSubtitleTrackID = trackID
                restorePendingHistorySubtitleTrackIfAvailable()
            }

            if let subtitleURL = destination.subtitleURL,
               subtitles.document?.sourceURL.standardizedFileURL != subtitleURL {
                await loadPrimarySubtitle(
                    from: subtitleURL,
                    loadIntoMpv: true
                ).value
            }

            model.seek(to: destination.seekTime)
            subtitles.update(
                time: destination.seekTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
            areSubtitlesVisible = true

            if wasPlaying {
                model.engine.play()
            } else {
                model.engine.pause()
            }
        }
    }

    private func copyMiningHistorySubtitle(_ item: VideoMiningHistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.subtitleText, forType: .string)
        showMiningHistoryNotice(.copied)
    }

    private func restorePendingHistorySubtitleTrackIfAvailable() {
        guard let trackID = pendingHistoryEmbeddedSubtitleTrackID,
              model.snapshot.tracks.contains(where: {
                  $0.type == .subtitle && $0.id == trackID
              }) else {
            return
        }
        pendingHistoryEmbeddedSubtitleTrackID = nil
        selectSubtitleTrack(trackID, rememberSelection: true)
    }

    private func showMiningHistoryNotice(_ notice: VideoMiningHistoryNotice) {
        miningHistoryNoticeTask?.cancel()
        withAnimation(.smooth(duration: 0.18)) {
            miningHistoryNotice = notice
        }
        miningHistoryNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.18)) {
                miningHistoryNotice = nil
            }
        }
    }

    private func videoMiningHistoryNotice(
        _ notice: VideoMiningHistoryNotice
    ) -> some View {
        Label(notice.title, systemImage: notice.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
    }

    private func seekRelativeSubtitleCue(offset: Int) -> Bool {
        guard let targetIndex = subtitles.transcript.relativeRowIndex(
            atPlaybackTime: model.snapshot.currentTime,
            subtitleDelay: model.snapshot.subtitleDelay,
            offset: offset
        ) else {
            return false
        }
        model.seek(
            to: subtitles.transcript.rows[targetIndex].startTime
                + model.snapshot.subtitleDelay
        )
        return true
    }

    private func restoreRememberedSubtitleSelectionOrAutoload() {
        guard model.pendingSubtitleSelection != nil,
              let mediaURL = model.currentURL else {
            return
        }
        restoreRememberedSubtitleSelectionOrAutoload(for: mediaURL)
    }

    private func handleVideoLoadGeneration() {
        if shouldSkipNextAutomaticSubtitleRestore {
            shouldSkipNextAutomaticSubtitleRestore = false
            _ = model.consumePendingSubtitleSelection()
            return
        }
        lookup.closeAll(player: model)
        cancelSubtitleTrackExtraction()
        subtitles.clear()
        guard let mediaURL = model.currentURL else { return }
        restoreRememberedSubtitleSelectionOrAutoload(for: mediaURL)
    }

    private func restoreRememberedSubtitleSelectionOrAutoload(
        for mediaURL: URL
    ) {
        guard let selection = model.pendingSubtitleSelection else {
            autoloadSubtitleIfAvailable(for: mediaURL)
            return
        }
        let resolution = VideoSubtitleRestoreResolver.resolve(
            selection: selection,
            tracks: model.snapshot.tracks,
            isLoaded: model.snapshot.isLoaded
        )
        switch resolution {
        case .off:
            _ = model.consumePendingSubtitleSelection()
            applySubtitlesOff(clearPrimary: true, rememberSelection: false)
        case .external(let subtitleURL):
            _ = model.consumePendingSubtitleSelection()
            loadPrimarySubtitle(
                from: subtitleURL,
                loadIntoMpv: true,
                rememberSelection: false
            )
        case .embeddedTrack(let trackID):
            _ = model.consumePendingSubtitleSelection()
            selectSubtitleTrack(trackID, rememberSelection: false)
        case .waitingForTracks:
            break
        case .unavailable:
            _ = model.consumePendingSubtitleSelection()
            autoloadSubtitleIfAvailable(for: mediaURL)
        }
    }

    private func selectSubtitleTrack(
        _ trackID: Int,
        rememberSelection: Bool
    ) {
        guard let track = model.snapshot.tracks.first(where: {
            $0.type == .subtitle && $0.id == trackID
        }) else {
            return
        }
        cancelSubtitleTrackExtraction()
        subtitles.clearPrimary()
        lastSelectedSubtitleTrackID = trackID
        areSubtitlesVisible = true
        model.selectTrack(type: .subtitle, id: trackID)
        guard rememberSelection else { return }
        if let filename = track.externalFilename, !filename.isEmpty {
            model.rememberSubtitleSelection(
                .external(path: URL(fileURLWithPath: filename).standardizedFileURL.path)
            )
        } else {
            model.rememberSubtitleSelection(
                .embedded(VideoSubtitleTrackIdentity(track: track))
            )
        }
    }

    private func applySubtitlesOff(
        clearPrimary: Bool,
        rememberSelection: Bool
    ) {
        cancelSubtitleTrackExtraction()
        if clearPrimary {
            subtitles.clearPrimary()
            lastSelectedSubtitleTrackID = nil
        }
        model.selectTrack(type: .subtitle, id: nil)
        areSubtitlesVisible = false
        if rememberSelection {
            model.rememberSubtitleSelection(.off)
        }
    }

    private func toggleSubtitlesVisible() {
        if areSubtitlesVisible {
            lastSelectedSubtitleTrackID = model.snapshot.tracks
                .first { $0.type == .subtitle && $0.isSelected }?
                .id
            applySubtitlesOff(clearPrimary: false, rememberSelection: true)
        } else {
            if let document = subtitles.document,
               document.format != .embedded {
                areSubtitlesVisible = true
                model.rememberSubtitleSelection(
                    .external(path: document.sourceURL.standardizedFileURL.path)
                )
                return
            }
            let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            if let trackID {
                selectSubtitleTrack(trackID, rememberSelection: true)
            }
        }
    }

    private func cycleSubtitleTrack() -> Bool {
        let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
        guard !subtitleTracks.isEmpty else { return false }
        guard areSubtitlesVisible else {
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            if let trackID {
                selectSubtitleTrack(trackID, rememberSelection: true)
            }
            return true
        }
        if let selectedIndex = subtitleTracks.firstIndex(where: \.isSelected) {
            let nextIndex = subtitleTracks.index(after: selectedIndex)
            if nextIndex < subtitleTracks.endIndex {
                let id = subtitleTracks[nextIndex].id
                selectSubtitleTrack(id, rememberSelection: true)
            } else {
                lastSelectedSubtitleTrackID = subtitleTracks[selectedIndex].id
                applySubtitlesOff(clearPrimary: false, rememberSelection: true)
            }
        } else {
            let id = subtitleTracks[0].id
            selectSubtitleTrack(id, rememberSelection: true)
        }
        return true
    }

    private func toggleMiningHistory() {
        videoScreenLog.info(
            "Toggling video mining history visible=\(self.isMiningHistoryVisible)"
        )
        if isMiningHistoryVisible, selectedStudySidebarTab == .history {
            isMiningHistoryVisible = false
        } else {
            selectedStudySidebarTab = .history
            isMiningHistoryVisible = true
        }
    }

    private func toggleTranscriptSidebar() {
        dismissVideoPopupsThen {
            if isMiningHistoryVisible, selectedStudySidebarTab == .transcript {
                isMiningHistoryVisible = false
            } else {
                selectedStudySidebarTab = .transcript
                isMiningHistoryVisible = true
                isInspectorVisible = false
            }
        }
    }

    private var hasActiveVideoPopup: Bool {
        !lookup.presentation.popups.isEmpty
    }

    private var hasVisibleVideoPopup: Bool {
        lookup.presentation.popups.contains { $0.showPopup }
    }

    private var shouldShowVideoDismissLayer: Bool {
        hasActiveVideoPopup || isInspectorVisible
    }

    private var shouldHandleVideoSurfaceVolumeScroll: Bool {
        model.currentURL != nil
            && !hasActiveVideoPopup
    }

    private func dismissVideoPopupsIfNeeded() {
        guard hasActiveVideoPopup else { return }
        videoScreenLog.info("Dismissing active video lookup popups")
        lookup.closeAll(player: model)
    }

    private func dismissVideoPopupsThen(_ action: @escaping () -> Void) {
        guard hasActiveVideoPopup else {
            action()
            return
        }
        videoScreenLog.info("Deferring video action until lookup popup stack closes")
        lookup.closeAll(player: model) {
            action()
        }
    }

    private func dismissVideoOverlaysFromCanvas() {
        dismissVideoPopupsIfNeeded()
        if isInspectorVisible {
            videoScreenLog.info("Closing video inspector from canvas tap")
            isInspectorVisible = false
        }
    }

    private func toggleInspector(tab: VideoInspectorTab? = nil) {
        videoScreenLog.info(
            "Toggling video inspector visible=\(self.isInspectorVisible) requestedTab=\(tab?.rawValue ?? "none")"
        )
        if let tab {
            if isInspectorVisible, selectedInspectorTab == tab {
                isInspectorVisible = false
            } else {
                selectedInspectorTab = tab
                isInspectorVisible = true
            }
            return
        }

        isInspectorVisible.toggle()
    }

    private func installEmbeddedSubtitleHandler() {
        model.engine.onEmbeddedSubtitleCuesChanged = { cues in
            guard let sourceURL = model.currentURL else { return }
            subtitles.loadEmbedded(cues, sourceURL: sourceURL)
            subtitles.update(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
        }
    }

    private func synchronizeSelectedSubtitleTrack() {
        guard !isLoadingPrimarySubtitle else { return }
        guard let videoURL = model.currentURL else {
            cancelSubtitleTrackExtraction()
            return
        }
        guard let track = model.snapshot.tracks.first(where: {
            $0.type == .subtitle && $0.isSelected
        }) else {
            cancelSubtitleTrackExtraction()
            if subtitles.document?.format == .embedded {
                subtitles.clearPrimary()
            }
            return
        }
        if let format = subtitles.document?.format, format != .embedded {
            return
        }

        let key = [
            videoURL.standardizedFileURL.path,
            String(track.id),
            String(track.ffIndex ?? -1),
            track.externalFilename ?? ""
        ].joined(separator: "|")
        guard key != activeSubtitleTrackExtractionKey else { return }

        subtitleTrackExtractionTask?.cancel()
        activeSubtitleTrackExtractionKey = key
        subtitles.beginEmbeddedTrack(trackID: track.id, sourceURL: videoURL)

        subtitleTrackExtractionTask = Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return SubtitleTrackExtractionOutcome.success(
                        try VideoSubtitleTrackExtractor.extract(
                            videoURL: videoURL,
                            track: track
                        )
                    )
                } catch {
                    return SubtitleTrackExtractionOutcome.failure(
                        error.localizedDescription
                    )
                }
            }.value
            guard !Task.isCancelled,
                  activeSubtitleTrackExtractionKey == key else {
                return
            }
            switch outcome {
            case .success(let cues):
                subtitles.replaceEmbeddedTranscript(
                    cues,
                    sourceURL: videoURL,
                    trackID: track.id
                )
                subtitles.update(
                    time: model.snapshot.currentTime,
                    subtitleDelay: model.snapshot.subtitleDelay
                )
            case .failure(let message):
                subtitles.failEmbeddedTranscript(message, trackID: track.id)
            }
        }
    }

    private func cancelSubtitleTrackExtraction() {
        subtitleTrackExtractionTask?.cancel()
        subtitleTrackExtractionTask = nil
        activeSubtitleTrackExtractionKey = nil
    }
}

private enum VideoVolumeScrollDelta {
    private static let wheelStep = 5.0
    private static let preciseScale = 0.5
    private static let maximumPreciseStep = 5.0
    private static let minimumPreciseStep = 0.1

    static func adjustment(
        deltaX: Double,
        deltaY: Double,
        hasPreciseScrollingDeltas: Bool
    ) -> Double? {
        guard deltaY.isFinite,
              abs(deltaY) >= 0.01,
              abs(deltaY) >= abs(deltaX) else {
            return nil
        }

        guard hasPreciseScrollingDeltas else {
            return deltaY > 0 ? Self.wheelStep : -Self.wheelStep
        }

        let preciseDelta = deltaY * Self.preciseScale
        guard abs(preciseDelta) >= Self.minimumPreciseStep else { return nil }
        return min(max(preciseDelta, -Self.maximumPreciseStep), Self.maximumPreciseStep)
    }
}

private struct VideoSurfaceScrollBridge: NSViewRepresentable {
    let isEnabled: Bool
    let excludedRects: [CGRect]
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> VideoSurfaceScrollMonitorView {
        let view = VideoSurfaceScrollMonitorView()
        view.isEnabled = isEnabled
        view.excludedRects = excludedRects
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: VideoSurfaceScrollMonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.excludedRects = excludedRects
        view.onScroll = onScroll
    }
}

private final class VideoSurfaceScrollMonitorView: NSView {
    var isEnabled = false
    var excludedRects: [CGRect] = []
    var onScroll: ((Double) -> Void)?

    nonisolated(unsafe) private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resetScrollMonitor()
    }

    deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    private func resetScrollMonitor() {
        removeScrollMonitor()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard let delta = self.scrollDelta(for: event) else { return event }
            self.onScroll?(delta)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func scrollDelta(for event: NSEvent) -> Double? {
        guard isEnabled,
              let window,
              event.window === window else {
            return nil
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return nil }
        if excludedRects.contains(where: { $0.contains(localPoint) }) {
            return nil
        }
        return VideoVolumeScrollDelta.adjustment(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
    }
}

private struct VideoInspectorOverlayFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private enum SubtitleTrackExtractionOutcome: Sendable {
    case success([VideoEmbeddedSubtitleCue])
    case failure(String)
}

private enum VideoFileImportKind {
    case video
    case primarySubtitle

    func allowedContentTypes(
        mediaTypes: [UTType],
        subtitleTypes: [UTType]
    ) -> [UTType] {
        switch self {
        case .video:
            mediaTypes
        case .primarySubtitle:
            subtitleTypes
        }
    }
}

private enum VideoMiningHistoryNotice: String, Identifiable {
    case saved
    case copied
    case noSubtitle
    case disabled

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .saved:
            "Saved to Mining History"
        case .copied:
            "Subtitle Copied"
        case .noSubtitle:
            "No subtitle is active at the current time."
        case .disabled:
            "Mining History is disabled in Video Settings."
        }
    }

    var systemImage: String {
        switch self {
        case .saved, .copied:
            "checkmark.circle.fill"
        case .noSubtitle, .disabled:
            "exclamationmark.triangle.fill"
        }
    }
}

#endif
