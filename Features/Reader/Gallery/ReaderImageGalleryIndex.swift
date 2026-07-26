//
//  ReaderImageGalleryIndex.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum ReaderImageGalleryIndex {
    struct Entry: Equatable {
        let path: String
        let characterOffset: Int
    }

    private static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png"]
    private static let imageTagRegex = try! NSRegularExpression(
        pattern: #"<\s*(img|image)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"\s([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
    )
    private static let bodyTagRegex = try! NSRegularExpression(
        pattern: #"<body\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let bodyContentRegex = try! NSRegularExpression(
        pattern: #"(?s)<body.*?</body>"#
    )
    private static let ignoredMarkupRegexes = [
        try! NSRegularExpression(pattern: #"(?s)<rt[^>]*>.*?</rt>"#),
        try! NSRegularExpression(pattern: #"(?s)<(script|style)[^>]*>.*?</\1>"#),
        try! NSRegularExpression(pattern: #"<[^>]+>"#),
        try! NSRegularExpression(pattern: #"&(nbsp|amp|lt|gt);"#),
    ]
    static func imagePaths(
        in markup: String,
        chapterURL: URL,
        contentDirectory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        imageEntries(
            in: markup,
            chapterURL: chapterURL,
            contentDirectory: contentDirectory,
            fileManager: fileManager
        ).map(\.path)
    }

    static func readableCharacterCount(in markup: String) -> Int {
        let range = NSRange(markup.startIndex..., in: markup)
        let end = bodyContentRegex.firstMatch(in: markup, range: range)
            .map { NSMaxRange($0.range) }
            ?? range.length
        var characterCounter = ReadableCharacterCounter(markup: markup, range: range)
        return characterCounter.offset(before: end)
    }

    static func readableCharacterOffset(in markup: String, beforeUTF16Offset: Int) -> Int {
        let range = NSRange(markup.startIndex..., in: markup)
        var characterCounter = ReadableCharacterCounter(markup: markup, range: range)
        return characterCounter.offset(before: beforeUTF16Offset)
    }

    static func imageEntries(
        in markup: String,
        chapterURL: URL,
        contentDirectory: URL,
        fileManager: FileManager = .default,
        shouldCancel: () -> Bool = { false }
    ) -> [Entry] {
        let range = NSRange(markup.startIndex..., in: markup)
        var seenPaths: Set<String> = []
        var entries: [Entry] = []
        var characterCounter = ReadableCharacterCounter(markup: markup, range: range)
        let rootPath = canonicalRootPath(contentDirectory)
        for match in imageTagRegex.matches(in: markup, range: range) {
            guard !shouldCancel() else { return [] }
            let characterOffset = characterCounter.offset(before: match.range(at: 0).location)
            guard let tagRange = Range(match.range(at: 0), in: markup),
                  let nameRange = Range(match.range(at: 1), in: markup) else {
                continue
            }

            let tag = String(markup[tagRange])
            let tagName = String(markup[nameRange]).lowercased()
            let attributes = attributeValues(in: tag)
            if let className = attributes["class"],
               className.split(whereSeparator: \Character.isWhitespace).contains(where: {
                   $0.caseInsensitiveCompare("gaiji") == .orderedSame
               }) {
                continue
            }

            let reference: String?
            if tagName == "img" {
                reference = attributes["src"]
            } else {
                reference = attributes["xlink:href"] ?? attributes["href"]
            }
            guard let reference,
                  let imageURL = resolvedImageURL(
                      for: reference,
                      relativeTo: chapterURL.deletingLastPathComponent(),
                      rootPath: rootPath,
                      fileManager: fileManager
                  ) else {
                continue
            }
            guard let path = relativePath(for: imageURL, rootPath: rootPath),
                  seenPaths.insert(path).inserted else {
                continue
            }
            entries.append(Entry(path: path, characterOffset: characterOffset))
        }
        return entries
    }

    static func resolvedImageURL(
        for reference: String,
        relativeTo baseURL: URL,
        contentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        resolvedImageURL(
            for: reference,
            relativeTo: baseURL,
            rootPath: canonicalRootPath(contentDirectory),
            fileManager: fileManager
        )
    }

    private static func resolvedImageURL(
        for reference: String,
        relativeTo baseURL: URL,
        rootPath: String,
        fileManager: FileManager
    ) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme == nil,
              components.host == nil else {
            return nil
        }

        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        guard !decodedPath.isEmpty, !decodedPath.hasPrefix("/") else {
            return nil
        }

        return validatedImageURL(
            path: decodedPath,
            relativeTo: baseURL,
            rootPath: rootPath,
            fileManager: fileManager
        )
    }

    static func resolvedStoredImageURL(
        for relativePath: String,
        contentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        resolvedStoredImageURL(
            for: relativePath,
            contentDirectory: contentDirectory,
            rootPath: canonicalRootPath(contentDirectory),
            fileManager: fileManager
        )
    }

    private static func resolvedStoredImageURL(
        for relativePath: String,
        contentDirectory: URL,
        rootPath: String,
        fileManager: FileManager
    ) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            return nil
        }
        return validatedImageURL(
            path: trimmed,
            relativeTo: contentDirectory,
            rootPath: rootPath,
            fileManager: fileManager
        )
    }

    static func resolvedStoredImageURLs(
        for relativePaths: [String],
        contentDirectory: URL,
        fileManager: FileManager = .default,
        shouldCancel: () -> Bool = { false }
    ) -> [String: URL]? {
        var result: [String: URL] = [:]
        var seenPaths: Set<String> = []
        result.reserveCapacity(relativePaths.count)
        seenPaths.reserveCapacity(relativePaths.count)
        let rootPath = canonicalRootPath(contentDirectory)
        for relativePath in relativePaths where seenPaths.insert(relativePath).inserted {
            guard !shouldCancel() else { return nil }
            if let url = resolvedStoredImageURL(
                for: relativePath,
                contentDirectory: contentDirectory,
                rootPath: rootPath,
                fileManager: fileManager
            ) {
                result[relativePath] = url
            }
        }
        return result
    }

    private static func validatedImageURL(
        path: String,
        relativeTo baseURL: URL,
        rootPath: String,
        fileManager: FileManager
    ) -> URL? {
        let imageURL = URL(fileURLWithPath: path, relativeTo: baseURL)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let imagePath = imageURL.path(percentEncoded: false)
        guard supportedExtensions.contains(imageURL.pathExtension.lowercased()),
              imagePath.hasPrefix(rootPath + "/") else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: imagePath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return imageURL
    }

    private static func relativePath(for imageURL: URL, rootPath: String) -> String? {
        let imagePath = imageURL.path(percentEncoded: false)
        guard imagePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(imagePath.dropFirst(rootPath.count + 1))
    }

    private static func canonicalRootPath(_ contentDirectory: URL) -> String {
        normalizedDirectoryPath(contentDirectory.standardizedFileURL.resolvingSymlinksInPath())
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private struct ReadableCharacterCounter {
        private let markup: String
        private let ignoredRanges: [NSRange]
        private let bodyStart: Int?
        private var ignoredRangeIndex = 0
        private var cursor = 0
        private var count = 0
        private var didEnterBody = false

        init(markup: String, range: NSRange) {
            self.markup = markup
            ignoredRanges = Self.mergedIgnoredRanges(in: markup, range: range)
            bodyStart = bodyTagRegex.firstMatch(in: markup, range: range).map {
                NSMaxRange($0.range)
            }
        }

        mutating func offset(before utf16Offset: Int) -> Int {
            let safeOffset = min(max(utf16Offset, 0), (markup as NSString).length)
            if let bodyStart, safeOffset >= bodyStart, !didEnterBody {
                didEnterBody = true
                cursor = bodyStart
                count = 0
                ignoredRangeIndex = ignoredRanges.firstIndex {
                    NSMaxRange($0) > bodyStart
                } ?? ignoredRanges.endIndex
            }
            guard safeOffset > cursor else { return count }

            let end = safeOffset
            while ignoredRangeIndex < ignoredRanges.endIndex,
                  NSMaxRange(ignoredRanges[ignoredRangeIndex]) <= cursor {
                ignoredRangeIndex += 1
            }

            while ignoredRangeIndex < ignoredRanges.endIndex {
                let ignoredRange = ignoredRanges[ignoredRangeIndex]
                guard ignoredRange.location < end else { break }
                if ignoredRange.location > cursor {
                    count += readableCharacterCount(
                        in: NSRange(
                            location: cursor,
                            length: min(ignoredRange.location, end) - cursor
                        )
                    )
                }
                if NSMaxRange(ignoredRange) >= end {
                    cursor = end
                    break
                }
                cursor = max(cursor, NSMaxRange(ignoredRange))
                ignoredRangeIndex += 1
            }

            if cursor < end {
                count += readableCharacterCount(
                    in: NSRange(location: cursor, length: end - cursor)
                )
                cursor = end
            }
            return count
        }

        private func readableCharacterCount(in range: NSRange) -> Int {
            ReaderCharacterNormalizer.readableCharacterCount(
                in: (markup as NSString).substring(with: range)
            )
        }

        private static func mergedIgnoredRanges(in markup: String, range: NSRange) -> [NSRange] {
            var ranges: [NSRange] = []
            for regex in ignoredMarkupRegexes {
                ranges.append(contentsOf: regex.matches(in: markup, range: range).map { $0.range })
            }
            ranges.sort {
                $0.location == $1.location
                    ? $0.length < $1.length
                    : $0.location < $1.location
            }
            guard var current = ranges.first else { return [] }
            var merged: [NSRange] = []
            for next in ranges.dropFirst() {
                if next.location <= NSMaxRange(current) {
                    current.length = max(NSMaxRange(current), NSMaxRange(next)) - current.location
                } else {
                    merged.append(current)
                    current = next
                }
            }
            merged.append(current)
            return merged
        }
    }

    private static func attributeValues(in tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in attributeRegex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()
            guard attributes[name] == nil else { continue }
            for captureIndex in 2...3 {
                let matchRange = match.range(at: captureIndex)
                guard matchRange.location != NSNotFound,
                      let valueRange = Range(matchRange, in: tag) else {
                    continue
                }
                attributes[name] = String(tag[valueRange])
                break
            }
        }
        return attributes
    }
}
