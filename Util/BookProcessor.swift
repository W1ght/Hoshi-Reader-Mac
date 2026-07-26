//
//  BookProcessor.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation

struct BookProcessor {
    nonisolated struct ImageIndex: Sendable {
        let paths: [String]
        let positions: [String: Int]
    }

    nonisolated struct ImageIndexSource: Sendable {
        let chapterURL: URL
        let contentDirectory: URL
        let storedChapterStart: Int?
        let storedChapterCount: Int?
    }

    static func process(document: EPUBDocument) -> BookInfo {
        var chapterInfo: [String: BookInfo.ChapterInfo] = [:]
        var total = 0
        let fragmentsByPath = ReaderChapterIndex.fragmentsByChapterPath(
            in: tableOfContentsItemPaths(in: document.tableOfContents)
        )
        for (index, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            let path = document.contentDirectory.appendingPathComponent(manifestItem.path)
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                let count = content.filtered().count
                let fragments = ReaderChapterIndex.fragments(
                    forChapterPath: manifestItem.path,
                    in: fragmentsByPath
                )
                chapterInfo[manifestItem.path] = BookInfo.ChapterInfo(
                    spineIndex: index,
                    currentTotal: total,
                    chapterCount: count,
                    fragmentOffsets: ReaderChapterIndex.fragmentOffsets(
                        in: content,
                        fragments: fragments
                    )
                )
                total += count
            }
        }
        // Import keeps its existing synchronous character-statistics pass.
        // NativeReaderModel fills the optional Gallery fields through its
        // cancellable utility-priority backfill after the copied book opens.
        return BookInfo(characterCount: total, chapterInfo: chapterInfo)
    }

    static func tableOfContentsItemPaths(in tableOfContents: EPUBTableOfContents) -> [String] {
        var paths: [String] = []
        func walk(_ node: EPUBTableOfContents) {
            if let item = node.item {
                paths.append(item)
            }
            node.subTable?.forEach(walk)
        }
        walk(tableOfContents)
        return paths
    }

    static func fragmentOffsetSources(
        document: EPUBDocument,
        chapterInfo: [String: BookInfo.ChapterInfo]
    ) -> [ReaderChapterIndex.FragmentOffsetSource] {
        let fragmentsByPath = ReaderChapterIndex.fragmentsByChapterPath(
            in: tableOfContentsItemPaths(in: document.tableOfContents)
        )
        return document.spine.items.compactMap { item -> ReaderChapterIndex.FragmentOffsetSource? in
            guard let manifestItem = document.manifest.items[item.idref],
                  let storedChapter = chapterInfo[manifestItem.path] else {
                return nil
            }
            let expectedFragments = ReaderChapterIndex.fragments(
                forChapterPath: manifestItem.path,
                in: fragmentsByPath
            )
            let storedFragments = Set(storedChapter.fragmentOffsets?.keys.map { $0 } ?? [])
            let missingFragments = expectedFragments.subtracting(storedFragments)
            guard storedChapter.fragmentOffsets == nil || !missingFragments.isEmpty else {
                return nil
            }
            return ReaderChapterIndex.FragmentOffsetSource(
                chapterPath: manifestItem.path,
                chapterURL: document.contentDirectory.appendingPathComponent(manifestItem.path),
                fragments: missingFragments,
                expectedChapterStart: storedChapter.currentTotal,
                expectedChapterCount: storedChapter.chapterCount
            )
        }
    }

    static func imagePaths(document: EPUBDocument) -> [String] {
        imageIndex(document: document).paths
    }

    static func imageIndex(
        document: EPUBDocument,
        chapterInfo: [String: BookInfo.ChapterInfo] = [:]
    ) -> ImageIndex {
        imageIndex(sources: imageIndexSources(document: document, chapterInfo: chapterInfo))
            ?? ImageIndex(paths: [], positions: [:])
    }

    static func imageIndexSources(
        document: EPUBDocument,
        chapterInfo: [String: BookInfo.ChapterInfo] = [:]
    ) -> [ImageIndexSource] {
        document.spine.items.compactMap { item in
            guard let manifestItem = document.manifest.items[item.idref] else {
                return nil
            }
            let storedChapter = chapterInfo[manifestItem.path]
            return ImageIndexSource(
                chapterURL: document.contentDirectory.appendingPathComponent(manifestItem.path),
                contentDirectory: document.contentDirectory,
                storedChapterStart: storedChapter?.currentTotal,
                storedChapterCount: storedChapter?.chapterCount
            )
        }
    }

    nonisolated static func imageIndex(sources: [ImageIndexSource]) -> ImageIndex? {
        var images: [String] = []
        var imagePositions: [String: Int] = [:]
        var seenImages: Set<String> = []
        var fallbackTotal = 0
        for source in sources {
            guard !Task.isCancelled else { return nil }
            guard let content = try? String(contentsOf: source.chapterURL, encoding: .utf8) else {
                continue
            }
            guard !Task.isCancelled else { return nil }
            let chapterCount = source.storedChapterCount
                ?? ReaderImageGalleryIndex.readableCharacterCount(in: content)
            guard appendImages(
                from: content,
                chapterURL: source.chapterURL,
                contentDirectory: source.contentDirectory,
                chapterStart: source.storedChapterStart ?? fallbackTotal,
                chapterCount: chapterCount,
                images: &images,
                imagePositions: &imagePositions,
                seenImages: &seenImages,
                shouldCancel: { Task.isCancelled }
            ) else { return nil }
            fallbackTotal += chapterCount
        }
        return ImageIndex(paths: images, positions: imagePositions)
    }

    private nonisolated static func appendImages(
        from content: String,
        chapterURL: URL,
        contentDirectory: URL,
        chapterStart: Int,
        chapterCount: Int,
        images: inout [String],
        imagePositions: inout [String: Int],
        seenImages: inout Set<String>,
        shouldCancel: () -> Bool = { false }
    ) -> Bool {
        let entries = ReaderImageGalleryIndex.imageEntries(
            in: content,
            chapterURL: chapterURL,
            contentDirectory: contentDirectory,
            shouldCancel: shouldCancel
        )
        guard !shouldCancel() else { return false }
        for entry in entries where seenImages.insert(entry.path).inserted {
            images.append(entry.path)
            imagePositions[entry.path] = chapterStart + min(entry.characterOffset, chapterCount)
        }
        return true
    }
}
