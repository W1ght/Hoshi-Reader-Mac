#if HOSHI_VIDEO
import AppKit
import SwiftUI

enum VideoInspectorTab: String, CaseIterable, Identifiable {
    case episodes
    case video
    case audio
    case subtitles

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .episodes: "Episodes"
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        }
    }

    var systemName: String {
        switch self {
        case .episodes: "list.number"
        case .video: "film"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        }
    }
}

struct VideoInspectorView: View {
    static let minimumWidth: CGFloat = 300
    static let idealWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 400

    @Environment(UserConfig.self) private var userConfig
    @Binding var selectedTab: VideoInspectorTab
    @State private var speedInputText = ""
    @State private var subtitleTimingInputText = ""

    let snapshot: VideoPlaybackSnapshot
    let playlist: VideoPlaylist
    let currentURL: URL?
    let primarySubtitleName: String?

    var onSelectEpisode: (URL) -> Void
    var onSetSpeed: (Double) -> Void
    var onSetSubtitleDelay: (TimeInterval) -> Void
    var onSetAudioDelay: (TimeInterval) -> Void
    var onSetLoopMode: (VideoLoopMode) -> Void
    var onSetABLoopStart: () -> Void
    var onSetABLoopEnd: () -> Void
    var onClearABLoop: () -> Void
    var onSetAspectRatio: (VideoAspectRatio) -> Void
    var onRotateClockwise: () -> Void
    var onSelectTrack: (VideoTrackType, Int?) -> Void
    var onOpenSubtitle: () -> Void
    var onClearPrimarySubtitle: () -> Void
    var onOpenTranscript: () -> Void
    var onClose: () -> Void

    private let speedChoices = VideoPlaybackSpeed.presetChoices
    private let speedRows = [
        [0.25, 0.5, 1, 1.5],
        [2, 3, 4, 5],
    ]
    private static let subtitleTimingMinimumMilliseconds = -10_000
    private static let subtitleTimingMaximumMilliseconds = 10_000
    private static let subtitleTimingLargeStepMilliseconds = 1_000
    private static let subtitleTimingSmallStepMilliseconds = 50

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker

            Divider()
                .opacity(0.5)

            ScrollView {
                tabContent
                    .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: Self.minimumWidth, idealWidth: Self.idealWidth, maxWidth: Self.maximumWidth)
        .modifier(VideoInspectorGlassSurface(cornerRadius: 24))
        .onAppear {
            synchronizeSpeedInput()
            synchronizeSubtitleTimingInput()
        }
        .onChange(of: snapshot.speed) { _, _ in
            synchronizeSpeedInput()
        }
        .onChange(of: snapshot.subtitleDelay) { _, _ in
            synchronizeSubtitleTimingInput()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(VideoInspectorGlassButtonStyle(shape: .circle))
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        NativeGlassSegmentedPicker(
            selection: $selectedTab,
            values: VideoInspectorTab.allCases,
            minSegmentWidth: 42,
            fillsWidth: true
        ) { tab in
            VStack(spacing: 2) {
                Image(systemName: tab.systemName)
                    .font(.caption)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .episodes:
            episodesTab
        case .video:
            videoTab
        case .audio:
            audioTab
        case .subtitles:
            subtitlesTab
        }
    }

    private var episodesTab: some View {
        inspectorSection("Episodes", systemName: "list.number") {
            if playlist.items.isEmpty {
                emptyRow("No episodes")
            } else {
                ForEach(playlist.items, id: \.standardizedFileURL) { url in
                    selectionRow(
                        title: url.lastPathComponent,
                        subtitle: nil,
                        isSelected: url.standardizedFileURL == currentURL?.standardizedFileURL
                    ) {
                        onSelectEpisode(url)
                    }
                }
            }
        }
    }

    private var videoTab: some View {
        VStack(spacing: 12) {
            inspectorSection("Playback Speed", systemName: "speedometer") {
                ForEach(speedRows, id: \.self) { row in
                    NativeGlassSegmentedPicker(
                        selection: Binding<Double>(
                            get: { selectedPresetSpeed },
                            set: { setSpeed($0) }
                        ),
                        values: row,
                        minSegmentWidth: 44,
                        fillsWidth: true
                    ) { speed in
                        Text(Self.speedLabel(speed))
                            .font(.caption.weight(.semibold))
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
                    .modifier(VideoInspectorTextFieldGlassSurface(cornerRadius: 10))
                }
            }

            videoEnhancementSection

            trackSection(
                title: "Video Track",
                systemName: "film",
                type: .video,
                allowsOff: false
            )

            inspectorSection("Aspect Ratio", systemName: "rectangle.inset.filled") {
                NativeGlassSegmentedPicker(
                    selection: Binding<VideoAspectRatio>(
                        get: { snapshot.aspectRatio },
                        set: { onSetAspectRatio($0) }
                    ),
                    values: VideoAspectRatio.allCases,
                    minSegmentWidth: 48,
                    fillsWidth: true
                ) { aspectRatio in
                    Text(aspectRatio.title)
                        .font(.caption.weight(.semibold))
                }

                Button {
                    onRotateClockwise()
                } label: {
                    Label("Rotate Clockwise", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle())
            }

            inspectorSection("Loop", systemName: "repeat") {
                NativeGlassSegmentedPicker(
                    selection: Binding<Bool>(
                        get: { snapshot.loopMode == .file },
                        set: { onSetLoopMode($0 ? .file : .none) }
                    ),
                    values: [false, true],
                    minSegmentWidth: 100,
                    fillsWidth: true
                ) { isLooping in
                    Text(isLooping ? "Loop File" : "Off")
                        .font(.caption.weight(.semibold))
                }

                HStack(spacing: 8) {
                    Button("Set A Point", action: onSetABLoopStart)
                    Button("Set B Point", action: onSetABLoopEnd)
                    Button("Clear", action: onClearABLoop)
                        .disabled(snapshot.abLoop == nil)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle())
            }
        }
    }

    private var videoEnhancementSection: some View {
        inspectorSection("Video Enhancement", systemName: "sparkles.tv") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    Toggle("Hardware Decoding", isOn: videoHardwareDecodingEnabled)
                    Toggle("Deinterlace", isOn: videoDeinterlacingEnabled)
                    Toggle("HDR", isOn: videoHDREnhancementEnabled)
                }
                .toggleStyle(.switch)

                Divider()
                    .opacity(0.45)

                ForEach(VideoEqualizerAdjustment.allCases, id: \.self) { adjustment in
                    videoEqualizerSlider(
                        adjustment,
                        value: videoEqualizerBinding(adjustment)
                    )
                }
            }
        }
    }

