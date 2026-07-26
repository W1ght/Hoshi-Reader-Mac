//
//  ReaderChapterIndex.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum ReaderChapterIndex {
    struct FragmentOffsetSource: Sendable {
        let chapterPath: String
        let chapterURL: URL
        let fragments: Set<String>
        let expectedChapterStart: Int
        let expectedChapterCount: Int
    }

    struct ChapterRange: Equatable {
        let start: Int
        let count: Int

        func character(at globalCharacter: Int) -> Int {
            min(max(globalCharacter - start, 0), count)
        }

        func remaining(at globalCharacter: Int) -> Int {
            max(count - character(at: globalCharacter), 0)
        }
    }

    private struct Target {
        let path: String
        let fragment: String?
    }

    private static let openingTagRegex = try! NSRegularExpression(
        pattern: #"<\s*[A-Za-z][A-Za-z0-9:_-]*\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"\s([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
    )
    private static let bodyTagRegex = try! NSRegularExpression(
        pattern: #"<body\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let closingBodyTagRegex = try! NSRegularExpression(
        pattern: #"</body\s*>"#,
        options: [.caseInsensitive]
    )
    private static let ignoredTagContainerRegexes = [
        try! NSRegularExpression(pattern: #"(?s)<!--.*?-->"#),
        try! NSRegularExpression(pattern: #"(?s)<(script|style)\b[^>]*>.*?</\1\s*>"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"(?s)<!\[CDATA\[.*?\]\]>"#),
    ]

    static func fragmentsByChapterPath(in tableOfContentsItems: [String]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for item in tableOfContentsItems {
            let target = target(from: item)
            guard let fragment = target.fragment else { continue }
            result[target.path, default: []].insert(fragment)
        }
        return result
    }

    static func fragments(
        forChapterPath chapterPath: String,
        in fragmentsByPath: [String: Set<String>]
    ) -> Set<String> {
        fragmentsByPath[normalizedChapterPath(chapterPath)] ?? []
    }

    static func fragmentOffsets(
        in markup: String,
        fragments: Set<String>
    ) -> [String: Int] {
        guard !fragments.isEmpty else { return [:] }

        var offsets = Dictionary(uniqueKeysWithValues: fragments.map { ($0, 0) })
        var fragmentsByIdentifier: [String: [String]] = [:]
        for fragment in fragments {
            fragmentsByIdentifier[decodedFragmentIdentifier(fragment), default: []].append(fragment)
        }

        let fullRange = NSRange(markup.startIndex..., in: markup)
        guard let bodyMatch = bodyTagRegex.firstMatch(in: markup, range: fullRange) else {
            return offsets
        }
        let bodyStart = NSMaxRange(bodyMatch.range)
        let bodyEnd = closingBodyTagRegex.firstMatch(
            in: markup,
            range: NSRange(location: bodyStart, length: max(fullRange.length - bodyStart, 0))
        )?.range.location ?? fullRange.length
        let bodyRange = NSRange(location: bodyStart, length: max(bodyEnd - bodyStart, 0))
        let ignoredRanges = ignoredTagContainerRegexes.flatMap {
            $0.matches(in: markup, range: bodyRange).map(\.range)
        }.sorted { $0.location < $1.location }
        var ignoredRangeIndex = 0

        for match in openingTagRegex.matches(in: markup, range: bodyRange) {
            while ignoredRangeIndex < ignoredRanges.count,
                  NSMaxRange(ignoredRanges[ignoredRangeIndex]) <= match.range.location {
                ignoredRangeIndex += 1
            }
            if ignoredRangeIndex < ignoredRanges.count,
               NSLocationInRange(match.range.location, ignoredRanges[ignoredRangeIndex]) {
                continue
            }
            guard let tagRange = Range(match.range, in: markup) else { continue }
            let attributes = attributeValues(in: String(markup[tagRange]))
            guard let rawIdentifier = attributes["id"] ?? attributes["xml:id"] else {
                continue
            }
            let identifier = ReaderCharacterNormalizer.decodedCharacterReferences(in: rawIdentifier)
            guard let matchingFragments = fragmentsByIdentifier.removeValue(forKey: identifier) else {
                continue
            }
            let offset = ReaderImageGalleryIndex.readableCharacterOffset(
                in: markup,
                beforeUTF16Offset: match.range.location
            )
            for fragment in matchingFragments {
                offsets[fragment] = offset
            }
            if fragmentsByIdentifier.isEmpty {
                break
            }
        }
        return offsets
    }

    static func fragmentOffsets(
        sources: [FragmentOffsetSource],
        shouldCancel: () -> Bool = { false }
    ) -> [String: [String: Int]]? {
        var result: [String: [String: Int]] = [:]
        result.reserveCapacity(sources.count)
        for source in sources {
            guard !shouldCancel() else { return nil }
            if source.fragments.isEmpty {
                result[source.chapterPath] = [:]
                continue
            }
            guard let markup = try? String(contentsOf: source.chapterURL, encoding: .utf8) else {
                continue
            }
            guard !shouldCancel() else { return nil }
            result[source.chapterPath] = fragmentOffsets(
                in: markup,
                fragments: source.fragments
            )
        }
        return result
    }

    static func chapterStart(
        forTableOfContentsItem item: String,
        bookInfo: BookInfo
    ) -> Int? {
        let target = target(from: item)
        guard let chapter = chapterInfo(forNormalizedPath: target.path, bookInfo: bookInfo) else {
            return nil
        }
        let offset = target.fragment.flatMap { chapter.fragmentOffsets?[$0] } ?? 0
        return min(max(chapter.currentTotal + offset, chapter.currentTotal), chapter.currentTotal + chapter.chapterCount)
    }

    static func chapterStarts(
        tableOfContentsItems: [String],
        bookInfo: BookInfo
    ) -> [Int] {
        var starts: Set<Int> = [0]
        for item in tableOfContentsItems {
            if let start = chapterStart(forTableOfContentsItem: item, bookInfo: bookInfo),
               start >= 0,
               start <= bookInfo.characterCount {
                starts.insert(start)
            }
        }
        return starts.sorted()
    }

    static func chapterRange(
        containing globalCharacter: Int,
        chapterStarts: [Int],
        bookCharacterCount: Int
    ) -> ChapterRange {
        guard bookCharacterCount > 0 else {
            return ChapterRange(start: 0, count: 0)
        }

        let normalizedStarts = Array(
            Set(chapterStarts.filter { $0 >= 0 && $0 < bookCharacterCount } + [0])
        ).sorted()
        let lookupCharacter = min(max(globalCharacter, 0), bookCharacterCount - 1)
        let nextIndex = normalizedStarts.firstIndex { $0 > lookupCharacter } ?? normalizedStarts.count
        let startIndex = max(nextIndex - 1, 0)
        let start = normalizedStarts[startIndex]
        let end = nextIndex < normalizedStarts.count ? normalizedStarts[nextIndex] : bookCharacterCount
        return ChapterRange(start: start, count: max(end - start, 0))
    }

    static func normalizedChapterPath(_ rawPath: String) -> String {
        let withoutQuery = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? rawPath
        var path = withoutQuery.removingPercentEncoding ?? withoutQuery
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }

    private static func target(from item: String) -> Target {
        let parts = item.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = normalizedChapterPath(String(parts[0]))
        let fragment = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return Target(path: path, fragment: fragment)
    }

    private static func decodedFragmentIdentifier(_ fragment: String) -> String {
        let percentDecoded = fragment.removingPercentEncoding ?? fragment
        return ReaderCharacterNormalizer.decodedCharacterReferences(in: percentDecoded)
    }

    private static func chapterInfo(
        forNormalizedPath path: String,
        bookInfo: BookInfo
    ) -> BookInfo.ChapterInfo? {
        if let exact = bookInfo.chapterInfo[path] {
            return exact
        }
        return bookInfo.chapterInfo.first {
            normalizedChapterPath($0.key) == path
        }?.value
    }

    private static func attributeValues(in tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in attributeRegex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()
            guard attributes[name] == nil else { continue }
            for captureIndex in 2...3 {
                let captureRange = match.range(at: captureIndex)
                guard captureRange.location != NSNotFound,
                      let valueRange = Range(captureRange, in: tag) else {
                    continue
                }
                attributes[name] = String(tag[valueRange])
                break
            }
        }
        return attributes
    }
}
