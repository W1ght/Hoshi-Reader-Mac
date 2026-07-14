#if HOSHI_VIDEO
import AppKit
import Foundation
import SwiftUI

@MainActor
struct VideoPlaybackCommandContext {
    let snapshot: VideoPlaybackSnapshot
    let playlist: VideoPlaylist
    let currentURL: URL?
    let areSubtitlesVisible: Bool
    let primarySubtitleName: String?
    let canMineCurrentSubtitle: Bool

    var openVideo: @MainActor () -> Void
    var openRemoteLink: @MainActor () -> Void
    var playPause: @MainActor () -> Void
    var previousEpisode: @MainActor () -> Void
    var nextEpisode: @MainActor () -> Void
    var setSpeed: @MainActor (Double) -> Void
    var setAspectRatio: @MainActor (VideoAspectRatio) -> Void
    var rotateClockwise: @MainActor () -> Void
    var toggleFileLoop: @MainActor () -> Void
    var setABLoopStart: @MainActor () -> Void
    var setABLoopEnd: @MainActor () -> Void
    var clearABLoop: @MainActor () -> Void
    var selectTrack: @MainActor (VideoTrackType, Int?) -> Void
    var toggleMuted: @MainActor () -> Void
    var adjustVolume: @MainActor (Double) -> Void
    var adjustAudioDelay: @MainActor (TimeInterval) -> Void
    var resetAudioDelay: @MainActor () -> Void
    var openSubtitles: @MainActor () -> Void
    var clearPrimarySubtitle: @MainActor () -> Void
    var toggleSubtitlesVisible: @MainActor () -> Void
    var previousSubtitleCue: @MainActor () -> Void
    var nextSubtitleCue: @MainActor () -> Void
    var cycleSubtitleTrack: @MainActor () -> Void
    var adjustSubtitleDelay: @MainActor (TimeInterval) -> Void
    var resetSubtitleDelay: @MainActor () -> Void
    var openTranscript: @MainActor () -> Void
    var mineCurrentSubtitle: @MainActor () -> Void

    var hasVideo: Bool { currentURL != nil }
    var hasPreviousEpisode: Bool { playlist.previousURL != nil }
    var hasNextEpisode: Bool { playlist.nextURL != nil }

    func tracks(_ type: VideoTrackType) -> [VideoTrack] {
        snapshot.tracks.filter { $0.type == type }
    }

    func isTrackSelected(_ type: VideoTrackType, id: Int?) -> Bool {
        let tracks = tracks(type)
        if let id {
            return tracks.first { $0.id == id }?.isSelected == true
        }
        return !tracks.contains(where: \.isSelected)
            && (type != .subtitle || primarySubtitleName == nil)
    }
}

private struct VideoPlaybackCommandContextKey: FocusedValueKey {
    typealias Value = VideoPlaybackCommandContext
}

extension FocusedValues {
    var videoPlaybackCommandContext: VideoPlaybackCommandContext? {
        get { self[VideoPlaybackCommandContextKey.self] }
        set { self[VideoPlaybackCommandContextKey.self] = newValue }
    }
}

struct VideoPlaybackCommands: Commands {
    @FocusedValue(\.videoPlaybackCommandContext) private var context

    private static let speedChoices = VideoPlaybackSpeed.presetChoices

    var body: some Commands {
        CommandMenu("Video") {
            videoMenu
        }
        CommandMenu("Audio") {
            audioMenu
        }
        CommandMenu("Subtitles") {
            subtitlesMenu
        }
    }

