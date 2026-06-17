#if HOSHI_VIDEO
import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let videoScreenLog = Logger(subsystem: "de.manhhao.hoshi", category: "VideoScreen")

struct VideoPlayerScreen: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(ShortcutManager.self) private var shortcutManager
    @State private var model = VideoPlayerViewModel(engine: MpvPlayerEngine())
    @State private var subtitles = VideoSubtitleController()
    @State private var lookup = VideoLookupCoordinator()
    @State private var miningHistory = VideoMiningHistoryStore()
    @State private var isInspectorVisible = false
    @State private var isMiningHistoryVisible = false
    @State private var selectedInspectorTab: VideoInspectorTab = .subtitles
    @State private var shortcutRegistrationIDs: [UUID] = []
    @State private var pendingFileImportKind: VideoFileImportKind?
    @State private var activeFileImportKind: VideoFileImportKind?

    private let mediaTypes: [UTType] = {
        var types: [UTType] = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie]
        let mpvMediaExtensions = [
            "mkv", "webm", "avi", "m4v", "mp4", "mov", "qt",
            "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "ogv",
            "wmv", "asf", "flv",
            "m4b", "m4a", "mp3", "flac", "opus", "ogg", "oga",
            "weba", "wav", "aac", "aiff", "aif", "ape", "wv"
        ]
        for fileExtension in mpvMediaExtensions {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        return types
    }()

    private let subtitleTypes: [UTType] = ["srt", "vtt"].compactMap {
        UTType(filenameExtension: $0)
    }

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        observedContent
            .fileImporter(
                isPresented: fileImporterPresentation,
                allowedContentTypes: (pendingFileImportKind ?? activeFileImportKind)?.allowedContentTypes(
                    mediaTypes: mediaTypes,
                    subtitleTypes: subtitleTypes
                ) ?? mediaTypes,
                allowsMultipleSelection: false
            ) { result in
                guard let kind = activeFileImportKind ?? pendingFileImportKind else { return }
                pendingFileImportKind = nil
                activeFileImportKind = nil
                handleFileImport(result, kind: kind)
            }
            .onAppear {
                synchronizePlaybackPreferences()
                installEmbeddedSubtitleHandler()
                registerKeyboardShortcuts()
            }
            .onChange(of: userConfig.videoAutoPlayNext) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoRememberPlaybackPosition) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onDisappear {
                unregisterKeyboardShortcuts()
                model.engine.onEmbeddedSubtitleCuesChanged = nil
                lookup.closeAll(player: model)
                model.shutdown()
            }
            .alert("Video Error", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? subtitles.errorMessage ?? "")
            }
    }

    private var observedContent: some View {
        playerSurface
            .onChange(of: model.snapshot.currentTime) { _, time in
                subtitles.update(
                    time: time,
                    subtitleDelay: model.snapshot.subtitleDelay
                )
            }
            .onChange(of: model.snapshot.subtitleDelay) { _, delay in
                subtitles.update(
                    time: model.snapshot.currentTime,
                    subtitleDelay: delay
                )
            }
            .onChange(of: model.currentURL) { oldURL, newURL in
                guard oldURL != nil, oldURL != newURL else { return }
                lookup.closeAll(player: model)
                subtitles.clear()
            }
    }

    private var playerSurface: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                videoSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if isMiningHistoryVisible {
                    VideoMiningHistorySidebar(
                        items: miningHistory.items,
                        onClose: {
                            withAnimation(.smooth(duration: 0.22)) {
                                isMiningHistoryVisible = false
                            }
                        },
                        onSeek: { time in
                            dismissVideoPopupsIfNeeded()
                            model.seek(to: time)
                        },
                        onDelete: { id in
                            miningHistory.delete(id: id)
                        },
                        onClear: {
                            miningHistory.clear()
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .animation(.smooth(duration: 0.22), value: isMiningHistoryVisible)
        }
    }

    private var videoSurface: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                ZStack(alignment: .trailing) {
                    videoCanvas
                    if isInspectorVisible {
                        inspectorOverlay
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(5)
                    }
                }
                .animation(.smooth(duration: 0.22), value: isInspectorVisible)
                .coordinateSpace(name: "video-player")

                ForEach(lookup.presentation.popups) { popup in
                    popupView(popup, screenSize: geometry.size)
                }
            }
        }
    }

    private var videoCanvas: some View {
        ZStack(alignment: .bottom) {
            MpvRenderView(engine: model.engine as! MpvPlayerEngine)

            videoWindowDragStrip
                .zIndex(0.5)

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
            } else {
                SubtitleOverlayView(
                    cues: subtitles.currentCues,
                    scanLength: userConfig.scanLength,
                    maskEnabled: userConfig.videoSubtitleMaskEnabled,
                    maskMode: userConfig.videoSubtitleMaskMode,
                    maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius,
                    maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity
                ) { cue, selection in
                    _ = lookup.present(
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
                    playlist: model.playlist,
                    onTogglePlayback: model.togglePlayback,
                    onSeek: model.seek,
                    onPrevious: model.playPrevious,
                    onNext: model.playNext,
                    onSetVolume: model.setVolume,
                    onToggleMuted: model.toggleMuted,
                    onToggleInspector: {
                        dismissVideoPopupsThen {
                            toggleInspector()
                        }
                    },
                    onToggleFullScreen: {
                        dismissVideoPopupsThen {
                            toggleFullScreen()
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .zIndex(3)
            }

            videoTopControls
                .zIndex(4)
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

    private var videoTopControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    toggleSidebar()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.leading")
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(VideoTopGlassButtonStyle())
                .help("Sidebar")

                if model.currentURL != nil {
                    Button {
                        dismissVideoPopupsThen {
                            toggleMiningHistory()
                        }
                    } label: {
                        Label("Mining History", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(VideoTopGlassButtonStyle())
                    .help("Mining History")

                    Button {
                        dismissVideoPopupsThen {
                            presentFileImporter(.video)
                        }
                    } label: {
                        Label("Open Video", systemImage: "film")
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(VideoTopGlassButtonStyle())
                    .help("Open Video")
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
    }

    private var inspectorOverlay: some View {
        VideoInspectorView(
            selectedTab: $selectedInspectorTab,
            snapshot: model.snapshot,
            playlist: model.playlist,
            currentURL: model.currentURL,
            primarySubtitleName: subtitles.document?.sourceURL.lastPathComponent,
            transcript: subtitles.transcript,
            onSelectEpisode: { url in
                dismissVideoPopupsIfNeeded()
                model.selectPlaylistItem(url)
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
            onSeekToChapter: { chapter in
                dismissVideoPopupsIfNeeded()
                model.seekToChapter(chapter)
            },
            onSelectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    subtitles.clearPrimary()
                }
                model.selectTrack(type: type, id: id)
            },
            onOpenSubtitle: {
                dismissVideoPopupsIfNeeded()
                presentFileImporter(.primarySubtitle)
            },
            onClearPrimarySubtitle: {
                dismissVideoPopupsIfNeeded()
                subtitles.clearPrimary()
            },
            onSeekTranscript: { time in
                dismissVideoPopupsIfNeeded()
                model.seek(to: time)
            },
            onClose: {
                dismissVideoPopupsIfNeeded()
                isInspectorVisible = false
            }
        )
        .padding(.vertical, 16)
        .padding(.trailing, 16)
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
            lookup.closeAll(player: model)
            subtitles.clear()
            model.open(url)
            autoloadSubtitleIfAvailable(for: url)
        }
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

    private func loadPrimarySubtitle(from url: URL, loadIntoMpv: Bool) {
        if loadIntoMpv {
            model.loadExternalSubtitle(url)
        }
        let loadTask = subtitles.load(url)
        Task { @MainActor in
            await loadTask.value
            subtitles.update(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
        }
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
                lookup.closeAll(player: model)
            },
            onSwipeDismiss: {
                lookup.dismiss(id: popupID, player: model)
            },
            miningContextProvider: { _ in
                guard let cue = lookup.activeCue,
                      let videoURL = model.currentURL else {
                    return MiningContext(
                        sentence: popup.currentSelection?.sentence ?? "",
                        documentTitle: model.currentURL?.lastPathComponent,
                        coverURL: nil
                    )
                }
                return await VideoMiningCoordinator.context(
                    cue: cue,
                    document: subtitles.document,
                    videoURL: videoURL,
                    engine: model.engine,
                    captureScreenshot: AnkiManager.shared.needsVideoScreenshot,
                    captureAudioClip: AnkiManager.shared.needsVideoAudioClip
                )
            },
            onMiningStarted: { content, context in
                let historyID = miningHistory.recordPending(
                    content: content,
                    context: context
                )
                if historyID != nil {
                    withAnimation(.smooth(duration: 0.22)) {
                        isMiningHistoryVisible = true
                    }
                }
                return historyID
            },
            onMiningFinished: { id, result in
                miningHistory.update(
                    id: id,
                    status: VideoMiningHistoryStatus(result.status),
                    message: result.message
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
                        model.adjustSpeed(by: -0.25)
                        return true
                    },
                    VideoShortcutActions.increaseSpeed.id: {
                        model.adjustSpeed(by: 0.25)
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
                    VideoShortcutActions.subtitleEarlier.id: {
                        model.adjustSubtitleDelay(by: -0.5)
                        return true
                    },
                    VideoShortcutActions.subtitleLater.id: {
                        model.adjustSubtitleDelay(by: 0.5)
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
                        dismissVideoPopupsThen {
                            toggleInspector(tab: .transcript)
                        }
                        return true
                    },
                    VideoShortcutActions.rotateClockwise.id: {
                        model.rotateClockwise()
                        return true
                    },
                    VideoShortcutActions.toggleFullScreen.id: {
                        guard NSApp.keyWindow != nil else { return false }
                        dismissVideoPopupsThen {
                            toggleFullScreen()
                        }
                        return true
                    },
                    VideoShortcutActions.exitFocusMode.id: {
                        guard let window = NSApp.keyWindow,
                              window.styleMask.contains(.fullScreen) else {
                            return false
                        }
                        window.toggleFullScreen(nil)
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
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func toggleSidebar() {
        dismissVideoPopupsIfNeeded()
        NSApp.sendAction(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            to: nil,
            from: nil
        )
    }

    private func toggleMiningHistory() {
        videoScreenLog.info(
            "Toggling video mining history visible=\(self.isMiningHistoryVisible)"
        )
        isMiningHistoryVisible.toggle()
    }

    private var hasActiveVideoPopup: Bool {
        !lookup.presentation.popups.isEmpty
    }

    private var shouldShowVideoDismissLayer: Bool {
        hasActiveVideoPopup || isInspectorVisible
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

private extension VideoMiningHistoryStatus {
    init(_ status: AnkiMiningStatus) {
        switch status {
        case .added:
            self = .added
        case .duplicate:
            self = .duplicate
        case .failed:
            self = .failed
        case .pending:
            self = .pending
        }
    }
}

private struct VideoTopGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .glassEffect(.regular.interactive(), in: Circle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
        } else {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
        }
    }
}
#endif
