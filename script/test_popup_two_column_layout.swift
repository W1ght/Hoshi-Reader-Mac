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

func compactWhitespace(_ string: String) -> String {
    string.filter { !$0.isWhitespace }
}

func requireOrdered(_ source: String, _ first: String, before second: String, _ message: String) {
    guard let firstRange = source.range(of: first),
          let secondRange = source.range(of: second),
          firstRange.lowerBound < secondRange.lowerBound else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let profile = try source("Models/Profile.swift")
let userConfig = try source("Core/UserConfig.swift")
let dictionarySettings = try source("Features/Settings/DictionaryView.swift")
let appearanceSettings = try source("Features/Settings/AppearanceView.swift")
let popupView = try source("Features/Popup/PopupView.swift")
let popupWebView = try source("Features/Popup/PopupWebView.swift")
let dictionarySearch = try source("Features/Dictionary/DictionarySearchView.swift")
let profileSettingsStore = try source("Core/ProfileSettingsStore.swift")
let popupScript = try source("Features/Popup/popup.js")
let popupStyles = try source("Features/Popup/popup.css")
let selectionScript = try source("Features/Reader/ReaderWebView/selection.js")
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
    appearanceSettings.contains("in: 100...1400, step: 10"),
    "popup width should support a 1400-point maximum"
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
    popupWebView.contains("var twoColumnLayout: Bool = false")
        && popupWebView.contains("var lastTwoColumnLayout: Bool?")
        && popupWebView.contains("window.twoColumnLayout = \\(twoColumnLayout);")
        && popupWebView.contains("\"twoColumnLayout\": parent.twoColumnLayout")
        && popupWebView.contains("window.hoshiSetTwoColumnLayout?."),
    "PopupWebView should update the live WebView when the two-column preference changes"
)
require(
    popupView.contains("private var effectiveTwoColumnLayout: Bool")
        && popupView.contains("ProfileSettingsStore.shared.dictionarySettings(")
        && popupView.contains("fallback: userConfig.dictionaryProfileSettings()")
        && popupView.contains("twoColumnLayout: effectiveTwoColumnLayout")
        && profileSettingsStore.contains("func dictionarySettings(")
        && profileSettingsStore.contains("profileID != appliedProfileID")
        && profileSettingsStore.contains("repository.dictionarySettingsURL(for: profileID)"),
    "shared Reader/Video popup should resolve two-column layout from its popup Profile"
)
require(
    popupView.contains("let showsActionBar = userConfig.popupActionBar || backCount > 0 || forwardCount > 0")
        && popupView.contains("sasayakiControls(for: cue, player: player, includesActionBar: showsActionBar)"),
    "popup redirects should reveal history controls while Sasayaki shares the same control row"
)
require(
    dictionarySearch.components(separatedBy: "twoColumnLayout: userConfig.twoColumnLayout").count >= 3,
    "dictionary and nested dictionary WebViews should pass the live two-column preference"
)
require(
    popupScript.contains("function layoutMasonry()")
        && popupScript.contains("function scheduleMasonry()")
        && popupScript.contains("function observeMasonry(root)")
        && popupScript.contains("function applyTwoColumnLayout(enabled)")
        && popupScript.contains("window.hoshiSetTwoColumnLayout = (enabled) => {")
        && popupScript.contains("document.getElementById('popup-two-column-layout')?.remove();")
        && popupScript.contains("resetMasonryStyles();")
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
    popupStyles.contains("ruby > rt,\nruby > rp {")
        && popupStyles.contains("user-select: none;")
        && popupScript.contains("function getPopupSelectionText()")
        && popupScript.contains("selection.getRangeAt(i).cloneContents()")
        && popupScript.contains("container.querySelectorAll('rt, rp').forEach(el => el.remove());")
        && popupScript.contains("event.clipboardData.setData('text/plain', text);")
        && popupScript.contains("lastSelection = getPopupSelectionText();")
        && popupScript.contains("const popupSelectionText = getPopupSelectionText();"),
    "popup native selection, copying and mining context text should omit ruby annotation text"
)
require(
    compactWhitespace(popupScript).contains(
        "container.addEventListener('selectstart',()=>{suppressLookupClick=true;cachePopupSelection();},true);"
    ),
    "popup glossary native text selection should suppress the follow-up click lookup before it can clear single-column selections"
)
require(
    popupScript.contains("function isPopupInteractiveTarget(target)")
        && popupScript.contains("target.closest('a, button, summary, input, select, textarea, [role=\"button\"], [contenteditable=\"true\"]')")
        && compactWhitespace(popupScript).contains("if(isPopupInteractiveTarget(target)){popupPointerStart=null;suppressLookupClick=false;return;}"),
    "popup interactive controls should keep native pointer activation instead of being retargeted by glossary pointer capture"
)
require(
    compactWhitespace(popupScript).contains("container.setPointerCapture?.(e.pointerId);")
        && compactWhitespace(popupScript).contains("container.hasPointerCapture?.(e.pointerId)")
        && compactWhitespace(popupScript).contains("container.releasePointerCapture(e.pointerId);")
        && popupScript.contains("container.addEventListener('pointercancel'"),
    "popup glossary drags should retain pointer ownership until release or cancellation"
)
let compactPopupScript = compactWhitespace(popupScript)
requireOrdered(
    compactPopupScript,
    "if(suppressLookupClick){suppressLookupClick=false;cachePopupSelection();return;}",
    before: "if(!target?.closest('.glossary-content')&&!target?.closest('.expr-tag')){webkit.messageHandlers.tapOutside.postMessage(null);return;}",
    "popup click handling should preserve native text selection before treating a mouse-up target as outside the glossary"
)
require(
    selectionScript.contains("clearLookupSelection() {")
        && selectionScript.contains("this.clearLookupSelection();")
        && popupWebView.contains("window.hoshiSelection.clearLookupSelection?.()"),
    "tapOutside should clear Hoshi lookup highlights without removing native WebView text selection"
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