    @ViewBuilder
    private var videoMenu: some View {
        Button("Open Video") { run { $0.openVideo() } }
        Button("Open Link") { run { $0.openRemoteLink() } }

        Divider()

        Button("Play/Pause") { run { $0.playPause() } }
            .disabled(context?.hasVideo != true)
        Button("Previous Episode") { run { $0.previousEpisode() } }
            .disabled(context?.hasPreviousEpisode != true)
        Button("Next Episode") { run { $0.nextEpisode() } }
            .disabled(context?.hasNextEpisode != true)

        Divider()

        Menu("Playback Speed") {
            ForEach(Self.speedChoices, id: \.self) { speed in
                Button {
                    run { $0.setSpeed(speed) }
                } label: {
                    selectionLabel(
                        verbatim: Self.speedLabel(speed),
                        isSelected: isSpeedSelected(speed)
                    )
                }
            }
        }
        .disabled(context?.hasVideo != true)

        Menu("Video Track") {
            trackItems(type: .video, allowsOff: false)
        }
        .disabled(context?.hasVideo != true)

        Menu("Aspect Ratio") {
            ForEach(VideoAspectRatio.allCases, id: \.self) { aspectRatio in
                Button {
                    run { $0.setAspectRatio(aspectRatio) }
                } label: {
                    selectionLabel(
                        verbatim: aspectRatio.title,
                        isSelected: context?.snapshot.aspectRatio == aspectRatio
                    )
                }
            }
        }
        .disabled(context?.hasVideo != true)

        Button("Rotate Clockwise") { run { $0.rotateClockwise() } }
            .disabled(context?.hasVideo != true)

        Divider()

        Button {
            run { $0.toggleFileLoop() }
        } label: {
            selectionLabel("Loop File", isSelected: context?.snapshot.loopMode == .file)
        }
        .disabled(context?.hasVideo != true)

        Button("Set A Point") { run { $0.setABLoopStart() } }
            .disabled(context?.hasVideo != true)
        Button("Set B Point") { run { $0.setABLoopEnd() } }
            .disabled(context?.hasVideo != true)
        Button("Clear A-B Loop") { run { $0.clearABLoop() } }
            .disabled(context?.snapshot.abLoop == nil)
    }

    @ViewBuilder
    private var audioMenu: some View {
        Menu("Audio Track") {
            trackItems(type: .audio, allowsOff: true)
        }
        .disabled(context?.hasVideo != true)

        Divider()

        Button {
            run { $0.toggleMuted() }
        } label: {
            selectionLabel("Mute / Unmute", isSelected: context?.snapshot.isMuted == true)
        }
        .disabled(context?.hasVideo != true)

        Button("Volume Up") { run { $0.adjustVolume(5) } }
            .disabled(context?.hasVideo != true)
        Button("Volume Down") { run { $0.adjustVolume(-5) } }
            .disabled(context?.hasVideo != true)

        Divider()

        Button("Audio Earlier") { run { $0.adjustAudioDelay(-0.5) } }
            .disabled(context?.hasVideo != true)
        Button("Audio Later") { run { $0.adjustAudioDelay(0.5) } }
            .disabled(context?.hasVideo != true)
        Button("Reset Audio Timing") { run { $0.resetAudioDelay() } }
            .disabled(context?.hasVideo != true)
    }

    @ViewBuilder
    private var subtitlesMenu: some View {
        Button {
            run { $0.toggleSubtitlesVisible() }
        } label: {
            selectionLabel(
                "Show / Hide Subtitles",
                isSelected: context?.areSubtitlesVisible == true
            )
        }
        .disabled(context?.hasVideo != true)

        Button("Open Subtitles") { run { $0.openSubtitles() } }
            .disabled(context?.hasVideo != true)

        Menu("Subtitle Track") {
            subtitleTrackItems
        }
        .disabled(context?.hasVideo != true)

        Divider()

        Button("Previous Subtitle") { run { $0.previousSubtitleCue() } }
            .disabled(context?.hasVideo != true)
        Button("Next Subtitle") { run { $0.nextSubtitleCue() } }
            .disabled(context?.hasVideo != true)
        Button("Cycle Subtitle Track") { run { $0.cycleSubtitleTrack() } }
            .disabled(context?.hasVideo != true)

        Divider()

        Button("Subtitle Earlier") { run { $0.adjustSubtitleDelay(-0.05) } }
            .disabled(context?.hasVideo != true)
        Button("Subtitle Later") { run { $0.adjustSubtitleDelay(0.05) } }
            .disabled(context?.hasVideo != true)
        Button("Reset Subtitle Timing") { run { $0.resetSubtitleDelay() } }
            .disabled(context?.hasVideo != true)

        Divider()

        Button("Open Transcript") { run { $0.openTranscript() } }
            .disabled(context?.hasVideo != true)
        Button("Mine Current Subtitle") { run { $0.mineCurrentSubtitle() } }
            .disabled(context?.canMineCurrentSubtitle != true)
    }

