import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func source(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

let controls = try source("Features/Video/VideoControlsView.swift")
let localizable = try source("Localizable.xcstrings")

require(
    controls.contains("private var selectedProfileName: String")
        && controls.contains("private var profileMenuHelp: String")
        && controls.contains("String(format: String(localized: \"Video Profile: %@\"), selectedProfileName)"),
    "video profile control should expose the current Profile name without opening the menu"
)
require(
    controls.contains("Picker(")
        && controls.contains("\"Video Profile\"")
        && controls.contains("selection: Binding<String>")
        && controls.contains(".tag(profile.id)")
        && controls.contains(".pickerStyle(.inline)")
        && controls.contains(".labelsHidden()"),
    "video profile menu should be an inline picker so one click shows the checked active Profile"
)
require(
    controls.contains(".help(profileMenuHelp)")
        && controls.contains(".accessibilityLabel(Text(profileMenuHelp))"),
    "video profile icon should reveal the selected Profile through help and accessibility text"
)
require(
    localizable.contains("\"Video Profile: %@\"")
        && localizable.contains("\"视频 Profile：%@\""),
    "video profile help text should be localized in English and Chinese"
)

print("Video profile menu contract tests passed")
