#if HOSHI_VIDEO
import SwiftUI

enum VideoShortcutActions {
    static let playPause = ShortcutAction(
        id: "video.playPause",
        titleKey: "Play/Pause",
        category: .video,
        scopes: [.video],
        defaultBinding: .space
    )

    static let seekBackward = ShortcutAction(
        id: "video.seekBackward",
        titleKey: "Seek Backward",
        category: .video,
        scopes: [.video],
        defaultBinding: .leftArrow
    )

    static let seekForward = ShortcutAction(
        id: "video.seekForward",
        titleKey: "Seek Forward",
        category: .video,
        scopes: [.video],
        defaultBinding: .rightArrow
    )

    static let previousEpisode = ShortcutAction(
        id: "video.previousEpisode",
        titleKey: "Previous Episode",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "leftArrow",
            modifiers: EventModifiers.command.rawValue
                | EventModifiers.shift.rawValue
        )
    )

    static let nextEpisode = ShortcutAction(
        id: "video.nextEpisode",
        titleKey: "Next Episode",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "rightArrow",
            modifiers: EventModifiers.command.rawValue
                | EventModifiers.shift.rawValue
        )
    )

    static let decreaseSpeed = ShortcutAction(
        id: "video.decreaseSpeed",
        titleKey: "Decrease Playback Speed",
        category: .video,
        scopes: [.video],
        defaultBinding: .bracketLeft
    )

    static let increaseSpeed = ShortcutAction(
        id: "video.increaseSpeed",
        titleKey: "Increase Playback Speed",
        category: .video,
        scopes: [.video],
        defaultBinding: .bracketRight
    )

    static let resetSpeed = ShortcutAction(
        id: "video.resetSpeed",
        titleKey: "Reset Playback Speed",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "\\")
    )

    static let toggleMute = ShortcutAction(
        id: "video.toggleMute",
        titleKey: "Mute / Unmute",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "m")
    )

    static let volumeDown = ShortcutAction(
        id: "video.volumeDown",
        titleKey: "Volume Down",
        category: .video,
        scopes: [.video],
        defaultBinding: .downArrow
    )

    static let volumeUp = ShortcutAction(
        id: "video.volumeUp",
        titleKey: "Volume Up",
        category: .video,
        scopes: [.video],
        defaultBinding: .upArrow
    )

    static let previousSubtitleCue = ShortcutAction(
        id: "video.previousSubtitleCue",
        titleKey: "Previous Subtitle",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "leftArrow",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let nextSubtitleCue = ShortcutAction(
        id: "video.nextSubtitleCue",
        titleKey: "Next Subtitle",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "rightArrow",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let toggleSubtitlesVisible = ShortcutAction(
        id: "video.toggleSubtitlesVisible",
        titleKey: "Show / Hide Subtitles",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "v")
    )

    static let cycleSubtitleTrack = ShortcutAction(
        id: "video.cycleSubtitleTrack",
        titleKey: "Cycle Subtitle Track",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "s")
    )

    static let subtitleEarlier = ShortcutAction(
        id: "video.subtitleEarlier",
        titleKey: "Subtitle Earlier",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: ",",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let subtitleLater = ShortcutAction(
        id: "video.subtitleLater",
        titleKey: "Subtitle Later",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: ".",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let resetSubtitleTiming = ShortcutAction(
        id: "video.resetSubtitleTiming",
        titleKey: "Reset Subtitle Timing",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "/",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let audioEarlier = ShortcutAction(
        id: "video.audioEarlier",
        titleKey: "Audio Earlier",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: ",",
            modifiers: EventModifiers.option.rawValue
                | EventModifiers.shift.rawValue
        )
    )

    static let audioLater = ShortcutAction(
        id: "video.audioLater",
        titleKey: "Audio Later",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: ".",
            modifiers: EventModifiers.option.rawValue
                | EventModifiers.shift.rawValue
        )
    )

    static let toggleFileLoop = ShortcutAction(
        id: "video.toggleFileLoop",
        titleKey: "Toggle File Loop",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "l")
    )

    static let setABLoopStart = ShortcutAction(
        id: "video.setABLoopStart",
        titleKey: "Set A-B Loop Start",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "a",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let setABLoopEnd = ShortcutAction(
        id: "video.setABLoopEnd",
        titleKey: "Set A-B Loop End",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "b",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let toggleTranscript = ShortcutAction(
        id: "video.toggleTranscript",
        titleKey: "Toggle Transcript",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "t")
    )

    static let rotateClockwise = ShortcutAction(
        id: "video.rotateClockwise",
        titleKey: "Rotate Clockwise",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(key: "r")
    )

    static let toggleFullScreen = ShortcutAction(
        id: "video.toggleFullScreen",
        titleKey: "Toggle Full Screen",
        category: .video,
        scopes: [.video],
        defaultBinding: KeyboardShortcutBinding(
            key: "f",
            modifiers: EventModifiers.command.rawValue
                | EventModifiers.control.rawValue
        )
    )

    static let exitFocusMode = ShortcutAction(
        id: "video.exitFocusMode",
        titleKey: "Exit Full Screen or Focus Mode",
        category: .video,
        scopes: [.video],
        defaultBinding: .escape
    )

    static let all = [
        playPause,
        seekBackward,
        seekForward,
        previousEpisode,
        nextEpisode,
        decreaseSpeed,
        increaseSpeed,
        resetSpeed,
        toggleMute,
        volumeDown,
        volumeUp,
        previousSubtitleCue,
        nextSubtitleCue,
        toggleSubtitlesVisible,
        cycleSubtitleTrack,
        subtitleEarlier,
        subtitleLater,
        resetSubtitleTiming,
        audioEarlier,
        audioLater,
        toggleFileLoop,
        setABLoopStart,
        setABLoopEnd,
        toggleTranscript,
        rotateClockwise,
        toggleFullScreen,
        exitFocusMode
    ]
}
#endif
