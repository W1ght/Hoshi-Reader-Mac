import Foundation

nonisolated struct ReaderSearchResult: Equatable, Identifiable, Sendable {
    let id = UUID()
    let chapterIndex: Int
    let chapterLabel: String
    let character: Int
    let snippet: String
    let snippetMatchStart: Int
    let snippetMatchEnd: Int
}

nonisolated struct ReaderSearchChapter: Equatable, Sendable {
    let index: Int
    let path: String
    let currentTotal: Int
    let characterCount: Int
}

nonisolated struct ReaderSearchDocument: Sendable {
    let chapters: [ReaderSearchChapter]
    let htmlByPath: [String: String]
    let labels: [Int: String]

    init(
        chapters: [ReaderSearchChapter],
        htmlByPath: [String: String],
        labels: [Int: String] = [:]
    ) {
        self.chapters = chapters
        self.htmlByPath = htmlByPath
        self.labels = labels
    }
}

nonisolated final class ReaderSearchEngine {
    private let document: ReaderSearchDocument
    private lazy var index = ReaderSearchIndex(document: document)

    init(document: ReaderSearchDocument) {
        self.document = document
    }

    func search(_ query: String, maxResults: Int = 1_000) -> [ReaderSearchResult] {
        let normalizedQuery = ReaderSearchTextFilter.filteredSearchText(query)
        guard !normalizedQuery.isEmpty, maxResults > 0 else { return [] }

        var results: [ReaderSearchResult] = []
        let queryLength = normalizedQuery.count
        var fromIndex = index.searchText.startIndex

        while fromIndex <= index.searchText.endIndex, results.count < maxResults {
            guard let matchRange = index.searchText.range(
                of: normalizedQuery,
                options: [.caseInsensitive],
                range: fromIndex..<index.searchText.endIndex
            ) else {
                break
            }

            let searchStart = index.searchText.distance(from: index.searchText.startIndex, to: matchRange.lowerBound)
            let searchEnd = searchStart + queryLength
            if let chapter = index.chapter(containingSearchRange: searchStart..<searchEnd) {
                results.append(index.result(for: chapter, searchStart: searchStart, queryLength: queryLength))
                fromIndex = matchRange.upperBound
            } else {
                fromIndex = index.searchText.index(after: matchRange.lowerBound)
            }
        }

        return results
    }
}

nonisolated private struct ReaderSearchIndex {
    let searchText: String
    private let displayText: String
    private let searchToDisplayOffsets: [Int]
    private let chapters: [ReaderSearchChapterRange]
    private let labels: [Int: String]

    init(document: ReaderSearchDocument) {
        var builder = ReaderSearchDocumentBuilder()
        var ranges: [ReaderSearchChapterRange] = []

        for chapter in document.chapters {
            let html = document.htmlByPath[chapter.path] ?? ""
            let bounds = builder.appendChapter(html: html)
            ranges.append(
                ReaderSearchChapterRange(
                    index: chapter.index,
                    currentTotal: chapter.currentTotal,
                    startSearchCharacter: bounds.startSearchCharacter,
                    endSearchCharacter: bounds.endSearchCharacter,
                    startDisplayCharacter: bounds.startDisplayCharacter,
                    endDisplayCharacter: bounds.endDisplayCharacter
                )
            )
        }

        self.searchText = builder.searchText
        self.displayText = builder.displayText
        self.searchToDisplayOffsets = builder.searchToDisplayOffsets
        self.chapters = ranges
        self.labels = document.labels
    }

    func chapter(containingSearchRange range: Range<Int>) -> ReaderSearchChapterRange? {
        chapters.first { chapter in
            range.lowerBound >= chapter.startSearchCharacter && range.upperBound <= chapter.endSearchCharacter
        }
    }

    func result(for chapter: ReaderSearchChapterRange, searchStart: Int, queryLength: Int) -> ReaderSearchResult {
        let displayMatchStart = searchToDisplayOffsets[searchStart]
        let displayMatchEnd = searchToDisplayOffsets[searchStart + queryLength - 1] + 1
        let snippetStart = max(chapter.startDisplayCharacter, displayMatchStart - Self.snippetLeadingCharacters)
        let snippetEnd = min(chapter.endDisplayCharacter, displayMatchEnd + Self.snippetTrailingCharacters)
        let hasPrefix = snippetStart > chapter.startDisplayCharacter
        let hasSuffix = snippetEnd < chapter.endDisplayCharacter
        let displayCharacters = Array(displayText)
        let prefix = hasPrefix ? "..." : ""
        let suffix = hasSuffix ? "..." : ""
        let body = String(displayCharacters[snippetStart..<snippetEnd])
        let snippet = prefix + body + suffix
        let matchStart = prefix.count + displayMatchStart - snippetStart

        return ReaderSearchResult(
            chapterIndex: chapter.index,
            chapterLabel: label(for: chapter.index),
            character: chapter.currentTotal + searchStart - chapter.startSearchCharacter,
            snippet: snippet,
            snippetMatchStart: matchStart,
            snippetMatchEnd: matchStart + displayMatchEnd - displayMatchStart
        )
    }

    private func label(for chapterIndex: Int) -> String {
        var index = chapterIndex
        while index > 0, labels[index] == nil {
            index -= 1
        }
        return labels[index] ?? ""
    }

    private static let snippetLeadingCharacters = 24
    private static let snippetTrailingCharacters = 48
}

