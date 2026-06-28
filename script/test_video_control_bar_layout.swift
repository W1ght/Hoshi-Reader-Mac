import Foundation

private func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError("\(message): missing \(needle)")
    }
}

let userConfig = try String(contentsOfFile: "Core/UserConfig.swift", encoding: .utf8)

assertContains(
    userConfig,
    "enum VideoControlBarLayout: String, CaseIterable, Codable",
    "Video control bar layout enum"
)
assertContains(userConfig, "case floating", "floating case")
assertContains(userConfig, "case compactBottom", "compact bottom case")
assertContains(userConfig, "var videoControlBarLayout: VideoControlBarLayout", "persisted layout setting")
assertContains(userConfig, "forKey: \"videoControlBarLayout\"", "layout storage key")
assertContains(
    userConfig,
    "defaults.string(forKey: \"videoControlBarLayout\")",
    "layout default decode"
)
assertContains(userConfig, "?? .floating", "layout default fallback")

print("Video control bar layout tests passed")
