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

let userConfig = read("Core/UserConfig.swift")
let settings = read("Features/Settings/VideoSettingsView.swift")
let nativeSettings = read("NativeMac/NativeReuseViews.swift")
let player = read("Features/Video/VideoPlayerScreen.swift")

require(
    userConfig,
    contains: "var videoAutoPlayNext: Bool",
    "video auto-play preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoRememberPlaybackPosition: Bool",
    "video history preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSeekInterval: Double",
    "video seek interval should be centralized in UserConfig"
)
require(
    settings,
    contains: "\"Auto-Play Next Episode\"",
    "Video settings should expose auto-play next"
)
require(
    settings,
    contains: "\"Remember Playback Position\"",
    "Video settings should expose playback history"
)
require(
    settings,
    contains: "$userConfig.videoSeekInterval",
    "Video settings should expose the default seek interval"
)
require(
    nativeSettings,
    contains: "#if HOSHI_VIDEO\n                nativeSettingsRow(.video)",
    "Light settings should compile without the Video settings row"
)
require(
    player,
    contains: "model.skip(by: -userConfig.videoSeekInterval)",
    "backward seek should use the configured interval"
)
require(
    player,
    contains: "model.skip(by: userConfig.videoSeekInterval)",
    "forward seek should use the configured interval"
)

print("Video settings contract tests passed")
