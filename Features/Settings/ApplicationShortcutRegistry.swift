import SwiftUI

enum GlobalShortcutActions {
    static let open = ShortcutAction(
        id: "global.open",
        titleKey: "Open",
        category: .global,
        scopes: [.global],
        defaultBinding: KeyboardShortcutBinding(
            key: "o",
            modifiers: EventModifiers.command.rawValue
        )
    )

    static let all = [open]
}

extension ShortcutRegistry {
    static var application: ShortcutRegistry {
        var actions =
            GlobalShortcutActions.all
            + ReaderShortcutActions.all
            + DictionaryShortcutActions.all
            + PopupShortcutActions.all
            + SasayakiShortcutActions.all
#if HOSHI_VIDEO
        actions += VideoShortcutActions.all
#endif
        return ShortcutRegistry(actions: actions)
    }
}
