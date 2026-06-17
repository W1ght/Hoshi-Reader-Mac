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

    static let all = [previousPage, nextPage, close, toggleFocusMode]
}
