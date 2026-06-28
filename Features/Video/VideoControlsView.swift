#if HOSHI_VIDEO
import AppKit
import SwiftUI

struct VideoControlsMetrics {
    let chromeSize: CGSize
    let controlHeight: CGFloat
    let subtitleBottomClearance: CGFloat
    let popupBottomInset: CGFloat
    let bottomInset: CGFloat
}

struct VideoControlsView: View {
    let snapshot: VideoPlaybackSnapshot
    let timelinePreview: VideoTimelinePreview?
    let playlist: VideoPlaylist
    let profiles: [HoshiProfile]
    let selectedProfileID: String
    let canMineCurrentSubtitle: Bool
    let isFullScreen: Bool
    let layout: VideoControlBarLayout
    let availableWidth: CGFloat
    var onTogglePlayback: () -> Void
    var onSeek: (TimeInterval) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onSetVolume: (Double) -> Void
    var onToggleMuted: () -> Void
    var onSetSpeed: (Double) -> Void
    var onSelectProfile: (String) -> Void
    var onToggleMiningHistory: () -> Void
    var onOpenVideo: () -> Void
    var onMineCurrentSubtitle: () -> Void
    var onToggleInspector: () -> Void
    var onToggleFullScreen: () -> Void
    var onTimelinePreviewTimeChanged: (TimeInterval?) -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var isProgressPreviewActive = false
    @State private var isProgressHovering = false
    @State private var previewTime: TimeInterval?
    @State private var previewX: CGFloat = 0
    @State private var progressWidth: CGFloat = Self.progressSliderWidth
    @State private var progressFrame: CGRect = .zero
    @State private var progressPreviewHideTask: Task<Void, Never>?
    @State private var isSpeedPanelVisible = false
    @State private var speedInputText = ""

    private static let controlsWidth: CGFloat = 760
    private static let controlsHeight: CGFloat = 86
    private static let compactControlsHeight: CGFloat = 58
    static let timelinePreviewChromeHeight: CGFloat = 204
    private static let compactTimelinePreviewChromeHeight: CGFloat = 108
    private static let progressSliderWidth: CGFloat = 330
    private static let progressStripWidth: CGFloat = 442
    private static let progressSliderLeadingInStrip: CGFloat = 52
    private static let progressSliderTopInControls: CGFloat = 49
    private static let compactHorizontalPadding: CGFloat = 30
    private static let compactProgressSliderTop: CGFloat = 44
    private static let timelinePreviewWidth: CGFloat = 156
    private static let timelinePreviewBubbleCenterY: CGFloat = -70
    private static let compactTimelinePreviewBubbleCenterY: CGFloat = -54
    private static let controlsCoordinateSpace = "video-controls"
    private static let speedPanelWidth: CGFloat = 258
    private static let speedPanelCenterX: CGFloat = 552
    private static let speedPanelCenterY: CGFloat = 68
    private static let compactSpeedPanelCenterY: CGFloat = 18
    private static let speedPresetRows = [
        [0.25, 0.5, 1.0, 1.5],
        [2.0, 3.0, 4.0, 5.0]
    ]

    static func metrics(for layout: VideoControlBarLayout) -> VideoControlsMetrics {
        switch layout {
        case .floating:
            VideoControlsMetrics(
                chromeSize: CGSize(width: controlsWidth, height: timelinePreviewChromeHeight),
                controlHeight: controlsHeight,
                subtitleBottomClearance: 142,
                popupBottomInset: 56,
                bottomInset: 24
            )
        case .compactBottom:
            VideoControlsMetrics(
                chromeSize: CGSize(width: controlsWidth, height: compactTimelinePreviewChromeHeight),
                controlHeight: compactControlsHeight,
                subtitleBottomClearance: 72,
                popupBottomInset: 28,
                bottomInset: 0
            )
        }
    }

    private var activeChromeWidth: CGFloat {
        switch layout {
        case .floating:
            Self.controlsWidth
        case .compactBottom:
            max(availableWidth, Self.controlsWidth)
        }
    }

