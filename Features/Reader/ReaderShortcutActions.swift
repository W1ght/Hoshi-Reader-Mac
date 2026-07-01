import Foundation

enum ReaderShortcutActions {
    static let previousPage = ShortcutAction(
        id: "reader.previousPage",
        titleKey: "Previous Page",
        category: .reader,
        scopes: [.reader],
        defaultBinding: .leftArrow
    )

    static let nextPage = ShortcutAction(
        id: "reader.nextPage",
        titleKey: "Next Page",
        category: .reader,
        scopes: [.reader],
        defaultBinding: .rightArrow
    )

    static let close = ShortcutAction(
        id: "reader.close",
        titleKey: "Close Reader",
        category: .reader,
        scopes: [.reader],
        defaultBinding: .escape
    )

    static let toggleFocusMode = ShortcutAction(
        id: "reader.toggleFocusMode",
        titleKey: "Toggle Focus Mode",
        category: .reader,
        scopes: [.reader],
        defaultBinding: KeyboardShortcutBinding(key: "f")
    )

    static let toggleStatistics = ShortcutAction(
        id: "reader.toggleStatistics",
        titleKey: "Toggle Reading Timer",
        category: .reader,
        scopes: [.reader],
        defaultBinding: KeyboardShortcutBinding(key: "t")
    )

    static let toggleLyricsMode = ShortcutAction(
        id: "reader.toggleLyricsMode",
        titleKey: "Lyrics Mode",
        category: .reader,
        scopes: [.reader],
        defaultBinding: KeyboardShortcutBinding(key: "l")
    )

    static let all = [previousPage, nextPage, close, toggleFocusMode, toggleStatistics, toggleLyricsMode]
}
