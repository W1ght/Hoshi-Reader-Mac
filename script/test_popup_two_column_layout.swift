import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let profile = try source("Models/Profile.swift")
let userConfig = try source("Core/UserConfig.swift")
let dictionarySettings = try source("Features/Settings/DictionaryView.swift")
let appearanceSettings = try source("Features/Settings/AppearanceView.swift")
let popupView = try source("Features/Popup/PopupView.swift")
let dictionarySearch = try source("Features/Dictionary/DictionarySearchView.swift")
let popupScript = try source("Features/Popup/popup.js")
let popupStyles = try source("Features/Popup/popup.css")
let dictionariesCatalog = try source("Dictionaries.xcstrings")
let changelog = try source("docs/CHANGELOG.md")

require(
    profile.contains("var twoColumnLayout: Bool? = nil")
        && profile.contains("twoColumnLayout: false"),
    "dictionary profiles should decode the new preference compatibly and default it off"
)
require(
    userConfig.contains("var twoColumnLayout: Bool {")
        && userConfig.contains("Self.defaults.set(twoColumnLayout, forKey: \"twoColumnLayout\")")
        && userConfig.contains("self.twoColumnLayout = defaults.object(forKey: \"twoColumnLayout\") as? Bool ?? false")
        && userConfig.contains("twoColumnLayout: twoColumnLayout")
        && userConfig.contains("twoColumnLayout = settings.twoColumnLayout ?? false"),
    "UserConfig should persist and map the two-column profile preference"
)
require(
    dictionarySettings.contains("NativeSettingsToggle(\"Two-Column Layout\", isOn: $userConfig.twoColumnLayout)")
        && dictionarySettings.contains("Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens."),
    "Dictionary Settings should expose the localized toggle and guidance"
)
require(
    appearanceSettings.contains("in: 100...800, step: 10"),
    "popup height should support the upstream 800-point maximum"
)
require(
    popupView.contains(#"window.twoColumnLayout = \(userConfig.twoColumnLayout);"#)
        && dictionarySearch.contains(#"window.twoColumnLayout = \(userConfig.twoColumnLayout);"#),
    "every popup payload builder should inject the shared preference"
)
require(
    popupScript.contains("function layoutMasonry()")
        && popupScript.contains("function scheduleMasonry()")
        && popupScript.contains("function observeMasonry(root)")
        && popupScript.contains("className: 'glossary-sections'")
        && popupScript.contains("classList.toggle('single-section', dictNames.length === 1)")
        && popupScript.contains("new ResizeObserver(scheduleMasonry)")
        && popupScript.contains("window.twoColumnLayout && !document.getElementById('popup-two-column-layout')")
        && popupScript.contains("syncButtonFrames();"),
    "popup.js should implement upstream masonry with a resize fallback and button synchronization"
)
require(
    popupStyles.contains(".glossary-group {")
        && popupStyles.contains("border-radius: calc(8px * var(--popup-scale));")
        && popupStyles.contains("border: var(--popup-space-1) solid rgba(0, 0, 0, 0.14);")
        && popupStyles.contains(".glossary-sections > .glossary-group"),
    "glossary cards should use the scaled upstream presentation"
)
require(
    dictionariesCatalog.contains("\"Two-Column Layout\"")
        && dictionariesCatalog.contains("\"双栏布局\"")
        && dictionariesCatalog.contains("\"Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens.\"")
        && dictionariesCatalog.contains("\"将词典释义排列为两栏。建议仅在全宽或较大的查词框中使用。\""),
    "the new visible strings should include Simplified Chinese translations"
)
require(
    changelog.contains("two-column glossary layout"),
    "the user-visible popup layout should be recorded under Unreleased"
)

print("PASS: popup two-column layout contract")
