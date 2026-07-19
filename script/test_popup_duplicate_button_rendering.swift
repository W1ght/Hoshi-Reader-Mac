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

let popupScript = try source("Features/Popup/popup.js")
let popupStyles = try source("Features/Popup/popup.css")
let popupWebView = try source("Features/Popup/PopupWebView.swift")
let popupView = try source("Features/Popup/PopupView.swift")
let ankiMining = try source("Features/Popup/AnkiMining.swift")
let ankiManager = try source("Core/AnkiManager.swift")
let xcodeProject = try source("Niratan.xcodeproj/project.pbxproj")
let localizations = try source("Localizable.xcstrings")
let changelog = try source("docs/CHANGELOG.md")

require(
    xcodeProject.contains("Popup/PopupSystemSymbolRenderer.swift,"),
    "the synchronized Features group should include the popup symbol renderer in the app target"
)

require(
    popupWebView.contains("PopupSystemSymbolRenderer.duplicateSymbolDataURL")
        && popupWebView.contains("PopupSystemSymbolRenderer.viewNoteSymbolDataURL")
        && popupWebView.contains("window.hoshiInlineButtonSymbols = {")
        && popupWebView.contains("viewNote: viewNoteSymbolDataURL || null")
        && popupWebView.contains("\"viewNoteSymbolDataURL\": viewNoteSymbolDataURL"),
    "PopupWebView should inject the duplicate and view-note system symbols before rendering"
)
require(
    popupScript.contains("window.hoshiInlineButtonSymbols?.duplicate")
        && popupScript.contains("class=\"inline-system-symbol\"")
        && popupScript.contains("--inline-system-symbol-mask"),
    "duplicate Add to Anki state should prefer the injected system symbol mask"
)
require(
    popupScript.contains(#"<rect x="5" y="7" width="11" height="11""#),
    "duplicate Add to Anki state should retain the SVG fallback"
)
require(
    popupStyles.contains(".inline-system-symbol {")
        && popupStyles.contains("-webkit-mask: var(--inline-system-symbol-mask) center / contain no-repeat;")
        && popupStyles.contains("background: currentColor;"),
    "inline system symbols should use a currentColor CSS mask"
)
require(
    popupStyles.contains(".inline-action-button:disabled {\n    opacity: 0.45;\n    background: transparent;\n}"),
    "disabled inline action buttons should retain a transparent background"
)
require(
    popupScript.contains("slot.disabled = !enabled;")
        && popupScript.contains("if (slot.dataset.enabled === 'false') { return; }"),
    "duplicate Add to Anki entries should remain disabled and ignore clicks"
)

require(
    ankiManager.contains("import AppKit")
        && ankiManager.contains("func addNote(content: [String: String], context: MiningContext) async -> Int64?")
        && ankiManager.contains("let noteID = (result as? NSNumber)?.int64Value")
        && ankiManager.contains("func openNoteInAnki(_ noteID: Int64) async -> Bool")
        && ankiManager.contains("func openNotesInAnki(_ noteIDs: [Int64]) async -> Bool")
        && ankiManager.contains("action: \"guiBrowse\"")
        && ankiManager.contains("let query = \"nid:\\(validNoteIDs.map(String.init).joined(separator: \",\"))\"")
        && ankiManager.components(separatedBy: "action: \"guiBrowse\"").count == 2
        && ankiManager.contains("await activateAnkiApplication()")
        && ankiManager.contains("NSApp.yieldActivation(to: application)")
        && ankiManager.contains("application.activate()")
        && ankiManager.contains("where !application.isActive")
        && ankiManager.range(of: "await activateAnkiApplication()")!.lowerBound
            < ankiManager.range(of: "action: \"guiBrowse\"")!.lowerBound,
    "AnkiManager should cooperatively activate Anki before its single Browser request"
)
require(
    ankiManager.contains("struct AnkiDuplicateLookupResult")
        && ankiManager.contains("\"noteIDs\": noteIDs.map(String.init)")
        && ankiManager.contains("func duplicateLookup(word: String) async -> AnkiDuplicateLookupResult")
        && ankiManager.contains("action: \"findNotes\"")
        && ankiManager.contains("quotedAnkiSearchTerm(\"deck:\\(deck)\")")
        && ankiManager.contains("quotedAnkiSearchTerm(\"note:\\(noteTypeName)\")"),
    "duplicate checks should resolve existing note IDs with the configured Anki scope"
)
require(
    ankiMining.contains("let noteID: Int64?")
        && ankiMining.contains("payload[\"noteID\"] = String(noteID)")
        && ankiMining.contains("return .added(noteID: noteID"),
    "the shared mining result should carry the added note ID back into the popup"
)
require(
    popupWebView.contains("name: \"openAnkiNote\"")
        && popupWebView.contains("AnkiManager.shared.openNotesInAnki(noteIDs)")
        && popupWebView.contains("duplicateLookup(word: word).webPayload")
        && popupWebView.contains("return \"magnifyingglass\"")
        && popupScript.contains("window.hoshiInlineButtonSymbols?.viewNote")
        && popupScript.contains("openAnkiNoteAtIndex")
        && popupScript.contains("webkit.messageHandlers.openAnkiNote.postMessage(noteIDs)")
        && popupScript.contains("showAnkiNoteButton(entryIndex, result.noteID)")
        && popupScript.contains("showAnkiNoteButton(entryIndex, noteIDs, slots.viewNote)")
        && popupScript.contains("applyAnkiDuplicateLookup(idx, duplicateLookup, { mine: mineSlot, viewNote: viewNoteSlot })")
        && popupScript.contains("normalizedAnkiNoteIDs(duplicateLookup?.noteIDs)")
        && popupScript.contains("viewNoteSlot.hidden = true"),
    "the magnifying-glass action should appear after mining or when duplicate lookup finds existing note IDs"
)
require(
    popupWebView.contains("func relinquishTextInputFocus() -> Bool")
        && popupWebView.contains("firstResponderView.isDescendant(of: self)")
        && popupWebView.contains("(webView as? NativePopupWKWebView)?.relinquishTextInputFocus()")
        && popupWebView.contains("(message.webView as? NativePopupWKWebView)?.relinquishTextInputFocus()")
        && popupWebView.contains("await Task.yield()")
        && popupWebView.contains("guard NSApp.isActive,")
        && popupWebView.contains("window.isKeyWindow else { return }"),
    "popup WebViews should relinquish text input before Anki activation or teardown"
)
require(
    popupScript.contains("content._entryIndex = String(entryIndex)")
        && popupView.contains("ankiNoteCommand: ankiNoteCommand")
        && popupView.contains("showAnkiNoteButton(entryIndex: entryIndex, noteID: noteID)"),
    "context-selected mining should reveal the same in-popup Anki navigation button"
)
require(
    localizations.contains("\"View added note in Anki\"")
        && localizations.contains("\"在 Anki 中查看已添加的笔记\"")
        && changelog.contains("放大镜按钮")
        && changelog.contains("magnifying-glass button"),
    "the user-visible Anki navigation action should be localized and recorded"
)

print("PASS: popup Anki action button rendering contract")
