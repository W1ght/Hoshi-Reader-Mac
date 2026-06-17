#if HOSHI_VIDEO
import SwiftUI

struct VideoControlsView: View {
    let snapshot: VideoPlaybackSnapshot
    let playlist: VideoPlaylist
    var onTogglePlayback: () -> Void
    var onSeek: (TimeInterval) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onSetVolume: (Double) -> Void
    var onToggleMuted: () -> Void
    var onToggleInspector: () -> Void
    var onToggleFullScreen: () -> Void

    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        controls
            .modifier(VideoFloatingGlassSurface())
    }

    private var controls: some View {
        primaryControlGroup
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: 960)
    }

    private var primaryControlGroup: some View {
        HStack(spacing: 12) {
            episodeControls

            Text(VideoTimeFormatter.string(from: isScrubbing ? scrubTime : snapshot.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .trailing)

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

            Text(VideoTimeFormatter.string(from: snapshot.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)

            volumeControl

            Button(action: onToggleInspector) {
                Label("Inspector", systemImage: "sidebar.trailing")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Inspector")

            Button(action: onToggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .help("Toggle Full Screen")
        }
    }

    private var episodeControls: some View {
        HStack(spacing: 6) {
            Button(action: onPrevious) {
                Image(systemName: "backward.end.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .disabled(playlist.previousURL == nil)
            .help("Previous Episode")

            Button(action: onTogglePlayback) {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(VideoPlaybackButtonStyle())
            .help(snapshot.isPlaying ? "Pause" : "Play")

            Button(action: onNext) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VideoGlassIconButtonStyle())
            .disabled(playlist.nextURL == nil)
            .help("Next Episode")
        }
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
            .frame(width: 86)
        }
    }

}

private struct VideoFloatingGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content
                    .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
            }
        } else {
            content
                .background(
                    .thinMaterial,
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
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
