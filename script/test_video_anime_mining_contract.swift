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
let popup = read("Features/Popup/PopupView.swift")
let architecture = read("docs/VIDEO_LEARNING_ARCHITECTURE.md")

require(
    screen.contains("let needsScreenshot = AnkiManager.shared.needsVideoScreenshot")
        && screen.contains("let needsAudioClip = AnkiManager.shared.needsVideoAudioClip")
        && screen.contains("captureScreenshot: needsScreenshot")
        && screen.contains("captureAudioClip: needsAudioClip")
        && !screen.contains("captureScreenshot: true")
        && !screen.contains("captureAudioClip: true"),
    "video subtitle mining should only capture media requested by Anki field mappings"
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
        && mining.contains("audioClipFilename == nil")
        && mining.contains("audioClipErrorMessage"),
    "mapped video audio should fail before AnkiConnect only when neither fallback URL nor direct filename is available"
)
require(
    mining.contains("func preflightAnkiMining")
        && mining.contains("preflightAlreadyPassed"),
    "Anki mining should expose a preflight path so duplicate checks can run before expensive media capture"
)
require(
    anki.contains("func getMediaDirPath")
        && anki.contains("cachedAnkiMediaDirectories")
        && anki.contains("action: \"getMediaDirPath\"")
        && anki.contains("isWritableFile"),
    "AnkiManager should cache and validate Anki collection.media paths for direct local media writes"
)
require(
    anki.contains("directAudioMarkup(filename:")
        && anki.contains("directImageMarkup(filename:")
        && anki.contains("[sound:\\(")
        && anki.contains("<img src=\\\"\\(")
        && anki.contains("writeDirectMedia"),
    "AnkiManager should write local media directly and put Anki media markup into note fields"
)
require(
    anki.contains("context.video?.audioClipFilename")
        && anki.contains("context.video?.screenshotFilename")
        && anki.contains("context.video?.audioClipURL")
        && anki.contains("context.video?.screenshotURL"),
    "AnkiManager should support direct Video filenames while preserving fallback URL attachments"
)
require(
    coordinator.contains("ankiMediaDirectory:")
        && coordinator.contains("captureScreenshot(to:")
        && coordinator.contains("exportAudioClip(")
        && coordinator.contains("try mediaStore.replaceMediaItem(")
        && coordinator.contains("screenshotFilename = filenames.screenshot")
        && coordinator.contains("audioClipFilename = filenames.audioClip")
        && coordinator.contains("audioClipErrorMessage = String("),
    "Video mining should await direct Anki media writes, expose filenames only after success, and retain audio failures"
)
require(
    screen.contains("compressScreenshot: AnkiManager.shared.compressVideoScreenshots")
        && coordinator.contains("compressScreenshot: Bool")
        && coordinator.contains("preparedScreenshot(at:"),
    "video mining must receive persisted screenshot compression"
)
require(
    ankiView.contains("if isVideoBuild")
        && ankiView.contains("Compress Video Screenshots"),
    "only Video builds expose screenshot compression"
)
require(
    coordinator.contains("suspendVideoThumbnailsForMining()")
        && coordinator.contains("resumeVideoThumbnailsForMining()")
        && coordinator.contains("await VideoThumbnailScheduler.shared.suspend(reason: .mining)")
        && coordinator.contains("await VideoThumbnailScheduler.shared.resume(reason: .mining)")
        && coordinator.contains("if captureScreenshot || captureAudioClip"),
    "Video mining should suspend low-priority library thumbnail work during screenshot and audio export"
)
if let mineEntryRange = popup.range(of: "private func mineEntry("),
   let mineEntryEnd = popup[mineEntryRange.lowerBound...].range(of: "private func showMiningToast")?.lowerBound {
    let mineEntry = popup[mineEntryRange.lowerBound..<mineEntryEnd]
    let preflightIndex = mineEntry.range(of: "preflightAnkiMining(content: content, profileID: profileID)")?.lowerBound
    let sasayakiIndex = mineEntry.range(of: "cueSentenceAudio")?.lowerBound
    let videoContextIndex = mineEntry.range(of: "miningContextProvider")?.lowerBound
    require(
        preflightIndex != nil
            && sasayakiIndex != nil
            && videoContextIndex != nil
            && preflightIndex! < sasayakiIndex!
            && preflightIndex! < videoContextIndex!,
        "Popup mining should check duplicate/configuration before preparing Sasayaki or Video media"
    )
} else {
    require(false, "Popup mining entry point should be available for preflight ordering checks")
}
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
