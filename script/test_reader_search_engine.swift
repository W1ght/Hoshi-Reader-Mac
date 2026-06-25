import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let source = root.appendingPathComponent("Features/Reader/Search/ReaderSearchEngine.swift")
let harness = URL(fileURLWithPath: "/tmp/test_reader_search_engine_harness.swift")
let binary = URL(fileURLWithPath: "/tmp/test_reader_search_engine")

let harnessSource = #"""
import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

private func assertTrue(_ condition: Bool, _ message: String) {
    guard condition else {
        fatalError(message)
    }
}

private func searchDocument(
    chapters: [ReaderSearchChapter],
    htmlByPath: [String: String],
    labels: [Int: String] = [:]
) -> ReaderSearchDocument {
    ReaderSearchDocument(chapters: chapters, htmlByPath: htmlByPath, labels: labels)
}

private func chapter(
    index: Int,
    path: String,
    currentTotal: Int,
    characterCount: Int
) -> ReaderSearchChapter {
    ReaderSearchChapter(
        index: index,
        path: path,
        currentTotal: currentTotal,
        characterCount: characterCount
    )
}

private extension ReaderSearchResult {
    var highlightedText: String {
        String(snippet.codePointSlice(from: snippetMatchStart, to: snippetMatchEnd))
    }
}

private extension Array {
    func single(file: StaticString = #file, line: UInt = #line) -> Element {
        guard count == 1, let element = first else {
            fatalError("expected exactly one element, got \(count)", file: file, line: line)
        }
        return element
    }
}

private extension String {
    func codePointSlice(from start: Int, to end: Int) -> Substring {
        let lower = index(startIndex, offsetBy: max(0, start), limitedBy: endIndex) ?? endIndex
        let upper = index(startIndex, offsetBy: max(0, end), limitedBy: endIndex) ?? endIndex
        return self[lower..<upper]
    }
}

private func testSearchReadsChapterHTMLAndIgnoresRubyScriptsAndStyles() {
    let document = searchDocument(
        chapters: [
            chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 3),
            chapter(index: 1, path: "c1.xhtml", currentTotal: 3, characterCount: 3)
        ],
        htmlByPath: [
            "c0.xhtml": "<html><body><ruby>漢<rt>かん</rt></ruby>字 A<script>bad</script><style>bad</style></body></html>",
            "c1.xhtml": "<html><body>猫と犬</body></html>"
        ],
        labels: [0: "First", 1: "Second"]
    )

    let result = ReaderSearchEngine(document: document).search("漢字A").single()

    assertEqual(result.chapterIndex, 0, "ruby/script result chapter")
    assertEqual(result.chapterLabel, "First", "chapter label")
    assertEqual(result.character, 0, "ruby/script result character")
    assertTrue(result.snippet.contains("漢字 A"), "display snippet keeps visible spacing")
    assertTrue(!result.snippet.contains("かん"), "snippet excludes ruby text")
    assertTrue(!result.snippet.contains("bad"), "snippet excludes script/style text")
}

private func testPunctuationInsensitiveSearchKeepsDisplayPunctuation() {
    let document = searchDocument(
        chapters: [chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 7)],
        htmlByPath: ["c0.xhtml": "<html><body>吾輩は「猫、です。」犬</body></html>"]
    )

    let result = ReaderSearchEngine(document: document).search("猫!です").single()

    assertEqual(result.character, 3, "punctuation-insensitive character")
    assertTrue(result.snippet.contains("「猫、です。」"), "snippet keeps punctuation")
    assertEqual(result.highlightedText, "猫、です", "highlight spans display punctuation between match characters")
}

private func testHTMLDecodingAndNonBMPDisplayOffsets() {
    let document = searchDocument(
        chapters: [chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 4)],
        htmlByPath: ["c0.xhtml": "<html><body>A🙂B&amp;C</body></html>"]
    )

    let emojiResult = ReaderSearchEngine(document: document).search("AB").single()
    let entityResult = ReaderSearchEngine(document: document).search("BC").single()

    assertEqual(emojiResult.snippet, "A🙂B&C", "snippet keeps non-BMP code point")
    assertEqual(emojiResult.highlightedText, "A🙂B", "highlight crosses emoji display code point")
    assertEqual(entityResult.highlightedText, "B&C", "common HTML entity decodes before matching")
}

private func testLatinSearchIsCaseInsensitiveAndEmptyQueriesDoNotMatch() {
    let document = searchDocument(
        chapters: [chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 6)],
        htmlByPath: ["c0.xhtml": "<html><body>CATcat</body></html>"]
    )
    let engine = ReaderSearchEngine(document: document)

    assertEqual(engine.search("cat").map(\.character), [0, 3], "latin search ignores case")
    assertEqual(engine.search("").count, 0, "empty query has no results")
    assertEqual(engine.search(" ! ").count, 0, "punctuation-only query has no results")
}

private func testCrossChapterMatchesAreRejectedWithoutSkippingNextChapter() {
    let document = searchDocument(
        chapters: [
            chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 2),
            chapter(index: 1, path: "c1.xhtml", currentTotal: 2, characterCount: 2)
        ],
        htmlByPath: [
            "c0.xhtml": "<html><body>ab</body></html>",
            "c1.xhtml": "<html><body>bc</body></html>"
        ]
    )

    let results = ReaderSearchEngine(document: document).search("bc")

    assertEqual(results.map(\.character), [2], "cross-chapter match is rejected while next chapter match remains")
    assertEqual(results.map(\.chapterIndex), [1], "next chapter result uses next chapter index")
}

private func testResultLimitAndFallbackChapterLabels() {
    let document = searchDocument(
        chapters: [
            chapter(index: 0, path: "c0.xhtml", currentTotal: 0, characterCount: 3),
            chapter(index: 1, path: "c1.xhtml", currentTotal: 3, characterCount: 3)
        ],
        htmlByPath: [
            "c0.xhtml": "<html><body>猫猫猫</body></html>",
            "c1.xhtml": "<html><body>猫猫猫</body></html>"
        ],
        labels: [0: "Top"]
    )

    let limited = ReaderSearchEngine(document: document).search("猫", maxResults: 4)

    assertEqual(limited.count, 4, "max result limit")
    assertEqual(limited.map(\.chapterLabel), ["Top", "Top", "Top", "Top"], "chapter label falls back to nearest previous label")
}

@main
private enum ReaderSearchEngineTestRunner {
    static func main() {
        testSearchReadsChapterHTMLAndIgnoresRubyScriptsAndStyles()
        testPunctuationInsensitiveSearchKeepsDisplayPunctuation()
        testHTMLDecodingAndNonBMPDisplayOffsets()
        testLatinSearchIsCaseInsensitiveAndEmptyQueriesDoNotMatch()
        testCrossChapterMatchesAreRejectedWithoutSkippingNextChapter()
        testResultLimitAndFallbackChapterLabels()

        print("ReaderSearchEngine tests passed")
    }
}
"""#

try harnessSource.write(to: harness, atomically: true, encoding: .utf8)

func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

let compileStatus = try run(
    "/usr/bin/xcrun",
    [
        "swiftc",
        "-parse-as-library",
        source.path,
        harness.path,
        "-o",
        binary.path
    ]
)
guard compileStatus == 0 else {
    exit(compileStatus)
}

let testStatus = try run(binary.path, [])
exit(testStatus)
