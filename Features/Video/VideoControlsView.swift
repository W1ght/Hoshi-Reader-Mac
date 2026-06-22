#if HOSHI_VIDEO
import SwiftUI

struct VideoControlsView: View {
    let snapshot: VideoPlaybackSnapshot
    let playlist: VideoPlaylist
    let profiles: [HoshiProfile]
    let selectedProfileID: String
    let canMineCurrentSubtitle: Bool
    var onTogglePlayback: () -> Void
    var onSeek: (TimeInterval) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onSetVolume: (Double) -> Void
    var onToggleMuted: () -> Void
    var onSelectProfile: (String) -> Void
    var onToggleMiningHistory: () -> Void
    var onOpenVideo: () -> Void
    var onMineCurrentSubtitle: () -> Void
    var onToggleInspector: () -> Void
    var onToggleFullScreen: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: (CGSize) -> Void

    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        controls
            .modifier(VideoFloatingGlassSurface())
    }

    private var controls: some View {
        VStack(spacing: 7) {
            primaryControlGroup
            progressControlStrip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            controlDragSurface
        }
        .frame(width: 760)
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
            Button(action: onToggleMiningHistory) {
                Label("Mining History", systemImage: "clock.arrow.circlepath")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Mining History")

            Button(action: onOpenVideo) {
                Label("Open Video", systemImage: "film")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Open Video")

            profileMenu

            volumeControl
                .frame(width: 112, alignment: .leading)

            Spacer(minLength: 0)

            episodeControls

            Spacer(minLength: 0)

            Button(action: onMineCurrentSubtitle) {
                Label("Mine Current Subtitle", systemImage: "tray.and.arrow.down")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .disabled(!canMineCurrentSubtitle)
            .help("Mine Current Subtitle")

            Button(action: onToggleInspector) {
                Label("Inspector", systemImage: "sidebar.trailing")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Inspector")

            Button(action: onToggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Toggle Full Screen")
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(profiles) { profile in
                Button {
                    onSelectProfile(profile.id)
                } label: {
                    Label(
                        profile.displayName,
                        systemImage: profile.id == selectedProfileID
                            ? "checkmark"
                            : "person.crop.circle"
                    )
                }
            }
        } label: {
            Label(selectedProfile.displayName, systemImage: "person.crop.circle")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 132, alignment: .leading)
        .help("Video Profile")
    }

    private var progressControlStrip: some View {
        HStack(spacing: 8) {
            Text(VideoTimeFormatter.string(from: isScrubbing ? scrubTime : snapshot.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            progressSlider
                .frame(width: 330)

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

    private var progressSlider: some View {
        Slider(
            value: Binding(
                get: { isScrubbing ? scrubTime : snapshot.currentTime },
                set: { scrubTime = $0 }
            ),
            in: 0...max(snapshot.duration, 0.01),
            onEditingChanged: { editing in
                isScrubbing = editing
                if editing {
                    scrubTime = snapshot.currentTime
                } else {
                    onSeek(scrubTime)
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

    private var remainingTimeText: String {
        let activeTime = isScrubbing ? scrubTime : snapshot.currentTime
        let remaining = max(snapshot.duration - activeTime, 0)
        return "-" + VideoTimeFormatter.string(from: remaining)
    }

    private var selectedProfile: HoshiProfile {
        profiles.first(where: { $0.id == selectedProfileID })
            ?? profiles.first
            ?? .defaultJapaneseVideo
    }

}

private struct VideoFloatingGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
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

private struct VideoPlaybackButtonStyle: ButtonStyle {
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
                .background(.ultraThinMaterial, in: Circle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
        }
    }
}
#endif