    @ViewBuilder
    private var subtitleTrackItems: some View {
        Button {
            run { $0.clearPrimarySubtitle() }
        } label: {
            selectionLabel(
                "Off",
                isSelected: context?.isTrackSelected(.subtitle, id: nil) == true
            )
        }

        if let primarySubtitleName = context?.primarySubtitleName {
            Button {
                run { $0.clearPrimarySubtitle() }
            } label: {
                selectionLabel(verbatim: primarySubtitleName, isSelected: true)
            }
            Divider()
        }

        trackItems(type: .subtitle, allowsOff: false)
    }

    @ViewBuilder
    private func trackItems(type: VideoTrackType, allowsOff: Bool) -> some View {
        if allowsOff {
            Button {
                run { $0.selectTrack(type, nil) }
            } label: {
                selectionLabel(
                    "Off",
                    isSelected: context?.isTrackSelected(type, id: nil) == true
                )
            }
        }

        let tracks = context?.tracks(type) ?? []
        if tracks.isEmpty {
            Text("No tracks")
        } else {
            ForEach(tracks) { track in
                Button {
                    run { $0.selectTrack(type, track.id) }
                } label: {
                    selectionLabel(verbatim: track.displayName, isSelected: track.isSelected)
                }
            }
        }
    }

    private func run(_ action: @MainActor (VideoPlaybackCommandContext) -> Void) {
        guard let context else { return }
        action(context)
    }

    private func isSpeedSelected(_ speed: Double) -> Bool {
        guard let currentSpeed = context?.snapshot.speed else { return false }
        return abs(currentSpeed - speed) < 0.001
    }

    @ViewBuilder
    private func selectionLabel(
        _ title: LocalizedStringKey,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func selectionLabel(
        verbatim title: String,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else {
            Text(verbatim: title)
        }
    }

    private static func speedLabel(_ speed: Double) -> String {
        VideoPlaybackSpeed.label(speed)
    }
}

@MainActor
final class VideoPlaybackMenuVisibilityController: NSObject {
    static let shared = VideoPlaybackMenuVisibilityController()

    private let visibleTitles: Set<String> = [
        String(localized: "Video"),
        String(localized: "Audio"),
        String(localized: "Subtitles"),
        "Video",
        "Audio",
        "Subtitles",
        "视频",
        "音频",
        "字幕",
        "影片",
        "音訊",
    ]

    private var isObserving = false

    func install() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyWindowDidChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyWindowDidChange(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        scheduleSync()
    }

    @objc private func keyWindowDidChange(_ notification: Notification) {
        scheduleSync()
    }

    private func scheduleSync(retries: Int = 4) {
        sync()
        guard retries > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            scheduleSync(retries: retries - 1)
        }
    }

    private func sync() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let shouldShow = isVideoPlaybackWindow(currentAppKitWindow)
        for item in mainMenu.items where visibleTitles.contains(item.title) {
            item.isHidden = !shouldShow
        }
    }

    private var currentAppKitWindow: NSWindow? {
        NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { window in
                window.isKeyWindow || window.isMainWindow
            }
    }

    private func isVideoPlaybackWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.identifier?.rawValue == VideoWindowCoordinator.windowID
    }
}
#endif
