import Foundation

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    if !haystack.contains(needle) {
        fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
        exit(1)
    }
}

func assertOccurrenceCountAtLeast(
    _ haystack: String,
    _ needle: String,
    _ minimum: Int,
    _ message: String
) {
    let count = haystack.components(separatedBy: needle).count - 1
    if count < minimum {
        fputs("FAIL: \(message)\nExpected at least \(minimum), found \(count): \(needle)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        fputs("FAIL: Could not read \(path): \(error)\n", stderr)
        exit(1)
    }
}

let dictionarySearchView = read("Features/Dictionary/DictionarySearchView.swift")
let popupView = read("Features/Popup/PopupView.swift")
let popupWebView = read("Features/Popup/PopupWebView.swift")

assertContains(
    dictionarySearchView,
    "@Environment(ShortcutManager.self)",
    "Dictionary search page must use the shared shortcut manager"
)
assertContains(
    dictionarySearchView,
    "shortcutManager.register(\n            scope: .dictionary",
    "Dictionary search page must register dictionary entry navigation handlers"
)
assertContains(
    dictionarySearchView,
    "DictionaryShortcutActions.previousEntry.id",
    "Dictionary search page must handle the previous-entry shortcut action"
)
assertContains(
    dictionarySearchView,
    "DictionaryShortcutActions.nextEntry.id",
    "Dictionary search page must handle the next-entry shortcut action"
)

assertContains(
    popupView,
    "@Environment(ShortcutManager.self)",
    "Reader/native popup must use the shared shortcut manager"
)
assertContains(
    popupView,
    "shortcutManager.register(\n            scope: .dictionary",
    "Reader/native popup must register dictionary entry navigation handlers"
)
assertContains(
    popupView,
    "DictionaryShortcutActions.previousEntry.id",
    "Reader/native popup must handle the previous-entry shortcut action"
)
assertContains(
    popupView,
    "DictionaryShortcutActions.nextEntry.id",
    "Reader/native popup must handle the next-entry shortcut action"
)

assertContains(
    popupWebView,
    "struct DictionaryEntryNavigationCommand",
    "PopupWebView must expose a command value for dictionary entry navigation"
)
assertContains(
    popupWebView,
    "dictionaryEntryNavigationCommand",
    "PopupWebView must accept dictionary entry navigation commands from SwiftUI state"
)
assertContains(
    popupWebView,
    "window.hoshiMoveDictionaryEntry(\\(command.direction), \\(command.count))",
    "PopupWebView must route shortcut commands to the existing JS entry navigation function"
)
assertOccurrenceCountAtLeast(
    popupWebView,
    "window.hoshiResetDictionaryEntryFocus?.();",
    1,
    "PopupWebView should keep resetting entry focus after rendering dictionary entries"
)

print("Dictionary entry navigation shortcut contract passed.")
