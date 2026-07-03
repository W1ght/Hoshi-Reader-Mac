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
let xcodeProject = try source("Niratan.xcodeproj/project.pbxproj")

require(
    xcodeProject.contains("Popup/PopupSystemSymbolRenderer.swift,"),
    "the synchronized Features group should include the popup symbol renderer in the app target"
)

require(
    popupWebView.contains("PopupSystemSymbolRenderer.duplicateSymbolDataURL")
        && popupWebView.contains("window.hoshiInlineButtonSymbols = {")
        && popupWebView.contains("\"duplicateSymbolDataURL\": duplicateSymbolDataURL"),
    "PopupWebView should inject the system duplicate symbol before rendering"
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

print("PASS: popup duplicate button rendering contract")
