#if HOSHI_VIDEO
import AppKit
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

struct VideoPlayerScreen: View {
    let isActive: Bool

    @Environment(UserConfig.self) private var userConfig
    @Environment(ShortcutManager.self) private var shortcutManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = VideoPlayerViewModel(engine: MpvPlayerEngine())
    @State private var subtitles = VideoSubtitleController()
    @State private var lookup = VideoLookupCoordinator()
    @State private var miningHistory = VideoMiningHistoryStore()
    @State private var profileRepository = ProfileRepository.shared
    @State private var isInspectorVisible = false
    @State private var isMiningHistoryVisible = false
    @State private var selectedStudySidebarTab: VideoStudySidebarTab = .history
    @State private var isPlaybackChromeVisible = true
    @State private var isPointerInsidePlayerSurface = true
    @State private var isPointerOverPlaybackChrome = false
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

    private static let playbackChromeSize = CGSize(width: 680, height: 86)
    private static let playbackChromeEdgeInset: CGFloat = 16
    private static let playbackChromeBottomInset: CGFloat = 24

    private static let mpvMediaExtensions = [
        "mkv", "webm", "avi", "m4v", "mp4", "mov", "qt",
        "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "ogv",
        "wmv", "asf", "flv",
        "m4b", "m4a", "mp3", "flac", "opus", "ogg", "oga",
        "weba", "wav", "aac", "aiff", "aif", "ape", "wv"
    ]

    private static let subtitleFileExtensions = ["srt", "vtt"]

    private let mediaTypes: [UTType] = {
        var types: [UTType] = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie]
        for fileExtension in Self.mpvMediaExtensions {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        return types
    }()