nonisolated private struct ReaderSearchChapterRange {
    let index: Int
    let currentTotal: Int
    let startSearchCharacter: Int
    let endSearchCharacter: Int
    let startDisplayCharacter: Int
    let endDisplayCharacter: Int
}

nonisolated private struct ReaderSearchChapterBounds {
    let startSearchCharacter: Int
    let endSearchCharacter: Int
    let startDisplayCharacter: Int
    let endDisplayCharacter: Int
}

nonisolated private struct ReaderSearchDocumentBuilder {
    private(set) var searchText = ""
    private(set) var displayText = ""
    private(set) var searchToDisplayOffsets: [Int] = []
    private var searchCharacterCount = 0
    private var displayCharacterCount = 0

    mutating func appendChapter(html: String) -> ReaderSearchChapterBounds {
        let startSearchCharacter = searchCharacterCount
        let startDisplayCharacter = displayCharacterCount
        var hasDisplayContent = false
        var pendingWhitespace = false

        for character in ReaderSearchTextFilter.visibleText(html) {
            if character.isWhitespace {
                if hasDisplayContent {
                    pendingWhitespace = true
                }
                continue
            }

            if pendingWhitespace {
                appendDisplayCharacter(" ")
                pendingWhitespace = false
            }

            hasDisplayContent = true
            let displayOffset = displayCharacterCount
            appendDisplayCharacter(character)
            if character.isReaderSearchMatchable {
                searchText.append(character)
                searchToDisplayOffsets.append(displayOffset)
                searchCharacterCount += 1
            }
        }

        return ReaderSearchChapterBounds(
            startSearchCharacter: startSearchCharacter,
            endSearchCharacter: searchCharacterCount,
            startDisplayCharacter: startDisplayCharacter,
            endDisplayCharacter: displayCharacterCount
        )
    }

    private mutating func appendDisplayCharacter(_ character: Character) {
        displayText.append(character)
        displayCharacterCount += 1
    }
}

nonisolated enum ReaderSearchTextFilter {
    static func hasMatchableText(_ value: String) -> Bool {
        !filteredSearchText(value).isEmpty
    }

    static func filteredSearchText(_ value: String) -> String {
        String(visibleText(value).filter(\.isReaderSearchMatchable))
    }

    static func visibleText(_ html: String) -> String {
        var text = firstMatch(in: html, pattern: #"(?s)<body[^>]*>.*?</body>"#) ?? html
        text = replace(pattern: #"(?s)<rt[^>]*>.*?</rt>"#, in: text, with: "")
        text = replace(pattern: #"(?s)<(script|style)[^>]*>.*?</\1>"#, in: text, with: "")
        text = replace(pattern: #"<[^>]+>"#, in: text, with: "")
        return decodeHTMLEntities(text)
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range, in: string) else { return nil }
        return String(string[range])
    }

    private static func replace(pattern: String, in string: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return string
        }
        return regex.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

private extension Character {
    nonisolated var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    nonisolated var isReaderSearchMatchable: Bool {
        unicodeScalars.contains { scalar in
            scalar.isReaderSearchMatchable
        }
    }
}

private extension UnicodeScalar {
    nonisolated var isReaderSearchMatchable: Bool {
        switch value {
        case 0x30...0x39,
             0x41...0x5A,
             0x61...0x7A,
             0x25CB,
             0x3005...0x3007,
             0x303B,
             0x3041...0x3096,
             0x309D...0x309E,
             0x30A1...0x30FA,
             0x30FC,
             0xFF10...0xFF19,
             0xFF21...0xFF3A,
             0xFF41...0xFF5A,
             0xFF66...0xFF9D,
             0x2E80...0x2FDF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x30000...0x3134F,
             0x31350...0x323AF:
            true
        default:
            false
        }
    }
}
