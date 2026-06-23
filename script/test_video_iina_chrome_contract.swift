import Foundation

private func read(_ path: String) -> String {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return source
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let surface = read("Features/Video/VideoTranslucentSurface.swift")
let controls = read("Features/Video/VideoControlsView.swift")
let inspector = read("Features/Video/VideoInspectorView.swift")
let screen = read("Features/Video/VideoPlayerScreen.swift")
let viewModel = read("Features/Video/VideoPlayerViewModel.swift")
let settings = read("Features/Settings/VideoSettingsView.swift")
let config = read("Core/UserConfig.swift")

require(
    surface.contains("NSGlassEffectView")
        && surface.contains("contentView")
        && surface.contains("NSVisualEffectView")
        && surface.contains(".popover")
        && surface.contains("NSHostingView<AnyView>"),
    "video chrome should use one AppKit translucent hosting surface"
)
require(!controls.contains("glassEffect("), "control buttons should not add nested glass")
require(!inspector.contains("glassEffect("), "inspector sections and rows should not add nested glass")
require(controls.contains("var onScrubbingChanged: (Bool) -> Void"), "controls should report scrubbing state")
require(controls.contains("progressSlider\n                .frame(maxWidth: .infinity)"), "progress row should use flexible width")

let volumeIndex = controls.range(of: "volumeControl")!.lowerBound
let episodeIndex = controls.range(of: "episodeControls")!.lowerBound
let historyIndex = controls.range(of: "Label(\"Mining History\"")!.lowerBound
let openIndex = controls.range(of: "Label(\"Open Video\"")!.lowerBound
let profileIndex = controls.range(of: "profileMenu", range: openIndex..<controls.endIndex)!.lowerBound
let mineIndex = controls.range(of: "Label(\"Mine Current Subtitle\"")!.lowerBound
let inspectorIndex = controls.range(of: "Label(\"Inspector\"")!.lowerBound
let fullscreenIndex = controls.range(of: "arrow.up.left.and.arrow.down.right")!.lowerBound
require(
    volumeIndex < episodeIndex
        && episodeIndex < historyIndex
        && historyIndex < openIndex
        && openIndex < profileIndex
        && profileIndex < mineIndex
        && mineIndex < inspectorIndex
        && inspectorIndex < fullscreenIndex,
    "first control row should follow the approved IINA ordering"
)

require(inspector.contains("let snapshot: VideoInspectorSnapshot"), "inspector should receive a low-frequency snapshot")
require(screen.contains("snapshot: model.inspectorSnapshot"), "screen should consume the low-frequency inspector projection")
require(
    viewModel.contains("if inspectorSnapshot != nextInspectorSnapshot")
        && viewModel.contains("inspectorSnapshot = nextInspectorSnapshot"),
    "the inspector projection should publish only when inspector inputs change"
)
require(!screen.contains(".padding(.vertical, 16)\n        .padding(.trailing, 16)"), "inspector should attach to the trailing edge")

require(
    config.contains("videoPlaybackControlsAutoHideEnabled")
        && config.contains("videoPlaybackControlsAutoHideDelay")
        && config.contains("videoPlaybackControlsPositionX")
        && config.contains("videoPlaybackControlsPositionY"),
    "video chrome preferences should persist in UserConfig"
)
require(
    settings.contains("Auto-Hide Playback Controls")
        && settings.contains("Playback Controls Hide Delay"),
    "Video Settings should expose the auto-hide controls"
)
require(screen.contains("NSCursor.setHiddenUntilMouseMoves"), "video viewing should conditionally hide the cursor")
require(screen.contains("NSHapticFeedbackManager"), "center snapping should provide alignment feedback")

print("Video IINA chrome contract tests passed")