    private var compactProgressSliderWidth: CGFloat {
        max(activeChromeWidth - Self.compactHorizontalPadding * 2, 220)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch layout {
            case .floating:
                floatingControls
                    .modifier(VideoFloatingGlassSurface())
                    .zIndex(0)
            case .compactBottom:
                compactBottomControls
                    .zIndex(0)
            }

            if isSpeedPanelVisible {
                speedControlPanel
                    .position(speedPanelPosition)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
            }

            if let preview = activeTimelinePreview {
                let progressFrame = effectiveProgressFrame
                timelinePreviewBubble(preview)
                    .position(
                        x: progressFrame.minX + clampedPreviewX(in: progressFrame.width),
                        y: progressFrame.minY + timelinePreviewBubbleCenterY
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: Self.controlsCoordinateSpace)
        .frame(
            width: activeChromeWidth,
            height: Self.metrics(for: layout).chromeSize.height,
            alignment: .bottom
        )
        .onPreferenceChange(VideoProgressFramePreferenceKey.self) { frame in
            progressFrame = frame
        }
        .onChange(of: snapshot.speed) { _, _ in
            synchronizeSpeedInput()
        }
        .onDisappear {
            progressPreviewHideTask?.cancel()
            progressPreviewHideTask = nil
            onTimelinePreviewTimeChanged(nil)
        }
    }

    private var floatingControls: some View {
        VStack(spacing: 7) {
            primaryControlGroup
            progressControlStrip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            controlDragSurface
        }
        .frame(width: Self.controlsWidth)
    }

    private var compactBottomControls: some View {
        VStack(spacing: 6) {
            timelineProgressControl
                .frame(width: compactProgressSliderWidth, height: 16)

            HStack(spacing: 8) {
                episodeControls

                volumeControl
                    .frame(width: 112, alignment: .leading)

                Text(compactTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 106, alignment: .leading)

                Spacer(minLength: 0)

                speedControlButton
                utilityControlGroup
            }
            .padding(.horizontal, Self.compactHorizontalPadding)
        }
        .frame(width: activeChromeWidth, height: Self.metrics(for: .compactBottom).chromeSize.height, alignment: .bottom)
        .background(alignment: .bottom) {
            compactBottomScrim
        }
    }

    private var compactBottomScrim: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.30),
                Color.black.opacity(0.16),
                Color.black.opacity(0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: Self.metrics(for: .compactBottom).chromeSize.height)
        .allowsHitTesting(false)
    }

    private var controlDragSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.001))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        onDragChanged(value.translation)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation)
                    }
            )
    }

    private var primaryControlGroup: some View {
        HStack(spacing: 10) {
            volumeControl
                .frame(width: 112, alignment: .leading)

            Spacer(minLength: 0)

            episodeControls

            Spacer(minLength: 0)

            speedControlButton
            utilityControlGroup
        }
    }

    private var utilityControlGroup: some View {
        HStack(spacing: 10) {
            miningHistoryButton
            openVideoButton
            profileMenu
            mineCurrentSubtitleButton
            inspectorButton
            fullScreenButton
        }
    }

    private var miningHistoryButton: some View {
        Button(action: onToggleMiningHistory) {
            Label("Mining History", systemImage: "clock.arrow.circlepath")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(VideoGlassIconButtonStyle())
        .help("Mining History")
    }

    private var openVideoButton: some View {
        Button(action: onOpenVideo) {
            Label("Open Video", systemImage: "film")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(VideoGlassIconButtonStyle())
        .help("Open Video")
    }

    private var mineCurrentSubtitleButton: some View {
        Button(action: onMineCurrentSubtitle) {
            Label("Mine Current Subtitle", systemImage: "tray.and.arrow.down")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(VideoGlassIconButtonStyle())
        .disabled(!canMineCurrentSubtitle)
        .help("Mine Current Subtitle")
    }

    private var inspectorButton: some View {
        Button(action: onToggleInspector) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(VideoGlassIconButtonStyle())
        .help("Inspector")
    }

    private var fullScreenButton: some View {
        Button(action: onToggleFullScreen) {
            Image(systemName: isFullScreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(VideoGlassIconButtonStyle())
        .help("Toggle Full Screen")
    }

    private var speedControlButton: some View {
        Button {
            synchronizeSpeedInput()
            withAnimation(.smooth(duration: 0.16)) {
                isSpeedPanelVisible.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Label("Playback Speed", systemImage: "speedometer")
                    .labelStyle(.iconOnly)
                    .imageScale(.small)
                Text(VideoPlaybackSpeed.label(snapshot.speed))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 30, alignment: .leading)
            }
            .frame(width: 66, height: 28)
        }
        .buttonStyle(VideoSpeedControlButtonStyle(isSelected: isSpeedPanelVisible))
        .help("Playback Speed")
        .accessibilityLabel(Text("Playback Speed"))
        .accessibilityValue(Text(VideoPlaybackSpeed.label(snapshot.speed)))
    }

    private var speedControlPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Playback Speed", systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 0)

                Text(VideoPlaybackSpeed.label(snapshot.speed))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(Self.speedPresetRows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { speed in
                        Button {
                            setSpeed(speed)
                        } label: {
                            Text(Self.speedLabel(speed))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                        }
                        .buttonStyle(VideoSpeedPresetButtonStyle(isSelected: isSpeedSelected(speed)))
                    }
                }
            }

            HStack(spacing: 10) {
                Slider(
                    value: Binding<Double>(
                        get: { sliderSpeed },
                        set: { setSpeed($0) }
                    ),
                    in: VideoPlaybackSpeed.customInputLowerBound...VideoPlaybackSpeed.maximum,
                    step: VideoPlaybackSpeed.customStep
                )
                .controlSize(.small)

                HStack(spacing: 3) {
                    TextField("Custom", text: $speedInputText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 48)
                        .onSubmit {
                            commitSpeedInput()
                        }
                    Text(verbatim: "x")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .modifier(VideoControlsTextFieldGlassSurface(cornerRadius: 10))
            }
        }
        .padding(10)
        .frame(width: Self.speedPanelWidth)
        .modifier(VideoFloatingGlassSurface())
        .onAppear {
            synchronizeSpeedInput()
        }
    }

    private var profileMenu: some View {
        Menu {
            Picker(
                "Video Profile",
                selection: Binding<String>(
                    get: { selectedProfileID },
                    set: { onSelectProfile($0) }
                )
            ) {
                ForEach(profiles) { profile in
                    Text(profile.displayName)
                        .tag(profile.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "person.crop.circle")
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help(profileMenuHelp)
        .accessibilityLabel(Text(profileMenuHelp))
    }

    private var selectedProfileName: String {
        profiles.first { $0.id == selectedProfileID }?.displayName
            ?? String(localized: "Video Profile")
    }

    private var profileMenuHelp: String {
        String(format: String(localized: "Video Profile: %@"), selectedProfileName)
    }

    private var progressControlStrip: some View {
        HStack(spacing: 8) {
            Text(VideoTimeFormatter.string(from: isScrubbing ? scrubTime : snapshot.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            timelineProgressControl
                .frame(width: Self.progressSliderWidth, height: 18)

            Text(remainingTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
        }
    }

    private var episodeControls: some View {
        HStack(spacing: 6) {
            Button(action: onPrevious) {
                Image(systemName: "backward.end.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .disabled(playlist.previousURL == nil)
            .help("Previous Episode")

            Button(action: onTogglePlayback) {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(VideoPlaybackButtonStyle())
            .help(snapshot.isPlaying ? "Pause" : "Play")

            Button(action: onNext) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .disabled(playlist.nextURL == nil)
            .help("Next Episode")
        }
    }

    private var timelineProgressControl: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                progressSlider
                    .frame(width: geometry.size.width)
                    .background {
                        VideoProgressHoverBridge(
                            onHover: { localX in
                                handleProgressHover(
                                    localX: localX,
                                    width: geometry.size.width
                                )
                            },
                            onExit: {
                                handleProgressExit()
                            }
                        )
                        .allowsHitTesting(false)
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: VideoProgressFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(Self.controlsCoordinateSpace))
                                )
                        }
                    }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    handleProgressHover(
                        localX: location.x,
                        width: geometry.size.width
                    )
                case .ended:
                    handleProgressExit()
                }
            }
            .onAppear {
                progressWidth = geometry.size.width
            }
            .onChange(of: geometry.size) { _, size in
                progressWidth = size.width
            }
        }
    }

    private var progressSlider: some View {
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubTime : snapshot.currentTime },
                set: { value in
                    let time = clampedProgressTime(value)
                    scrubTime = time
                    updateProgressPreview(time: time)
                }
            ),
            in: 0...max(snapshot.duration, 0.01),
            onEditingChanged: { editing in
                isScrubbing = editing
                if editing {
                    let time = clampedProgressTime(snapshot.currentTime)
                    progressPreviewHideTask?.cancel()
                    isProgressPreviewActive = true
                    scrubTime = time
                    updateProgressPreview(time: time)
                } else {
                    onSeek(scrubTime)
                    isProgressPreviewActive = true
                    updateProgressPreview(time: scrubTime)
                    if !isProgressHovering {
                        scheduleProgressPreviewHide()
                    }
                }
            }
        )
        .controlSize(.small)
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Button(action: onToggleMuted) {
                Image(systemName: snapshot.isMuted || snapshot.volume == 0
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill")
                .frame(width: 26, height: 26)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help(snapshot.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { snapshot.volume },
                    set: { value in
                        onSetVolume(value)
                    }
                ),
                in: 0...100
            )
            .controlSize(.small)
            .frame(width: 84)
        }
    }

    private static func speedLabel(_ speed: Double) -> String {
        VideoPlaybackSpeed.label(speed)
    }

    private var selectedPresetSpeed: Double {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(snapshot.speed)
        return VideoPlaybackSpeed.presetChoices.first { abs($0 - normalizedSpeed) < 0.001 } ?? normalizedSpeed
    }

    private var sliderSpeed: Double {
        min(
            max(VideoPlaybackSpeed.normalized(snapshot.speed), VideoPlaybackSpeed.customInputLowerBound),
            VideoPlaybackSpeed.maximum
        )
    }

    private func isSpeedSelected(_ speed: Double) -> Bool {
        abs(selectedPresetSpeed - VideoPlaybackSpeed.normalized(speed)) < 0.001
    }

    private func setSpeed(_ speed: Double) {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(speed)
        speedInputText = VideoPlaybackSpeed.label(normalizedSpeed, includesSuffix: false)
        onSetSpeed(normalizedSpeed)
    }

    private func synchronizeSpeedInput() {
        speedInputText = VideoPlaybackSpeed.label(snapshot.speed, includesSuffix: false)
    }

    private func commitSpeedInput() {
        let normalizedText = speedInputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let speed = Double(normalizedText) else {
            synchronizeSpeedInput()
            return
        }
        setSpeed(speed)
    }

    private var remainingTimeText: String {
        let activeTime = isScrubbing ? scrubTime : snapshot.currentTime
        let remaining = max(snapshot.duration - activeTime, 0)
        return "-" + VideoTimeFormatter.string(from: remaining)
    }

    private var compactTimeText: String {
        let activeTime = isScrubbing ? scrubTime : snapshot.currentTime
        return "\(VideoTimeFormatter.string(from: activeTime)) / \(VideoTimeFormatter.string(from: snapshot.duration))"
    }

    private var activeTimelinePreview: VideoTimelinePreview? {
        guard let previewTime, isProgressPreviewActive || isScrubbing else {
            return nil
        }

        if let timelinePreview,
           abs(timelinePreview.time - previewTime) < 0.75 {
            return VideoTimelinePreview(
                time: previewTime,
                pngData: timelinePreview.pngData
            )
        }

        return VideoTimelinePreview(time: previewTime, pngData: nil)
    }

    private var effectiveProgressFrame: CGRect {
        if progressFrame.width > 0 {
            return progressFrame
        }

        switch layout {
        case .floating:
            let controlsTop = Self.timelinePreviewChromeHeight - Self.controlsHeight
            let progressStripLeading = (Self.controlsWidth - Self.progressStripWidth) / 2
            return CGRect(
                x: progressStripLeading + Self.progressSliderLeadingInStrip,
                y: controlsTop + Self.progressSliderTopInControls,
                width: Self.progressSliderWidth,
                height: 18
            )
        case .compactBottom:
            return CGRect(
                x: (activeChromeWidth - compactProgressSliderWidth) / 2,
                y: Self.compactProgressSliderTop,
                width: compactProgressSliderWidth,
                height: 16
            )
        }
    }

    private var speedPanelPosition: CGPoint {
        switch layout {
        case .floating:
            CGPoint(x: Self.speedPanelCenterX, y: Self.speedPanelCenterY)
        case .compactBottom:
            CGPoint(x: max(activeChromeWidth - 222, Self.speedPanelWidth / 2), y: Self.compactSpeedPanelCenterY)
        }
    }

    private var timelinePreviewBubbleCenterY: CGFloat {
        switch layout {
        case .floating:
            Self.timelinePreviewBubbleCenterY
        case .compactBottom:
            Self.compactTimelinePreviewBubbleCenterY
        }
    }

    private func handleProgressHover(localX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        progressPreviewHideTask?.cancel()
        progressPreviewHideTask = nil
        isProgressHovering = true
        isProgressPreviewActive = true
        previewX = min(max(localX, 0), width)
        updateProgressPreview(time: progressTime(for: previewX, width: width))
    }

    private func handleProgressExit() {
        isProgressHovering = false
        guard !isScrubbing else { return }
        if progressPreviewHideTask != nil {
            return
        }
        isProgressPreviewActive = false
        previewTime = nil
        onTimelinePreviewTimeChanged(nil)
    }

    private func updateProgressPreview(time: TimeInterval) {
        let time = clampedProgressTime(time)
        progressPreviewHideTask?.cancel()
        progressPreviewHideTask = nil
        previewX = progressX(for: time, width: progressWidth)
        previewTime = time
        onTimelinePreviewTimeChanged(time)
    }

    private func progressTime(for x: CGFloat, width: CGFloat) -> TimeInterval {
        guard snapshot.duration > 0, width > 0 else { return 0 }
        let progress = min(max(Double(x / width), 0), 1)
        return clampedProgressTime(snapshot.duration * progress)
    }

    private func progressX(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard snapshot.duration > 0, width > 0 else { return 0 }
        let progress = min(max(time / snapshot.duration, 0), 1)
        return CGFloat(progress) * width
    }

    private func clampedProgressTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        return min(max(time, 0), max(snapshot.duration, 0))
    }

    private func clampedPreviewX(in width: CGFloat) -> CGFloat {
        guard width > Self.timelinePreviewWidth else {
            return max(width / 2, 0)
        }
        let halfWidth = Self.timelinePreviewWidth / 2
        return min(max(previewX, halfWidth), width - halfWidth)
    }

    private func scheduleProgressPreviewHide() {
        progressPreviewHideTask?.cancel()
        progressPreviewHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            guard !isScrubbing, !isProgressHovering else {
                progressPreviewHideTask = nil
                return
            }
            isProgressPreviewActive = false
            previewTime = nil
            progressPreviewHideTask = nil
            onTimelinePreviewTimeChanged(nil)
        }
    }

    private func timelinePreviewBubble(_ preview: VideoTimelinePreview) -> some View {
        Text(VideoTimeFormatter.string(from: preview.time))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: Self.timelinePreviewWidth)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
    }
}

