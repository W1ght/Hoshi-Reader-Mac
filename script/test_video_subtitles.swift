import Foundation
#if canImport(AppKit)
import AppKit
#endif

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectFast(
    _ label: String,
    maxSeconds: TimeInterval,
    operation: () -> Void
) {
    let start = Date()
    operation()
    let elapsed = Date().timeIntervalSince(start)
    expect(
        elapsed <= maxSeconds,
        "\(label) should complete in \(maxSeconds)s, got \(String(format: "%.3f", elapsed))s"
    )
}

@main
private enum VideoSubtitleTests {
static func main() throws {
let srt = """
2
00:00:03,500 --> 00:00:05,000
二行目
です

1
00:00:01,000 --> 00:00:02,250
最初です
"""

let srtDocument = try SubtitleParser.parse(
    data: Data(srt.utf8),
    sourceURL: URL(fileURLWithPath: "/tmp/sample.srt")
)
expect(srtDocument.format == .srt, "SRT format should be detected")
expect(srtDocument.cues.count == 2, "SRT should parse two cues")
expect(srtDocument.cues[0].text == "最初です", "cues should be sorted by start time")
expect(srtDocument.cues[1].text == "二行目\nです", "multiline subtitle text should be preserved")
expect(srtDocument.cues[0].endTime == 2.25, "SRT milliseconds should be parsed")

#if canImport(AppKit)
let wrappedSubtitleText = "これはかなり長い字幕で、大きいフォントサイズでは自然に二行以上へ折り返される必要があります"
let wrappedEdgeRecipe = VideoSubtitleEdgeRecipe.make(
    style: .highContrast,
    strength: 0.5,
    fontSize: 43
)
let measuredLargeSubtitleHeight = SubtitleOverlayRowHeightMeasurer.height(
    for: wrappedSubtitleText,
    availableWidth: 360,
    fontFamily: "",
    fontSize: 43,
    fontWeight: 700,
    edgeAllowance: wrappedEdgeRecipe.layoutAllowance
)
let legacySingleLineEstimate = CGFloat(43 + 10)
expect(
    measuredLargeSubtitleHeight > legacySingleLineEstimate * 1.5,
    "large soft-wrapped subtitles should measure enough height for generated visual lines"
)
#endif

let vtt = """
WEBVTT

intro
00:00.500 --> 00:02.000 position:50%
こんにちは

00:01.500 --> 00:03.000
重なります
"""

let vttDocument = try SubtitleParser.parse(
    data: Data(vtt.utf8),
    sourceURL: URL(fileURLWithPath: "/tmp/sample.vtt")
)
expect(vttDocument.format == .webVTT, "WebVTT format should be detected")
expect(vttDocument.cues.count == 2, "WebVTT should parse two cues")

let ass = #"""
[Script Info]
ScriptType: v4.00+

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour
Style: Default,Arial,20,&H00FFFFFF

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,comment should be ignored
Dialogue: 0,0:00:01.23,0:00:03.45,Default,,0,0,0,,{\an8}こんにちは\N世界, with comma
Dialogue: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,{\\pos(1,2)}次{\\i1}です
"""#

let assDocument = try SubtitleParser.parse(
    data: Data(ass.utf8),
    sourceURL: URL(fileURLWithPath: "/tmp/sample.ass")
)
expect(assDocument.format.rawValue == "ass", "ASS format should be detected")
expect(assDocument.cues.count == 2, "ASS should parse dialogue events")
expect(assDocument.cues[0].startTime == 1.23, "ASS centiseconds should be parsed")
expect(assDocument.cues[0].text == "こんにちは\n世界, with comma", "ASS override tags should be stripped and text commas preserved")
expect(assDocument.cues[1].text == "次です", "ASS inline override tags should be stripped")

let ssaDocument = try SubtitleParser.parse(
    data: Data(ass.utf8),
    sourceURL: URL(fileURLWithPath: "/tmp/sample.ssa")
)
expect(ssaDocument.format.rawValue == "ssa", "SSA format should be detected")

if let realASSPath = ProcessInfo.processInfo.environment["HOSHI_REAL_ASS_PATH"],
   !realASSPath.isEmpty {
    let realASSURL = URL(fileURLWithPath: realASSPath)
    let realASSDocument = try SubtitleParser.parse(
        data: Data(contentsOf: realASSURL),
        sourceURL: realASSURL
    )
    expect(realASSDocument.format.rawValue == "ass", "real ASS sample should be detected")
    expect(!realASSDocument.cues.isEmpty, "real ASS sample should parse cue text")
    expect(
        realASSDocument.cues.allSatisfy { !$0.text.contains("{") && !$0.text.contains("}") },
        "real ASS sample transcript text should not expose override tags"
    )
}

let store = SubtitleCueStore(document: vttDocument)
expect(store.cues(at: 0.25).isEmpty, "timeline gaps should return no cue")
expect(store.cues(at: 1.75).map(\.text) == ["こんにちは", "重なります"], "overlapping cues should both be returned")
expect(store.cues(at: 3.1).isEmpty, "expired cues should not remain active")
expect(
    store.cues(atPlaybackTime: 2.75, subtitleDelay: 1).map(\.text) == ["こんにちは", "重なります"],
    "positive subtitle delay should display cues later"
)
expect(
    store.cues(atPlaybackTime: 0.75, subtitleDelay: -1).map(\.text) == ["こんにちは", "重なります"],
    "negative subtitle delay should display cues earlier"
)

let navigationDocument = SubtitleDocument(
    sourceURL: URL(fileURLWithPath: "/tmp/navigation.srt"),
    format: .srt,
    cues: [
        SubtitleCue(id: "first", startTime: 0, endTime: 1.5, text: "first"),
        SubtitleCue(id: "second", startTime: 2, endTime: 4, text: "second"),
        SubtitleCue(id: "third", startTime: 5, endTime: 7, text: "third")
    ],
    warnings: []
)
let navigationStore = SubtitleCueStore(document: navigationDocument)
let gapSlice = navigationStore.slice(atPlaybackTime: 4.5, subtitleDelay: 0)
expect(
    gapSlice.showing.isEmpty
        && gapSlice.lastShown.map(\.text) == ["second"]
        && gapSlice.nextToShow.map(\.text) == ["third"],
    "subtitle slices should expose gap context for playback modes"
)
let navigationTranscript = SubtitleTranscript(
    primary: navigationDocument,
    secondary: nil
)
expect(
    navigationTranscript.relativeRowIndex(
        atPlaybackTime: 3.25,
        subtitleDelay: 0,
        offset: -1
    ) == 0,
    "previous subtitle should select the preceding cue even after playback has entered the current cue"
)
expect(
    navigationTranscript.relativeRowIndex(
        atPlaybackTime: 3.75,
        subtitleDelay: 0.5,
        offset: -1
    ) == 0,
    "previous subtitle should resolve against subtitle-adjusted playback time"
)
expect(
    navigationTranscript.relativeRowIndex(
        atPlaybackTime: 3.25,
        subtitleDelay: 0,
        offset: 1
    ) == 2,
    "next subtitle should select the following cue"
)
expect(
    navigationTranscript.relativeRowIndex(
        atPlaybackTime: 0.5,
        subtitleDelay: 0,
        offset: -1
    ) == nil,
    "previous subtitle should not wrap before the first cue"
)

let largeDocument = SubtitleDocument(
    sourceURL: URL(fileURLWithPath: "/tmp/large.srt"),
    format: .srt,
    cues: (0..<60_000).map { index in
        let start = TimeInterval(index) * 0.5
        return SubtitleCue(
            id: "\(index)",
            startTime: start,
            endTime: start + 0.2,
            text: "cue \(index)"
        )
    } + [
        SubtitleCue(id: "long", startTime: 0, endTime: 40_000, text: "long cue")
    ],
    warnings: []
)
let largeStore = SubtitleCueStore(document: largeDocument)
expect(
    largeStore.cues(at: 29_999.05).contains { $0.id == "long" },
    "timeline queries should preserve long overlapping cues that started much earlier"
)
expectFast("large subtitle timeline queries", maxSeconds: 0.35) {
    for tick in 0..<1_500 {
        let time = 20_000 + TimeInterval(tick) * 0.01
        _ = largeStore.cues(at: time)
    }
}

let autoloadDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("hoshi-subtitle-autoload-\(UUID().uuidString)")
try FileManager.default.createDirectory(
    at: autoloadDirectory,
    withIntermediateDirectories: true
)
defer {
    try? FileManager.default.removeItem(at: autoloadDirectory)
}
let mediaURL = autoloadDirectory.appendingPathComponent("Episode 01.mkv")
let exactSRT = autoloadDirectory.appendingPathComponent("Episode 01.srt")
let exactVTT = autoloadDirectory.appendingPathComponent("Episode 01.vtt")
let exactASS = autoloadDirectory.appendingPathComponent("Episode 01.ass")
let exactSSA = autoloadDirectory.appendingPathComponent("Episode 01.ssa")
let languageSRT = autoloadDirectory.appendingPathComponent("Episode 02.ja.srt")
let languageASS = autoloadDirectory.appendingPathComponent("Episode 04.ja.ass")
let unrelatedSRT = autoloadDirectory.appendingPathComponent("Episode 03.srt")
try Data().write(to: mediaURL)
try Data().write(to: exactSRT)
try Data().write(to: exactVTT)
try Data().write(to: exactASS)
try Data().write(to: exactSSA)
try Data().write(to: languageSRT)
try Data().write(to: languageASS)
try Data().write(to: unrelatedSRT)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) == exactSRT.standardizedFileURL,
    "subtitle autoload should prefer exact same-name SRT sidecars"
)
try FileManager.default.removeItem(at: exactSRT)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) == exactVTT.standardizedFileURL,
    "subtitle autoload should fall back to exact same-name VTT sidecars"
)
try FileManager.default.removeItem(at: exactVTT)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) == exactASS.standardizedFileURL,
    "subtitle autoload should fall back to exact same-name ASS sidecars"
)
try FileManager.default.removeItem(at: exactASS)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) == exactSSA.standardizedFileURL,
    "subtitle autoload should fall back to exact same-name SSA sidecars"
)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(
        for: autoloadDirectory.appendingPathComponent("Episode 02.mp4")
    ) == languageSRT.standardizedFileURL,
    "subtitle autoload should accept language-suffixed sidecars"
)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(
        for: autoloadDirectory.appendingPathComponent("Episode 04.mp4")
    ) == languageASS.standardizedFileURL,
    "subtitle autoload should accept language-suffixed ASS sidecars"
)
expect(
    VideoSubtitleAutoloadCandidate.bestCandidate(
        for: autoloadDirectory.appendingPathComponent("No Match.mp4")
    ) == nil,
    "subtitle autoload should not pick unrelated sidecars"
)

do {
    _ = try SubtitleParser.parse(
        data: Data("not a subtitle".utf8),
        sourceURL: URL(fileURLWithPath: "/tmp/bad.srt")
    )
    fputs("FAIL: malformed subtitles should throw\n", stderr)
    exit(1)
} catch {
    // Expected.
}

let videoPlayerScreenPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Features/Video/VideoPlayerScreen.swift")
let videoPlayerScreen = try String(contentsOf: videoPlayerScreenPath, encoding: .utf8)
expect(
    videoPlayerScreen.contains("private static let subtitleFileExtensions = [\"srt\", \"vtt\", \"ass\", \"ssa\"]"),
    "player subtitle importer should allow ASS and SSA files"
)

print("Video subtitle tests passed")
}
}
