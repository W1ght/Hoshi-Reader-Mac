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
let dictionaries = read("Dictionaries.xcstrings")
let architecture = read("docs/VIDEO_LEARNING_ARCHITECTURE.md")

require(
    screen.contains("captureScreenshot: true")
        && screen.contains("captureAudioClip: true"),
    "video subtitle mining should always try to capture the current frame and cue audio range"
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
    ankiView.contains("videoAnimeCardSection")
        && ankiView.contains("\"Anime Card Fields\"")
        && ankiView.contains("\"Apply Anime Card Preset\"")
        && ankiView.contains("applyAnimeCardPreset()")
        && ankiView.contains("animeCardHandlebar(for:")
        && ankiView.contains("Handlebars.videoAudioClip.rawValue")
        && ankiView.contains("Handlebars.videoScreenshot.rawValue"),
    "Anki settings should expose a video/anime card preset with media placeholders"
)
for text in [
    "Anime Card Fields",
    "Apply Anime Card Preset",
    "Subtitle audio clip",
    "Current video frame",
    "Video mining captures the current frame",
] {
    require(
        dictionaries.contains(text),
        "Dictionaries localization should include \(text)"
    )
}
require(
    architecture.contains("mpvacious-style")
        && architecture.contains("{video-screenshot}")
        && architecture.contains("{video-audio-clip}"),
    "video architecture docs should describe the anime card media-mining flow"
)

print("Video anime mining contract passed")
