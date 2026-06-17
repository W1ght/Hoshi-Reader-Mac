import Foundation

private func require(
    _ source: String,
    contains text: String,
    _ message: String
) {
    guard source.contains(text) else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func read(_ path: String) -> String {
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return value
}

let controls = read("Features/Video/VideoControlsView.swift")
let screen = read("Features/Video/VideoPlayerScreen.swift")

require(
    controls,
    contains: "var onToggleFullScreen: () -> Void",
    "the Video control surface should expose a fullscreen action"
)
require(
    controls,
    contains: "Image(systemName: \"arrow.up.left.and.arrow.down.right\")",
    "the Video control surface should render a fullscreen button"
)
require(
    screen,
    contains: "onToggleFullScreen: {",
    "the Video screen should wire the control through a fullscreen action closure"
)
require(
    screen,
    contains: "toggleFullScreen()",
    "the Video fullscreen control should still call the shared fullscreen implementation"
)
require(
    screen,
    contains: "dismissVideoPopupsIfNeeded()",
    "the Video fullscreen control should dismiss active subtitle lookup popups before continuing"
)
require(
    screen,
    contains: "private func toggleFullScreen()",
    "fullscreen UI and shortcuts should share one implementation"
)

print("Video fullscreen contract tests passed")