private struct VideoProgressFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct VideoProgressHoverBridge: NSViewRepresentable {
    var onHover: (CGFloat) -> Void
    var onExit: () -> Void

    func makeNSView(context: Context) -> VideoProgressHoverMonitorView {
        let view = VideoProgressHoverMonitorView()
        view.onHover = onHover
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: VideoProgressHoverMonitorView, context: Context) {
        nsView.onHover = onHover
        nsView.onExit = onExit
        nsView.updateMonitorState()
    }
}

private final class VideoProgressHoverMonitorView: NSView {
    var onHover: (CGFloat) -> Void = { _ in }
    var onExit: () -> Void = {}

    nonisolated(unsafe) private var mouseMonitor: Any?
    private var isInside = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitorState()
    }

    deinit {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    func updateMonitorState() {
        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitor()
        }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        isInside = false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let window, event.window === window else {
            notifyExitIfNeeded()
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else {
            notifyExitIfNeeded()
            return
        }

        isInside = true
        onHover(min(max(location.x, 0), bounds.width))
    }

    private func notifyExitIfNeeded() {
        guard isInside else { return }
        isInside = false
        onExit()
    }
}

private struct VideoFloatingGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: 10) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct VideoGlassIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background {
                if configuration.isPressed {
                    Circle().fill(.white.opacity(0.12))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Circle())
    }
}

private struct VideoSpeedControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(buttonFill(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.22 : 0.12), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func buttonFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.16)
        }
        if isSelected {
            return Color.white.opacity(0.12)
        }
        return Color.white.opacity(0.04)
    }
}

private struct VideoSpeedPresetButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(buttonFill(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.22 : 0.1), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func buttonFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.16)
        }
        if isSelected {
            return Color.accentColor.opacity(0.24)
        }
        return Color.white.opacity(0.05)
    }
}

private struct VideoControlsTextFieldGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct VideoPlaybackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .glassEffect(.regular.interactive(), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
#endif
