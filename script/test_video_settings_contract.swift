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

private func requireCondition(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
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
let shortcutActions = read("Features/Video/VideoShortcutActions.swift")

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
    contains: "var videoSubtitleFontFamily: String",
    "video subtitle font family should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleFontSize: Double",
    "video subtitle font size should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "defaults.string(forKey: \"videoSubtitleFontFamily\") ?? \"\"",
    "video subtitle font family should default to the asbplayer-style system font"
)
require(
    userConfig,
    contains: "defaults.object(forKey: \"videoSubtitleFontSize\") as? Double ?? 36",
    "video subtitle font size should default to asbplayer's 36 px default"
)
require(
    userConfig,
    contains: "min(max(newValue, 12), 72)",
    "video subtitle font size should be clamped to a readable range"
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
    contains: "min(max(newValue, 0), 20)",
    "video subtitle blur radius should be clamped to 0...20"
)
require(
    userConfig,
    contains: "min(max(newValue, 0), 1)",
    "video subtitle hidden opacity should be clamped to 0...1"
)
requireCondition(
    !userConfig.contains("min(max(videoSubtitleMaskHiddenOpacity, 0), 1)"),
    "video subtitle hidden opacity observer should not read itself and recurse"
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
    contains: "\"Subtitle Appearance\"",
    "Video settings should expose subtitle appearance controls"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleFontFamily",
    "Video settings should expose the subtitle font picker"
)
require(
    settings,
    contains: "$userConfig.videoSubtitleFontSize",
    "Video settings should expose the subtitle size slider"
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
    settings,
    contains: "shortcutSummarySection",
    "Video settings should include a shortcut summary section"
)
for label in [
    "\"Playback Shortcuts\"",
    "\"Subtitle Shortcuts\"",
    "\"Audio Shortcuts\"",
    "\"Open Keyboard Shortcuts\"",
] {
    require(
        settings,
        contains: label,
        "Video settings shortcut summary should include \(label)"
    )
}
require(
    inspector,
    contains: "\"Subtitle Appearance\"",
    "Video inspector should expose subtitle appearance controls in the Subtitles tab"
)
require(
    inspector,
    contains: "subtitleAppearanceSection",
    "Video inspector should keep subtitle appearance controls in a dedicated section"
)
require(
    inspector,
    contains: "subtitleFontFamily",
    "Video inspector should bind the subtitle font family setting"
)
require(
    inspector,
    contains: "subtitleFontSize",
    "Video inspector should bind the subtitle font size setting"
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
require(
    player,
    contains: "fontFamily: userConfig.videoSubtitleFontFamily",
    "subtitle overlay should receive the configured font family"
)
require(
    player,
    contains: "fontSize: userConfig.videoSubtitleFontSize",
    "subtitle overlay should receive the configured font size"
)
for actionID in [
    "video.previousSubtitleCue",
    "video.nextSubtitleCue",
    "video.toggleSubtitlesVisible",
    "video.cycleSubtitleTrack",
    "video.volumeDown",
    "video.volumeUp",
] {
    require(
        shortcutActions,
        contains: actionID,
        "Video shortcut actions should include \(actionID)"
    )
    require(
        player,
        contains: actionID
            .replacingOccurrences(of: "video.", with: "VideoShortcutActions.")
            .replacingOccurrences(of: "previousSubtitleCue", with: "previousSubtitleCue.id")
            .replacingOccurrences(of: "nextSubtitleCue", with: "nextSubtitleCue.id")
            .replacingOccurrences(of: "toggleSubtitlesVisible", with: "toggleSubtitlesVisible.id")
            .replacingOccurrences(of: "cycleSubtitleTrack", with: "cycleSubtitleTrack.id")
            .replacingOccurrences(of: "volumeDown", with: "volumeDown.id")
            .replacingOccurrences(of: "volumeUp", with: "volumeUp.id"),
        "Video shortcut handlers should wire \(actionID)"
    )
}
requireCondition(
    player.contains(".onTapGesture(count: 2)")
        || player.contains("TapGesture(count: 2)"),
    "video canvas should support double-click full screen"
)
require(
    player,
    contains: "toggleFullScreenFromPointer()",
    "video canvas double-click should route through the pointer full-screen toggle"
)
require(
    player,
    contains: "togglePlaybackFromPointer()",
    "video canvas single-click should route through the pointer playback toggle"
)
require(
    player,
    contains: ".onContinuousHover { phase in",
    "video canvas should reveal playback chrome when the pointer moves over the video"
)
require(
    player,
    contains: "hidePlaybackChromeForPointerExit()",
    "video playback chrome should hide when the pointer leaves the app/window or the app becomes inactive"
)
for key in [
    "\"Subtitle Mask\"",
    "\"Subtitle Appearance\"",
    "\"Subtitle Font\"",
    "\"System Default\"",
    "\"Subtitle Size\"",
    "\"Defaults match asbplayer text subtitles: system font and 36 px size.\"",
    "\"Mask subtitles until hover\"",
    "\"Mask Mode\"",
    "\"Blur Radius\"",
    "\"Hidden Opacity\"",
    "\"Transparent\"",
    "\"Playback Shortcuts\"",
    "\"Subtitle Shortcuts\"",
    "\"Audio Shortcuts\"",
    "\"Open Keyboard Shortcuts\"",
    "\"Previous Subtitle\"",
    "\"Next Subtitle\"",
    "\"Show / Hide Subtitles\"",
    "\"Cycle Subtitle Track\"",
    "\"Volume Down\"",
    "\"Volume Up\"",
] {
    require(
        localization,
        contains: key,
        "Localizable.xcstrings should include \(key) for subtitle mask UI"
    )
}

print("Video settings contract tests passed")
