import SwiftUI

enum DictionaryShortcutActions {
    static let previousEntry = ShortcutAction(
        id: "dictionary.previousEntry",
        titleKey: "Previous Entry",
        category: .dictionaryPopup,
        scopes: [.dictionary],
        defaultBinding: KeyboardShortcutBinding(
            key: "pageUp",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let nextEntry = ShortcutAction(
        id: "dictionary.nextEntry",
        titleKey: "Next Entry",
        category: .dictionaryPopup,
        scopes: [.dictionary],
        defaultBinding: KeyboardShortcutBinding(
            key: "pageDown",
            modifiers: EventModifiers.option.rawValue
        )
    )

    static let all = [previousEntry, nextEntry]
}
