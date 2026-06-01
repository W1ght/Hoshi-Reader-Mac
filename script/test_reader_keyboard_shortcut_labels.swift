import Foundation

struct ReaderKeyboardShortcut: Equatable {
    struct Modifiers: OptionSet {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 3)
        static let control = Modifiers(rawValue: 1 << 2)
    }

    var key: String
    var modifiers: Modifiers = []

    var label: String {
        let modifierLabels: [(Modifiers, String)] = [
            (.command, "⌘"),
            (.shift, "⇧"),
            (.option, "⌥"),
            (.control, "⌃")
        ]
        let prefix = modifierLabels
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return prefix + keyLabel
    }

    private var keyLabel: String {
        switch key {
        case "leftArrow": "←"
        case "rightArrow": "→"
        case "upArrow": "↑"
        case "downArrow": "↓"
        case "pageUp": "Page Up"
        case "pageDown": "Page Down"
        case "space": "Space"
        default: key.uppercased()
        }
    }
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

assertEqual(ReaderKeyboardShortcut(key: "leftArrow").label, "←", "left arrow label")
assertEqual(ReaderKeyboardShortcut(key: "rightArrow").label, "→", "right arrow label")
assertEqual(ReaderKeyboardShortcut(key: "pageUp").label, "Page Up", "page up label")
assertEqual(ReaderKeyboardShortcut(key: "pageDown").label, "Page Down", "page down label")
assertEqual(ReaderKeyboardShortcut(key: "space").label, "Space", "space label")
assertEqual(ReaderKeyboardShortcut(key: "[").label, "[", "punctuation label")
assertEqual(ReaderKeyboardShortcut(key: "j").label, "J", "letter label")
assertEqual(
    ReaderKeyboardShortcut(key: "r", modifiers: [.command, .shift, .option, .control]).label,
    "⌘⇧⌥⌃R",
    "modifier order"
)

print("ReaderKeyboardShortcut label tests passed")
