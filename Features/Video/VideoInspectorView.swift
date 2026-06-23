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
    @Environment(UserConfig.self) private var userConfig
    @Binding var selectedTab: VideoInspectorTab

    let snapshot: VideoInspectorSnapshot
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

    private let speedChoices = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private let speedRows = [
        [0.5, 0.75, 1],
        [1.25, 1.5, 1.75],
        [2, 2.5, 3],
    ]

    var body: some View {
        VideoTranslucentSurface(
            liquidGlassCornerRadius: 12,
            visualEffectCornerRadius: 0
        ) {
            VStack(spacing: 0) {
                header
                tabPicker

                Divider()

                ScrollView {
                    tabContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .scrollIndicators(.automatic)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .controlSize(.small)
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        .frame(maxHeight: .infinity)
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
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        Picker("Inspector", selection: $selectedTab) {
            ForEach(VideoInspectorTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemName)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
                    Picker("Playback Speed", selection: Binding<Double>(
                            get: { speedChoices.min(by: { abs($0 - snapshot.speed) < abs($1 - snapshot.speed) }) ?? 1 },
                            set: { onSetSpeed($0) }
                        )) {
                        ForEach(row, id: \.self) { speed in
                            Text(Self.speedLabel(speed)).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            trackSection(
                title: "Video Track",
                systemName: "film",
                type: .video,
                allowsOff: false
            )

            inspectorSection("Aspect Ratio", systemName: "rectangle.inset.filled") {
                Picker("Aspect Ratio", selection: Binding<VideoAspectRatio>(
                        get: { snapshot.aspectRatio },
                        set: { onSetAspectRatio($0) }
                    )) {
                    ForEach(VideoAspectRatio.allCases, id: \.self) { aspectRatio in
                        Text(aspectRatio.title).tag(aspectRatio)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button {
                    onRotateClockwise()
                } label: {
                    Label("Rotate Clockwise", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            inspectorSection("Loop", systemName: "repeat") {
                Picker("Loop", selection: Binding<Bool>(
                        get: { snapshot.loopMode == .file },
                        set: { onSetLoopMode($0 ? .file : .none) }
                    )) {
                    Text("Off").tag(false)
                    Text("Loop File").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Button("Set A Point", action: onSetABLoopStart)
                    Button("Set B Point", action: onSetABLoopEnd)
                    Button("Clear", action: onClearABLoop)
                        .disabled(snapshot.abLoop == nil)
                }
                .buttonStyle(.bordered)
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
                .buttonStyle(.bordered)

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
                    onOpenTranscript()
                } label: {
                    Label("Open Transcript", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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

                ColorPicker("Subtitle Color", selection: subtitleColor)
                    .font(.caption)

                ColorPicker("Lookup Highlight Color", selection: subtitleLookupHighlightColor)
                    .font(.caption)
            }
        }
    }

    private var subtitleMaskSection: some View {
        inspectorSection("Subtitle Mask", systemName: "eye.slash") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Mask subtitles until hover", isOn: subtitleMaskEnabled)
                    .toggleStyle(.switch)

                Picker("Mask Mode", selection: subtitleMaskMode) {
                    ForEach(VideoSubtitleMaskMode.allCases, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
            .buttonStyle(.bordered)

            Button("Reset", action: onReset)
                .buttonStyle(.bordered)
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
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Divider()
        }
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
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
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
#endif
