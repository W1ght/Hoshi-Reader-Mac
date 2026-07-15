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
    ankiManager.contains("func addNote(content: [String: String], context: MiningContext) async -> Int64?")
        && ankiManager.contains("let noteID = (result as? NSNumber)?.int64Value")
        && ankiManager.contains("func openNoteInAnki(_ noteID: Int64) async -> Bool")
        && ankiManager.contains("action: \"guiBrowse\"")
        && ankiManager.contains("params: [\"query\": \"nid:\\(noteID)\"]"),
    "AnkiManager should retain the added note ID and open that exact note in Anki's browser"
)
require(
    ankiMining.contains("let noteID: Int64?")
        && ankiMining.contains("payload[\"noteID\"] = String(noteID)")
        && ankiMining.contains("return .added(noteID: noteID"),
    "the shared mining result should carry the added note ID back into the popup"
)
require(
    popupWebView.contains("name: \"openAnkiNote\"")
        && popupWebView.contains("AnkiManager.shared.openNoteInAnki(noteID)")
        && popupWebView.contains("return \"magnifyingglass\"")
        && popupScript.contains("window.hoshiInlineButtonSymbols?.viewNote")
        && popupScript.contains("openAnkiNoteAtIndex")
        && popupScript.contains("webkit.messageHandlers.openAnkiNote.postMessage(noteID)")
        && popupScript.contains("showAnkiNoteButton(entryIndex, result.noteID)")
        && popupScript.contains("viewNoteSlot.hidden = true"),
    "a hidden magnifying-glass view-note action should appear inside the entry after mining succeeds"
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
