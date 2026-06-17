import Foundation

enum SasayakiShortcutActions {
    static let previousCue = ShortcutAction(
        id: "sasayaki.previousCue",
        titleKey: "Previous Cue",
        category: .sasayaki,
        scopes: [.sasayaki],
        defaultBinding: .bracketLeft
    )

    static let playPause = ShortcutAction(
        id: "sasayaki.playPause",
        titleKey: "Play/Pause",
        category: .sasayaki,
        scopes: [.sasayaki],
        defaultBinding: .p
    )

    static let nextCue = ShortcutAction(
        id: "sasayaki.nextCue",
        titleKey: "Next Cue",
        category: .sasayaki,
        scopes: [.sasayaki],
        defaultBinding: .bracketRight
    )

    static let replayCue = ShortcutAction(
        id: "sasayaki.replayCue",
        titleKey: "Replay Cue",
        category: .sasayaki,
        scopes: [.sasayaki],
        defaultBinding: .r
    )

    static let jumpCue = ShortcutAction(
        id: "sasayaki.jumpCue",
        titleKey: "Jump Cue",
        category: .sasayaki,
        scopes: [.sasayaki],
        defaultBinding: .j
    )

    static let all = [previousCue, playPause, nextCue, replayCue, jumpCue]
}
