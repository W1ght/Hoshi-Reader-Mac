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
require(
    source,
    contains: "track.type == \"sub\" ? \"subtitle\" : track.type",
    "mpv sub tracks should map to the Hoshi subtitle track type"
)

print("Video track mapping tests passed")
