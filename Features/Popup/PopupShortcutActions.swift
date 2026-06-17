import Foundation

enum PopupShortcutActions {
    static let dismiss = ShortcutAction(
        id: "popup.dismiss",
        titleKey: "Close Popup",
        category: .dictionaryPopup,
        scopes: [.popup],
        defaultBinding: .escape
    )

    static let all = [dismiss]
}
