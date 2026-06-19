#if HOSHI_VIDEO
import AppKit
import SwiftUI

enum VideoInspectorTab: String, CaseIterable, Identifiable {
    case episodes
    case video
    case audio
    case subtitles
    case transcript

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .episodes: "Episodes"
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .transcript: "Transcript"
        }
    }

    var systemName: String {
        switch self {
        case .episodes: "list.number"
        case .video: "film"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        case .transcript: "text.alignleft"
        }
    }
}

struct VideoInspectorView: View {
    @Environment(UserConfig.self) private var userConfig
    @Binding var selectedTab: VideoInspectorTab

    let snapshot: VideoPlaybackSnapshot
    let playlist: VideoPlaylist
    let currentURL: URL?
    let primarySubtitleName: String?
    let transcript: SubtitleTranscript

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
    var onSeekToChapter: (Int) -> Void
    var onSelectTrack: (VideoTrackType, Int?) -> Void
    var onOpenSubtitle: () -> Void
    var onClearPrimarySubtitle: () -> Void
    var onSeekTranscript: (TimeInterval) -> Void
    var onClose: () -> Void

    private let speedChoices = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private let speedRows = [
        [0.5, 0.75, 1],
        [1.25, 1.5, 1.75],
        [2, 2.5, 3],
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker

            Divider()
                .opacity(0.5)

            if selectedTab == .transcript {
                tabContent
                    .padding(12)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    tabContent
                        .padding(12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        .modifier(VideoInspectorGlassSurface(cornerRadius: 24))
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
        case .transcript:
            SubtitleTranscriptView(
                transcript: transcript,
                currentTime: snapshot.currentTime,
                onSeek: onSeekTranscript,
                onClose: onClose
            )
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
                            get: { speedChoices.min(by: { abs($0 - snapshot.speed) < abs($1 - snapshot.speed) }) ?? 1 },
                            set: { onSetSpeed($0) }
                        ),
                        values: row,
                        minSegmentWidth: 54,
                        fillsWidth: true
                    ) { speed in
                        Text(Self.speedLabel(speed))
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            trackSection(
                title: "Video Track",
                systemName: "film",
                type: .video,
                allowsOff: false
            )

            if !snapshot.chapters.isEmpty {
                inspectorSection("Chapters", systemName: "list.bullet.rectangle") {
                    ForEach(snapshot.chapters) { chapter in
                        selectionRow(
                            title: chapter.title,
                            subtitle: VideoTimeFormatter.string(from: chapter.startTime),
                            isSelected: false
                        ) {
                            onSeekToChapter(chapter.id)
                        }
                    }
                }
            }

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

            timingSection(
                title: "Subtitle Timing",
                systemName: "captions.bubble",
                value: snapshot.subtitleDelay,
                onEarlier: { onSetSubtitleDelay(max(snapshot.subtitleDelay - 0.5, -30)) },
                onReset: { onSetSubtitleDelay(0) },
                onLater: { onSetSubtitleDelay(min(snapshot.subtitleDelay + 0.5, 30)) }
            )

            subtitleAppearanceSection

            subtitleMaskSection

            inspectorSection("Transcript", systemName: "text.alignleft") {
                Button {
                    selectedTab = .transcript
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
        String(format: speed == speed.rounded() ? "%.0fx" : "%.2gx", speed)
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
