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

let path = "Features/Video/Playback/MpvPlayerEngine.swift"
let source = try String(contentsOfFile: path, encoding: .utf8)
let nativeSource = try String(
    contentsOfFile: "Features/Video/Playback/HSMpvClient.mm",
    encoding: .utf8
)
let extractorSource = try String(
    contentsOfFile: "Features/Video/Subtitles/VideoSubtitleTrackExtractor.swift",
    encoding: .utf8
)
require(
    source,
    contains: "track.type == \"sub\" ? \"subtitle\" : track.type",
    "mpv sub tracks should map to the Hoshi subtitle track type"
)
require(source, contains: "ffIndex: track.ffIndex >= 0", "track mapping should preserve the FFmpeg stream index")
require(source, contains: "externalFilename: track.externalFilename", "track mapping should preserve external subtitle paths")
require(source, contains: "isImage: track.isImage", "track mapping should identify bitmap subtitle tracks")
require(nativeSource, contains: "strcmp(key, \"ff-index\")", "native track metadata should read FFmpeg stream indices")
require(nativeSource, contains: "strcmp(key, \"external-filename\")", "native track metadata should read external subtitle paths")
require(nativeSource, contains: "strcmp(key, \"image\")", "native track metadata should read bitmap subtitle flags")
require(extractorSource, contains: "HSSubtitleTrackExtractor.extractTextSubtitle", "selected text tracks should use the bundled extractor")
require(
    source,
    contains: "snapshot.tracks = []",
    "opening another video should invalidate the previous video's tracks so an identical new track list still reloads its transcript"
)

print("Video track mapping tests passed")
