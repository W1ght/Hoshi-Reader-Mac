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

func requireOrdered(_ source: String, _ snippets: [String], _ message: String) {
    var lowerBound = source.startIndex
    for snippet in snippets {
        guard let range = source.range(of: snippet, range: lowerBound..<source.endIndex) else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        lowerBound = range.upperBound
    }
}

let app = try source("NativeMac/HoshiNativeMacApp.swift")
let screen = try source("Features/Video/VideoPlayerScreen.swift")
let commands = (try? source("Features/Video/VideoPlaybackCommands.swift")) ?? ""
let project = try source("Hoshi Reader.xcodeproj/project.pbxproj")

let windowGroupRange = app.range(of: "WindowGroup {")!.lowerBound..<app.range(of: "Window(\"Video\", id: VideoWindowCoordinator.windowID)")!.lowerBound
let windowGroupSource = String(app[windowGroupRange])

require(
    !windowGroupSource.contains("VideoPlaybackCommands()"),
    "video playback menus must not be attached to the main Reader window group"
)
requireOrdered(
    app,
    [
        "Window(\"Video\", id: VideoWindowCoordinator.windowID)",
        ".commands {\n            VideoPlaybackCommands()",
    ],
    "video playback commands should be attached to the dedicated Video window scene"
)
require(
    commands.contains("struct VideoPlaybackCommands: Commands")
        && commands.contains("@FocusedValue(\\.videoPlaybackCommandContext)")
        && commands.contains("CommandMenu(\"Video\")")
        && commands.contains("CommandMenu(\"Audio\")")
        && commands.contains("CommandMenu(\"Subtitles\")"),
    "video playback commands should expose Video, Audio and Subtitles menus through SwiftUI command menus"
)
require(
    commands.contains("struct VideoPlaybackCommandContext")
        && commands.contains("struct VideoPlaybackCommandContextKey: FocusedValueKey")
        && commands.contains("var videoPlaybackCommandContext: VideoPlaybackCommandContext?"),
    "video playback commands should define a focused command context instead of duplicating player state"
)
require(
    commands.contains("final class VideoPlaybackMenuVisibilityController")
        && commands.contains("NSWindow.didBecomeKeyNotification")
        && commands.contains("NSWindow.didResignKeyNotification")
        && commands.contains("item.isHidden = !shouldShow")
        && commands.contains("VideoWindowCoordinator.windowID"),
    "video playback menus should be hidden outside the actual Video key window"
)
require(
    app.contains("VideoPlaybackMenuVisibilityController.shared.install()"),
    "app launch should install the Video command menu visibility bridge in Video builds"
)
require(
    commands.contains("String(localized: \"Video\")")
        && commands.contains("String(localized: \"Audio\")")
        && commands.contains("String(localized: \"Subtitles\")"),
    "video playback menu titles should use existing localized Video, Audio and Subtitles strings"
)
require(
    screen.contains(".focusedSceneValue(\\.videoPlaybackCommandContext, videoPlaybackCommandContext)")
        && screen.contains("private var videoPlaybackCommandContext: VideoPlaybackCommandContext"),
    "video player screen should publish its current playback command context from the Video window"
)
require(
    project.contains("Video/VideoPlaybackCommands.swift"),
    "Xcode synchronized Features membership should include the Video playback commands file"
)

print("Video menu commands contract passed")
