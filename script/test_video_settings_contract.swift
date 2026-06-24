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
let subtitleOverlay = read("Features/Video/Subtitles/SubtitleOverlayView.swift")
let interactiveSubtitleText = read("Features/Video/Subtitles/InteractiveSubtitleTextView.swift")
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
    contains: "var videoMiningHistoryLimit: Int",
    "video mining history limit should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "defaults.object(forKey: \"videoMiningHistoryLimit\") as? Int ?? 25",
    "video mining history should default to asbplayer's 25-item limit"
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
    contains: "var videoSubtitleColor: Color",
    "video subtitle text color should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleLookupHighlightColor: Color",
    "video lookup highlight background color should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleLookupHighlightTextColor: Color",
    "video lookup highlight text color should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "Color(.sRGB, red: 181.0 / 255.0, green: 193.0 / 255.0, blue: 203.0 / 255.0, opacity: 62.0 / 255.0)",
    "video lookup highlight should default to the user's approved #B5C1CB3E color"
)
require(
    userConfig,
    contains: "Self.saveColor(videoSubtitleColor, key: \"videoSubtitleColor\")",
    "video subtitle text color should persist through the shared color codec"
)
require(
    userConfig,
    contains: "Self.saveColor(videoSubtitleLookupHighlightColor, key: \"videoSubtitleLookupHighlightColor\")",
    "video lookup highlight color should persist through the shared color codec"
)
require(
    userConfig,
    contains: "Self.saveColor(videoSubtitleLookupHighlightTextColor, key: \"videoSubtitleLookupHighlightTextColor\")",
    "video lookup highlight text color should persist through the shared color codec"
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
    contains: "\"Remember Playback State\"",
    "Video settings should expose playback-state history"
)
require(
    settings,
    contains: "\"Restores the last playback position and subtitle selection for each video.\"",
    "Video settings should explain which per-video state is restored"
)
require(
    settings,
    contains: "$userConfig.videoSeekInterval",
    "Video settings should expose the default seek interval"
)
require(
    settings,
    contains: "$userConfig.videoMiningHistoryLimit",
    "Video settings should expose the mining history storage limit"
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
    contains: "ColorPicker(\"Subtitle Color\", selection: $userConfig.videoSubtitleColor",
    "Video settings should expose the subtitle text color picker"
)
require(
    settings,
    contains: "ColorPicker(\"Lookup Highlight Color\", selection: $userConfig.videoSubtitleLookupHighlightColor",
    "Video settings should expose the lookup highlight color picker"
)
require(
    settings,
    contains: "ColorPicker(\"Lookup Highlight Text Color\", selection: $userConfig.videoSubtitleLookupHighlightTextColor",
    "Video settings should expose the lookup highlight text color picker"
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
for obsoleteShortcutUI in [
    "shortcutSummarySection",
    "shortcutSummaryGroup",
    "shortcutSummaryRow",
    "\"Playback Shortcuts\"",
    "\"Subtitle Shortcuts\"",
    "\"Audio Shortcuts\"",
    "\"Open Keyboard Shortcuts\"",
] {
    requireCondition(
        !settings.contains(obsoleteShortcutUI),
        "Video settings must not duplicate the unified shortcut UI: \(obsoleteShortcutUI)"
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
    contains: "ColorPicker(\"Subtitle Color\", selection: subtitleColor",
    "Video inspector should expose the subtitle text color picker"
)
require(
    inspector,
    contains: "ColorPicker(\"Lookup Highlight Color\", selection: subtitleLookupHighlightColor",
    "Video inspector should expose the lookup highlight color picker"
)
require(
    inspector,
    contains: "ColorPicker(\"Lookup Highlight Text Color\", selection: subtitleLookupHighlightTextColor",
    "Video inspector should expose the lookup highlight text color picker"
)
require(
    inspector,
    contains: "private var subtitleLookupHighlightTextColor: Binding<Color>",
    "Video inspector should bind the lookup highlight text color setting"
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
    contains: "#if HOSHI_VIDEO\n            Section(\"Video\") {\n                nativeSettingsRow(.video)\n            }\n            #endif",
    "Light settings should compile without the complete Video settings group"
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
require(
    player,
    contains: "subtitleColor: userConfig.videoSubtitleColor",
    "subtitle overlay should receive the configured text color"
)
require(
    player,
    contains: "lookupHighlightColor: userConfig.videoSubtitleLookupHighlightColor",
    "subtitle overlay should receive the configured lookup highlight color"
)
require(
    player,
    contains: "lookupHighlightTextColor: userConfig.videoSubtitleLookupHighlightTextColor",
    "subtitle overlay should receive the configured lookup highlight text color"
)
require(
    subtitleOverlay,
    contains: "let lookupHighlightTextColor: Color",
    "subtitle overlay should accept the configured lookup highlight text color"
)
require(
    subtitleOverlay,
    contains: "lookupHighlightTextColor: lookupHighlightTextColor",
    "subtitle overlay should pass lookup highlight text color into interactive subtitle rows"
)
require(
    interactiveSubtitleText,
    contains: "let lookupHighlightTextColor: Color",
    "interactive subtitle text view should accept lookup highlight text color"
)
require(
    interactiveSubtitleText,
    contains: ".foregroundColor",
    "interactive subtitle text view should apply lookup highlight text color to the selected range"
)
require(
    localization,
    contains: "\"Lookup Highlight Text Color\"",
    "lookup highlight text color label should be localized"
)
for actionID in [
    "video.mineCurrentSubtitle",
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
require(
    shortcutActions,
    contains: "key: \"z\"",
    "mine-current-subtitle should use the asbplayer macOS Z binding"
)
require(
    shortcutActions,
    contains: "EventModifiers.control.rawValue",
    "mine-current-subtitle should include Control"
)
require(
    shortcutActions,
    contains: "EventModifiers.shift.rawValue",
    "mine-current-subtitle should include Shift"
)
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
    "\"Remember Playback State\"",
    "\"Restores the last playback position and subtitle selection for each video.\"",
    "\"Subtitle Mask\"",
    "\"Subtitle Appearance\"",
    "\"Subtitle Font\"",
    "\"System Default\"",
    "\"Subtitle Size\"",
    "\"Subtitle Color\"",
    "\"Lookup Highlight Color\"",
    "\"Customize subtitle typography, text color, and lookup highlight background.\"",
    "\"Defaults match asbplayer text subtitles: system font and 36 px size.\"",
    "\"Mask subtitles until hover\"",
    "\"Mask Mode\"",
    "\"Blur Radius\"",
    "\"Hidden Opacity\"",
    "\"Transparent\"",
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
