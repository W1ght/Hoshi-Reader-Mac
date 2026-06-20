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

private func require(
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

let screen = read("Features/Video/VideoPlayerScreen.swift")
let anki = read("Core/AnkiManager.swift")
let ankiView = read("Features/Settings/AnkiView.swift")
let exporter = read("Features/Video/Playback/VideoAudioClipExporter.swift")
let clientHeader = read("Features/Video/Playback/HSMpvClient.h")
let clientImplementation = read("Features/Video/Playback/HSMpvClient.mm")
let coordinator = read("Features/Video/VideoMiningCoordinator.swift")
let mining = read("Features/Popup/AnkiMining.swift")
let architecture = read("docs/VIDEO_LEARNING_ARCHITECTURE.md")

require(
    screen.contains("captureScreenshot: true")
        && screen.contains("captureAudioClip: true"),
    "video subtitle mining should always try to capture the current frame and cue audio range"
)
require(
    coordinator.contains("VideoAudioClipRange.resolve(")
        && coordinator.contains("subtitleDelay: snapshot.subtitleDelay")
        && coordinator.contains("duration: snapshot.duration")
        && coordinator.contains("audioClipErrorMessage"),
    "video mining should apply subtitle delay, clamp the clip range, and retain export failures"
)
require(
    mining.contains("needsVideoAudioClip")
        && mining.contains("audioClipURL == nil")
        && mining.contains("audioClipErrorMessage"),
    "mapped video audio should fail before AnkiConnect when clip capture is unavailable"
)
require(
    anki.contains("videoAudioFields")
        && anki.contains("videoScreenshotFields")
        && anki.contains("context.video?.audioClipURL")
        && anki.contains("context.video?.screenshotURL")
        && anki.contains("\"audio\"")
        && anki.contains("\"picture\""),
    "AnkiConnect should attach video audio and screenshot media through mapped fields"
)
require(
    !ankiView.contains("videoAnimeCardSection")
        && !ankiView.contains("\"Anime Card Fields\"")
        && !ankiView.contains("\"Apply Anime Card Preset\"")
        && !ankiView.contains("applyAnimeCardPreset()")
        && !ankiView.contains("animeCardHandlebar(for:"),
    "Anki settings should not restore the old heuristic anime-card helper section"
)
require(
    ankiView.contains("Apply Novel Defaults")
        && ankiView.contains("Apply Anime Defaults")
        && ankiView.contains("AnkiFieldMappingPreset"),
    "Anki settings should expose explicit novel and anime note-type defaults"
)
require(
    ankiView.contains(".filter { isVideoBuild || !$0.isVideoSpecific }")
        && anki.contains("Handlebars.videoAudioClip.rawValue")
        && anki.contains("Handlebars.videoScreenshot.rawValue"),
    "Video placeholders should remain available through normal field mapping"
)
require(
    !exporter.contains("AVFoundation")
        && exporter.contains("HSMpvAudioClipExporter")
        && exporter.contains("audioTrackID"),
    "video audio export should use the bundled libmpv bridge and selected audio track"
)
require(
    clientHeader.contains("HSMpvAudioClipExporter")
        && clientImplementation.contains("mpv_create()")
        && clientImplementation.contains("audio-channels")
        && clientImplementation.contains("oacopts"),
    "the native bridge should run an isolated bundled-libmpv audio encoder"
)
require(
    architecture.contains("mpvacious-style")
        && architecture.contains("{video-screenshot}")
        && architecture.contains("{video-audio-clip}"),
    "video architecture docs should describe the anime card media-mining flow"
)

print("Video anime mining contract passed")