    private let subtitleTypes: [UTType] = Self.subtitleFileExtensions.compactMap {
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
                miningHistory.updateLimit(userConfig.videoMiningHistoryLimit)
                installEmbeddedSubtitleHandler()
                synchronizeSelectedSubtitleTrack()
                if isActive {
                    registerKeyboardShortcuts()
                }
                schedulePlaybackChromeAutoHide()
            }
            .onChange(of: isActive) { _, isActive in
                if isActive {
                    registerKeyboardShortcuts()
                    revealPlaybackChrome(scheduleHide: true)
                } else {
                    unregisterKeyboardShortcuts()
                }
            }
            .onChange(of: userConfig.videoAutoPlayNext) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoRememberPlaybackPosition) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoMiningHistoryLimit) { _, limit in
                miningHistory.updateLimit(limit)
            }
            .onChange(of: model.snapshot.tracks) { _, _ in
                restorePendingHistorySubtitleTrackIfAvailable()
                synchronizeSelectedSubtitleTrack()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    hidePlaybackChromeForPointerExit()
                }
            }
            .onDisappear {
                unregisterKeyboardShortcuts()
                playbackChromeAutoHideTask?.cancel()
                miningHistoryNoticeTask?.cancel()
                subtitleTrackExtractionTask?.cancel()
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
            .ignoresSafeArea(.container, edges: .top)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDroppedItems(providers)
            }
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
                subtitleTrackExtractionTask?.cancel()
                subtitleTrackExtractionTask = nil
                activeSubtitleTrackExtractionKey = nil
                if newURL != nil {
                    revealPlaybackChrome(scheduleHide: true)
                } else {
                    playbackChromeAutoHideTask?.cancel()
                    isPlaybackChromeVisible = true
                }
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
                        selectedTab: $selectedStudySidebarTab,
                        items: miningHistory.items,
                        transcript: subtitles.transcript,
                        chapters: model.snapshot.chapters,
                        currentTime: model.snapshot.currentTime,
                        isTranscriptLoading: subtitles.isTranscriptLoading,
                        transcriptErrorMessage: subtitles.transcriptErrorMessage,
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

    private var videoCanvas: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                MpvRenderView(engine: model.engine as! MpvPlayerEngine)
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
                } else if areSubtitlesVisible {
                    SubtitleOverlayView(
                        cues: subtitles.currentCues,
                        scanLength: userConfig.scanLength,
                        hoverLookupDelayMs: userConfig.desktopLookupHoverDelayMs,
                        maskEnabled: userConfig.videoSubtitleMaskEnabled,
                        maskMode: userConfig.videoSubtitleMaskMode,
                        maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius,
                        maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity,
                        fontFamily: userConfig.videoSubtitleFontFamily,
                        fontSize: userConfig.videoSubtitleFontSize,
                        isLookupPopupVisible: hasActiveVideoPopup
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

                if model.currentURL != nil, shouldShowPlaybackChrome {
                    VideoControlsView(
                        snapshot: model.snapshot,
                        playlist: model.playlist,
                        profiles: profileRepository.index.profiles,
                        selectedProfileID: resolvedVideoProfile.id,
                        canMineCurrentSubtitle: canMineCurrentSubtitle,
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
                        onSelectProfile: { profileID in
                            selectVideoProfile(profileID)
                            revealPlaybackChrome(scheduleHide: true)
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
                }

                if shouldShowPlaybackChrome {
                    videoTopControls
                        .onHover { hovering in
                            playbackChromeHoverChanged(hovering)
                        }
                        .transition(.opacity)
                        .zIndex(4)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.smooth(duration: 0.18), value: shouldShowPlaybackChrome)
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
            snapshot: model.snapshot,
            playlist: model.playlist,
            currentURL: model.currentURL,
            primarySubtitleName: subtitles.document?.sourceURL.lastPathComponent,
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
            onSelectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    cancelSubtitleTrackExtraction()
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
                cancelSubtitleTrackExtraction()
                subtitles.clearPrimary()
            },
            onOpenTranscript: {
                toggleTranscriptSidebar()
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

    @discardableResult
    private func loadPrimarySubtitle(
        from url: URL,
        loadIntoMpv: Bool
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
        lookup.closeAll(player: model)
        subtitles.clear()
        model.open(mediaURL)
        if let subtitleURL {
            loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
        } else {
            autoloadSubtitleIfAvailable(for: mediaURL)
        }
    }

    private func loadDroppedSubtitle(_ subtitleURL: URL) {
        guard model.currentURL != nil else { return }
        lookup.closeAll(player: model)
        loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
    }

    private func isMediaFile(_ url: URL) -> Bool {
        Self.mpvMediaExtensions.contains(url.pathExtension.lowercased())
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
                    captureScreenshot: true,
                    captureAudioClip: true
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
                        toggleTranscriptSidebar()
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
              !isPointerOverPlaybackChrome,
              !hasActiveVideoPopup,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            return
        }
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
        playbackChromeAutoHideTask?.cancel()
        isPointerInsidePlayerSurface = false
        isPointerOverPlaybackChrome = false
        withAnimation(.smooth(duration: 0.18)) {
            isPlaybackChromeVisible = false
        }
    }

    private func playbackChromeHoverChanged(_ hovering: Bool) {
        guard model.currentURL != nil else { return }
        isPointerOverPlaybackChrome = hovering
        if hovering {
            revealPlaybackChrome(scheduleHide: false)
        } else {
            schedulePlaybackChromeAutoHide()
        }
    }

    private func schedulePlaybackChromeAutoHide() {
        playbackChromeAutoHideTask?.cancel()
        guard model.currentURL != nil,
              isPlaybackChromeVisible,
              !isPointerOverPlaybackChrome,
              !hasActiveVideoPopup,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            return
        }
        playbackChromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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
                model.open(destination.videoURL)
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
        cancelSubtitleTrackExtraction()
        subtitles.clearPrimary()
        lastSelectedSubtitleTrackID = trackID
        model.selectTrack(type: .subtitle, id: trackID)
        pendingHistoryEmbeddedSubtitleTrackID = nil
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

    private func toggleSubtitlesVisible() {
        if areSubtitlesVisible {
            lastSelectedSubtitleTrackID = model.snapshot.tracks
                .first { $0.type == .subtitle && $0.isSelected }?
                .id
            model.selectTrack(type: .subtitle, id: nil)
            areSubtitlesVisible = false
        } else {
            let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            if let trackID {
                cancelSubtitleTrackExtraction()
                subtitles.clearPrimary()
                model.selectTrack(type: .subtitle, id: trackID)
            }
            areSubtitlesVisible = true
        }
    }

    private func cycleSubtitleTrack() -> Bool {
        let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
        guard !subtitleTracks.isEmpty else { return false }
        guard areSubtitlesVisible else {
            areSubtitlesVisible = true
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            cancelSubtitleTrackExtraction()
            subtitles.clearPrimary()
            model.selectTrack(type: .subtitle, id: trackID)
            return true
        }
        if let selectedIndex = subtitleTracks.firstIndex(where: \.isSelected) {
            let nextIndex = subtitleTracks.index(after: selectedIndex)
            if nextIndex < subtitleTracks.endIndex {
                let id = subtitleTracks[nextIndex].id
                lastSelectedSubtitleTrackID = id
                cancelSubtitleTrackExtraction()
                subtitles.clearPrimary()
                model.selectTrack(type: .subtitle, id: id)
            } else {
                lastSelectedSubtitleTrackID = subtitleTracks[selectedIndex].id
                cancelSubtitleTrackExtraction()
                subtitles.clearPrimary()
                model.selectTrack(type: .subtitle, id: nil)
            }
        } else {
            let id = subtitleTracks[0].id
            lastSelectedSubtitleTrackID = id
            cancelSubtitleTrackExtraction()
            subtitles.clearPrimary()
            model.selectTrack(type: .subtitle, id: id)
        }
        return true
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