    private var audioTab: some View {
        VStack(spacing: 12) {
            trackSection(
                title: "Audio Track",
                systemName: "waveform",
                type: .audio,
                allowsOff: true
            )
            timingSection(
                title: "Audio Timing",
                systemName: "waveform.badge.clock",
                value: snapshot.audioDelay,
                onEarlier: { onSetAudioDelay(max(snapshot.audioDelay - 0.5, -30)) },
                onReset: { onSetAudioDelay(0) },
                onLater: { onSetAudioDelay(min(snapshot.audioDelay + 0.5, 30)) }
            )
        }
    }

    private var subtitlesTab: some View {
        VStack(spacing: 12) {
            inspectorSection("External Subtitles", systemName: "captions.bubble") {
                Button {
                    onOpenSubtitle()
                } label: {
                    Label("Open Subtitles", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle())

                if let primarySubtitleName {
                    selectionRow(
                        title: primarySubtitleName,
                        subtitle: "Primary subtitle",
                        isSelected: true,
                        action: onClearPrimarySubtitle
                    )
                }

            }

            trackSection(
                title: "Subtitle Track",
                systemName: "captions.bubble",
                type: .subtitle,
                allowsOff: true,
                selectingSubtitleTrackClearsExternal: true
            )

            subtitleTimingSection

            subtitleAppearanceSection

            subtitleMaskSection

            inspectorSection("Transcript", systemName: "text.alignleft") {
                Button {
                    onOpenTranscript()
                } label: {
                    Label("Open Transcript", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle())
            }
        }
    }

    private var subtitleAppearanceSection: some View {
        inspectorSection("Subtitle Appearance", systemName: "textformat.size") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subtitle Font")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(selection: subtitleFontFamily) {
                        Text("System Default").tag("")
                        ForEach(Self.subtitleFontFamilies, id: \.self) { family in
                            Text(verbatim: family).tag(family)
                        }
                    } label: {
                        Text("Subtitle Font")
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Subtitle Size")
                        Spacer()
                        Text("\(Int(userConfig.videoSubtitleFontSize)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    Slider(
                        value: subtitleFontSize,
                        in: 12...72,
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Subtitle Weight")
                        Spacer()
                        Stepper(
                            "\(userConfig.videoSubtitleFontWeight)",
                            value: subtitleFontWeight,
                            in: 100...900,
                            step: 100
                        )
                        .labelsHidden()
                    }
                    .font(.caption)
                }

                subtitleAppearanceSlider(
                    title: "Shadow",
                    value: String(format: "%.1f", userConfig.videoSubtitleShadowRadius),
                    binding: subtitleShadowRadius,
                    range: 0...10,
                    step: 0.5
                )

                subtitleAppearanceSlider(
                    title: "Background Opacity",
                    value: "\(Int(userConfig.videoSubtitleBackgroundOpacity * 100))%",
                    binding: subtitleBackgroundOpacity,
                    range: 0...1,
                    step: 0.05
                )
                .disabled(userConfig.videoSubtitleBackgroundDisabled)

                Toggle("No Background", isOn: subtitleBackgroundDisabled)
                    .toggleStyle(.switch)
                    .font(.caption)

                subtitleAppearanceSlider(
                    title: "Vertical Position",
                    value: "\(Int(userConfig.videoSubtitleVerticalPosition))",
                    binding: subtitleVerticalPosition,
                    range: 0...100,
                    step: 1
                )

                ColorPicker("Subtitle Color", selection: subtitleColor)
                    .font(.caption)

                ColorPicker("Lookup Highlight Color", selection: subtitleLookupHighlightColor)
                    .font(.caption)

                ColorPicker("Lookup Highlight Text Color", selection: subtitleLookupHighlightTextColor)
                    .font(.caption)

                Button {
                    userConfig.resetVideoSubtitleAppearance()
                } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle())
            }
        }
    }

    private var subtitleMaskSection: some View {
        inspectorSection("Subtitle Mask", systemName: "eye.slash") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Mask subtitles until hover", isOn: subtitleMaskEnabled)
                    .toggleStyle(.switch)

                NativeGlassSegmentedPicker(
                    selection: subtitleMaskMode,
                    values: VideoSubtitleMaskMode.allCases,
                    minSegmentWidth: 96,
                    fillsWidth: true
                ) { mode in
                    Text(LocalizedStringKey(mode.rawValue))
                        .font(.caption.weight(.semibold))
                }
                .disabled(!userConfig.videoSubtitleMaskEnabled)

                if userConfig.videoSubtitleMaskMode == .blur {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Blur Radius")
                            Spacer()
                            Text("\(Int(userConfig.videoSubtitleMaskBlurRadius)) px")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: subtitleMaskBlurRadius,
                            in: 0...20,
                            step: 1
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Hidden Opacity")
                            Spacer()
                            Text("\(Int(userConfig.videoSubtitleMaskHiddenOpacity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: subtitleMaskHiddenOpacity,
                            in: 0...1,
                            step: 0.05
                        )
                    }
                }
            }
        }
    }

    private var subtitleTimingSection: some View {
        inspectorSection("Subtitle Timing", systemName: "captions.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Positive values delay subtitles; negative values show subtitles earlier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding<Double>(
                        get: { Double(subtitleTimingMilliseconds) },
                        set: { applySubtitleTimingMilliseconds(Int($0.rounded())) }
                    ),
                    in: Double(Self.subtitleTimingMinimumMilliseconds)...Double(Self.subtitleTimingMaximumMilliseconds),
                    step: Double(Self.subtitleTimingSmallStepMilliseconds)
                )

                HStack(spacing: 12) {
                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current - Self.subtitleTimingLargeStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .frame(width: 30, height: 30)
                    }
                    .help("Back 1000 ms")

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current - Self.subtitleTimingSmallStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 30, height: 30)
                    }
                    .help("Back 50 ms")

                    Spacer()

                    Text(subtitleTimingValueText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 86)

                    Spacer()

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current + Self.subtitleTimingSmallStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 30, height: 30)
                    }
                    .help("Forward 50 ms")

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current + Self.subtitleTimingLargeStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .frame(width: 30, height: 30)
                    }
                    .help("Forward 1000 ms")
                }
                .buttonStyle(VideoInspectorGlassButtonStyle(shape: .circle))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Offset (ms)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    HStack(spacing: 8) {
                        TextField("Offset", text: $subtitleTimingInputText)
                            .textFieldStyle(.plain)
                            .font(.title3.monospacedDigit())
                            .onSubmit {
                                commitSubtitleTimingInput()
                            }

                        Image(systemName: "keyboard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .modifier(VideoInspectorTextFieldGlassSurface(cornerRadius: 12))
                }
            }
        }
    }

    private func trackSection(
        title: LocalizedStringKey,
        systemName: String,
        type: VideoTrackType,
        allowsOff: Bool,
        selectingSubtitleTrackClearsExternal: Bool = false
    ) -> some View {
        let tracks = snapshot.tracks.filter { $0.type == type }
        return inspectorSection(title, systemName: systemName) {
            if allowsOff {
                selectionRow(
                    title: "Off",
                    subtitle: nil,
                    isSelected: !tracks.contains(where: \.isSelected)
                ) {
                    if selectingSubtitleTrackClearsExternal {
                        onClearPrimarySubtitle()
                    }
                    onSelectTrack(type, nil)
                }
            }

            if tracks.isEmpty {
                emptyRow("No tracks")
            } else {
                ForEach(tracks) { track in
                    selectionRow(
                        title: track.displayName,
                        subtitle: track.codec,
                        isSelected: track.isSelected
                    ) {
                        if selectingSubtitleTrackClearsExternal {
                            onClearPrimarySubtitle()
                        }
                        onSelectTrack(type, track.id)
                    }
                }
            }
        }
    }

    private func timingSection(
        title: LocalizedStringKey,
        systemName: String,
        value: TimeInterval,
        onEarlier: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) -> some View {
        inspectorSection(title, systemName: systemName) {
            HStack(spacing: 8) {
                Button("-0.5 s", action: onEarlier)
                Spacer()
                Text(String(format: "%+.1f s", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("+0.5 s", action: onLater)
            }
            .buttonStyle(VideoInspectorGlassButtonStyle())

            Button("Reset", action: onReset)
                .buttonStyle(VideoInspectorGlassButtonStyle())
        }
    }

    private var subtitleMaskEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoSubtitleMaskEnabled },
            set: { userConfig.videoSubtitleMaskEnabled = $0 }
        )
    }

    private var subtitleFontFamily: Binding<String> {
        Binding(
            get: { userConfig.videoSubtitleFontFamily },
            set: { userConfig.videoSubtitleFontFamily = $0 }
        )
    }

    private var subtitleFontSize: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleFontSize },
            set: { userConfig.videoSubtitleFontSize = $0 }
        )
    }

    private var subtitleFontWeight: Binding<Int> {
        Binding(
            get: { userConfig.videoSubtitleFontWeight },
            set: { userConfig.videoSubtitleFontWeight = $0 }
        )
    }

    private var subtitleShadowRadius: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleShadowRadius },
            set: { userConfig.videoSubtitleShadowRadius = $0 }
        )
    }

    private var subtitleBackgroundOpacity: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleBackgroundOpacity },
            set: { userConfig.videoSubtitleBackgroundOpacity = $0 }
        )
    }

    private var subtitleBackgroundDisabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoSubtitleBackgroundDisabled },
            set: { userConfig.videoSubtitleBackgroundDisabled = $0 }
        )
    }

    private var subtitleVerticalPosition: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleVerticalPosition },
            set: { userConfig.videoSubtitleVerticalPosition = $0 }
        )
    }

    private var subtitleColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleColor },
            set: { userConfig.videoSubtitleColor = $0 }
        )
    }

    private var subtitleLookupHighlightColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleLookupHighlightColor },
            set: { userConfig.videoSubtitleLookupHighlightColor = $0 }
        )
    }

    private var subtitleLookupHighlightTextColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleLookupHighlightTextColor },
            set: { userConfig.videoSubtitleLookupHighlightTextColor = $0 }
        )
    }

    private var subtitleMaskMode: Binding<VideoSubtitleMaskMode> {
        Binding(
            get: { userConfig.videoSubtitleMaskMode },
            set: { userConfig.videoSubtitleMaskMode = $0 }
        )
    }

    private var subtitleMaskBlurRadius: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleMaskBlurRadius },
            set: { userConfig.videoSubtitleMaskBlurRadius = $0 }
        )
    }

    private var subtitleMaskHiddenOpacity: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleMaskHiddenOpacity },
            set: { userConfig.videoSubtitleMaskHiddenOpacity = $0 }
        )
    }

    private var videoHardwareDecodingEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoHardwareDecodingEnabled },
            set: { userConfig.videoHardwareDecodingEnabled = $0 }
        )
    }

    private var videoDeinterlacingEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoDeinterlacingEnabled },
            set: { userConfig.videoDeinterlacingEnabled = $0 }
        )
    }

    private var videoHDREnhancementEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoHDREnhancementEnabled },
            set: { userConfig.videoHDREnhancementEnabled = $0 }
        )
    }

    private func videoEqualizerBinding(
        _ adjustment: VideoEqualizerAdjustment
    ) -> Binding<Double> {
        Binding(
            get: {
                switch adjustment {
                case .brightness: userConfig.videoBrightness
                case .contrast: userConfig.videoContrast
                case .saturation: userConfig.videoSaturation
                case .gamma: userConfig.videoGamma
                case .hue: userConfig.videoHue
                }
            },
            set: { value in
                let normalized = VideoEqualizerAdjustment.normalized(value)
                switch adjustment {
                case .brightness: userConfig.videoBrightness = normalized
                case .contrast: userConfig.videoContrast = normalized
                case .saturation: userConfig.videoSaturation = normalized
                case .gamma: userConfig.videoGamma = normalized
                case .hue: userConfig.videoHue = normalized
                }
            }
        )
    }

    private func videoEqualizerSlider(
        _ adjustment: VideoEqualizerAdjustment,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(LocalizedStringKey(adjustment.title), systemImage: adjustment.systemName)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            HStack(spacing: 8) {
                Slider(
                    value: value,
                    in: VideoEqualizerAdjustment.minimum...VideoEqualizerAdjustment.maximum,
                    step: 1
                )
                Button {
                    value.wrappedValue = VideoEqualizerAdjustment.neutral
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(VideoInspectorGlassButtonStyle(shape: .circle))
                .help("Reset")
            }
        }
    }

    private func subtitleAppearanceSlider(
        title: LocalizedStringKey,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: binding, in: range, step: step)
        }
    }

    private func inspectorSection<Content: View>(
        _ title: LocalizedStringKey,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(VideoInspectorSectionGlassSurface(cornerRadius: 18))
    }

    private func selectionRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(VideoInspectorSelectionRowGlassSurface(isSelected: isSelected, cornerRadius: 13))
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private static func speedLabel(_ speed: Double) -> String {
        VideoPlaybackSpeed.label(speed)
    }

    private var selectedPresetSpeed: Double {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(snapshot.speed)
        return speedChoices.first { abs($0 - normalizedSpeed) < 0.001 } ?? normalizedSpeed
    }

    private var sliderSpeed: Double {
        min(
            max(VideoPlaybackSpeed.normalized(snapshot.speed), VideoPlaybackSpeed.customInputLowerBound),
            VideoPlaybackSpeed.maximum
        )
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

    private var subtitleTimingMilliseconds: Int {
        Self.clampedSubtitleTimingMilliseconds(
            Int((snapshot.subtitleDelay * 1_000).rounded())
        )
    }

    private var subtitleTimingValueText: String {
        let milliseconds = subtitleTimingMilliseconds
        return "\(milliseconds >= 0 ? "+" : "")\(milliseconds) ms"
    }

    private func applySubtitleTimingMilliseconds(_ milliseconds: Int) {
        let clampedMilliseconds = Self.clampedSubtitleTimingMilliseconds(milliseconds)
        subtitleTimingInputText = "\(clampedMilliseconds)"
        onSetSubtitleDelay(TimeInterval(clampedMilliseconds) / 1_000)
    }

    private func synchronizeSubtitleTimingInput() {
        subtitleTimingInputText = "\(subtitleTimingMilliseconds)"
    }

    private func commitSubtitleTimingInput() {
        let normalizedText = subtitleTimingInputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let milliseconds = Int(normalizedText) else {
            synchronizeSubtitleTimingInput()
            return
        }
        applySubtitleTimingMilliseconds(milliseconds)
    }

    private static func clampedSubtitleTimingMilliseconds(_ milliseconds: Int) -> Int {
        min(
            max(milliseconds, Self.subtitleTimingMinimumMilliseconds),
            Self.subtitleTimingMaximumMilliseconds
        )
    }

    private static var subtitleFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}

private struct VideoInspectorGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

}

private struct VideoInspectorSectionGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                }
        }
    }
}

private struct VideoInspectorSelectionRowGlassSurface: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.7)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.58)
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                            }
                    }
                }
                .glassEffect(isSelected ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035))
                }
        }
    }
}

private struct VideoInspectorTextFieldGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 0.8)
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                }
        }
    }
}

private enum VideoInspectorGlassButtonShape {
    case capsule
    case circle
}

private struct VideoInspectorGlassButtonStyle: ButtonStyle {
    var shape: VideoInspectorGlassButtonShape = .capsule

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, shape == .circle ? 0 : 10)
            .padding(.vertical, shape == .circle ? 0 : 5)
            .foregroundStyle(configuration.isPressed ? .secondary : .primary)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
            .modifier(VideoInspectorGlassButtonSurface(shape: shape, isPressed: configuration.isPressed))
    }
}

private struct VideoInspectorGlassButtonSurface: ViewModifier {
    let shape: VideoInspectorGlassButtonShape
    let isPressed: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(isPressed ? 0.24 : 0.18), lineWidth: 0.7)
                        }
                }
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(
                    .thinMaterial,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                }
        }
    }
}
#endif
