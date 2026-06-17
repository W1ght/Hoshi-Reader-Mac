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
let inspector = read("Features/Video/VideoInspectorView.swift")
let localization = read("Localizable.xcstrings")

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
    userConfig,
    contains: "enum VideoSubtitleMaskMode: String, CaseIterable, Codable",
    "video subtitle mask mode should be a shared Codable user preference"
)
require(
    userConfig,
    contains: "var videoSubtitleMaskEnabled: Bool",
    "video subtitle mask enabled preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleMaskMode: VideoSubtitleMaskMode",
    "video subtitle mask mode preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleMaskBlurRadius: Double",
    "video subtitle blur radius preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleMaskHiddenOpacity: Double",
    "video subtitle transparent-mode opacity preference should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "min(max(videoSubtitleMaskBlurRadius, 0), 20)",
    "video subtitle blur radius should be clamped to 0...20"
)
require(
    userConfig,
    contains: "min(max(videoSubtitleMaskHiddenOpacity, 0), 1)",
    "video subtitle hidden opacity should be clamped to 0...1"
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
    settings,
    contains: "\"Subtitle Mask\"",
    "Video settings should expose subtitle mask controls"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleMaskEnabled",
    "Video settings should expose the subtitle mask toggle"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleMaskMode",
    "Video settings should expose the subtitle mask mode"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleMaskBlurRadius",
    "Video settings should expose the subtitle blur radius slider"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleMaskHiddenOpacity",
    "Video settings should expose the subtitle hidden opacity slider"
)
require(
    inspector,
    contains: "\"Subtitle Mask\"",
    "Video inspector should expose subtitle mask controls in the Subtitles tab"
)
require(
    inspector,
    contains: "subtitleMaskSection",
    "Video inspector should keep subtitle mask controls in a dedicated section"
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
require(
    player,
    contains: "maskEnabled: userConfig.videoSubtitleMaskEnabled",
    "subtitle overlay should receive the configured mask toggle"
)
require(
    player,
    contains: "maskMode: userConfig.videoSubtitleMaskMode",
    "subtitle overlay should receive the configured mask mode"
)
require(
    player,
    contains: "maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius",
    "subtitle overlay should receive the configured blur radius"
)
require(
    player,
    contains: "maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity",
    "subtitle overlay should receive the configured transparent-mode opacity"
)
for key in [
    "\"Subtitle Mask\"",
    "\"Mask subtitles until hover\"",
    "\"Mask Mode\"",
    "\"Blur Radius\"",
    "\"Hidden Opacity\"",
    "\"Transparent\"",
] {
    require(
        localization,
        contains: key,
        "Localizable.xcstrings should include \(key) for subtitle mask UI"
    )
}

print("Video settings contract tests passed")
