//
//  SasayakiAudiobookMetadata.swift
//  Niratan
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Foundation

enum SasayakiAudiobookMetadataLoader {
    static func loadMetadata(from asset: AVAsset) async -> SasayakiAudiobookMetadata {
        let items = (try? await asset.load(.commonMetadata)) ?? []
        let nativeMetadata = SasayakiAudiobookMetadata(
            title: await stringValue(for: .commonKeyTitle, in: items),
            artist: await stringValue(for: .commonKeyArtist, in: items),
            artworkData: await dataValue(for: .commonKeyArtwork, in: items)
        )
        guard nativeMetadata.title == nil
                || nativeMetadata.artist == nil
                || nativeMetadata.artworkData == nil,
              let fallbackURL = (asset as? AVURLAsset)?.url else {
            return nativeMetadata
        }

        let fallbackMetadata = await Task.detached(priority: .userInitiated) {
            SasayakiMP4MetadataParser.parse(url: fallbackURL)
        }.value
        return SasayakiAudiobookMetadata(
            title: nativeMetadata.title ?? fallbackMetadata.title,
            artist: nativeMetadata.artist ?? fallbackMetadata.artist,
            artworkData: nativeMetadata.artworkData ?? fallbackMetadata.artworkData
        )
    }

    static func loadChapters(from asset: AVAsset, fallbackURL: URL) async -> [SasayakiAudiobookChapter] {
        let nativeChapters = await loadNativeChapters(from: asset)
        if !nativeChapters.isEmpty {
            return nativeChapters
        }

        return await Task.detached(priority: .userInitiated) {
            SasayakiMP4ChapterParser.parse(url: fallbackURL)
        }.value
    }

    private static func loadNativeChapters(from asset: AVAsset) async -> [SasayakiAudiobookChapter] {
        guard let groups = try? await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: Locale.preferredLanguages
        ) else { return [] }

        var chapters: [SasayakiAudiobookChapter] = []
        chapters.reserveCapacity(groups.count)
        for (index, group) in groups.enumerated() {
            guard !Task.isCancelled else { return [] }
            let startTime = group.timeRange.start.seconds
            guard startTime.isFinite, startTime >= 0 else { continue }

            let titleItem = group.items.first { $0.commonKey == .commonKeyTitle }
            let loadedTitle: String?
            if let titleItem {
                loadedTitle = try? await titleItem.load(.stringValue)
            } else {
                loadedTitle = nil
            }
            let title = normalized(loadedTitle)
                ?? String.localizedStringWithFormat(String(localized: "Chapter %d"), index + 1)
            let rawEndTime = group.timeRange.end.seconds
            let endTime = rawEndTime.isFinite && rawEndTime > startTime ? rawEndTime : nil
            chapters.append(
                SasayakiAudiobookChapter(
                    id: index,
                    title: title,
                    startTime: startTime,
                    endTime: endTime
                )
            )
        }
        return chapters.sorted { $0.startTime < $1.startTime }
    }

    private static func stringValue(
        for key: AVMetadataKey,
        in items: [AVMetadataItem]
    ) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return normalized(try? await item.load(.stringValue))
    }

    private static func dataValue(
        for key: AVMetadataKey,
        in items: [AVMetadataItem]
    ) async -> Data? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.dataValue)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum SasayakiMP4MetadataParser {
    nonisolated static func parse(url: URL) -> SasayakiAudiobookMetadata {
        guard let reader = try? MP4MetadataReader(url: url) else { return .empty }
        return (try? reader.read()) ?? .empty
    }
}

enum SasayakiMP4ChapterParser {
    nonisolated static func parse(url: URL) -> [SasayakiAudiobookChapter] {
        guard let reader = try? MP4ChapterReader(url: url) else { return [] }
        return (try? reader.read()) ?? []
    }
}

private final class MP4ChapterReader: @unchecked Sendable {
    private let handle: FileHandle
    private let fileSize: UInt64

    nonisolated init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        fileSize = try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    nonisolated func read() throws -> [SasayakiAudiobookChapter] {
        guard let moov = try childBox(start: 0, end: fileSize, type: "moov") else { return [] }
        let movieDuration = try childBox(in: moov, type: "mvhd").flatMap(readMovieDuration)
        let udta = try childBox(in: moov, type: "udta")
        let chapterBox = try udta.flatMap { try childBox(in: $0, type: "chpl") }
            ?? childBox(in: moov, type: "chpl")
        guard let chapterBox else { return [] }

        let rawChapters = try readChapterList(chapterBox)
            .sorted { $0.startTime < $1.startTime }
        return rawChapters.enumerated().map { index, chapter in
            SasayakiAudiobookChapter(
                id: index,
                title: chapter.title.isEmpty
                    ? String.localizedStringWithFormat(String(localized: "Chapter %d"), index + 1)
                    : chapter.title,
                startTime: chapter.startTime,
                endTime: rawChapters.indices.contains(index + 1)
                    ? rawChapters[index + 1].startTime
                    : movieDuration.flatMap { $0 >= chapter.startTime ? $0 : nil }
            )
        }
    }

    nonisolated private func readMovieDuration(_ box: MP4Box) throws -> Double? {
        let version = try readUInt8(at: box.contentStart)
        switch version {
        case 0:
            let timescale = try readUInt32(at: box.contentStart + 12)
            let duration = try readUInt32(at: box.contentStart + 16)
            return seconds(duration: duration, timescale: timescale)
        case 1:
            let timescale = try readUInt32(at: box.contentStart + 20)
            let duration = try readUInt64(at: box.contentStart + 24)
            return seconds(duration: duration, timescale: timescale)
        default:
            return nil
        }
    }

    nonisolated private func readChapterList(_ box: MP4Box) throws -> [RawChapter] {
        guard box.contentStart + 9 <= box.end else { return [] }
        let count = Int(try readUInt8(at: box.contentStart + 8))
        var offset = box.contentStart + 9
        var chapters: [RawChapter] = []
        chapters.reserveCapacity(count)

        for _ in 0..<count {
            guard offset + 9 <= box.end else { break }
            let startTime = Double(try readUInt64(at: offset)) / 10_000_000
            offset += 8
            let titleLength = Int(try readUInt8(at: offset))
            offset += 1
            guard offset + UInt64(titleLength) <= box.end else { break }
            let titleData = try readData(at: offset, count: titleLength)
            offset += UInt64(titleLength)
            chapters.append(
                RawChapter(
                    title: String(decoding: titleData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: startTime
                )
            )
        }
        return chapters
    }

    nonisolated private func childBox(in parent: MP4Box, type: String) throws -> MP4Box? {
        try childBox(start: parent.contentStart, end: parent.end, type: type)
    }

    nonisolated private func childBox(start: UInt64, end: UInt64, type: String) throws -> MP4Box? {
        var offset = start
        while offset + 8 <= end {
            guard let box = try readBox(at: offset, parentEnd: end) else { return nil }
            if box.type == type { return box }
            guard box.end > offset else { return nil }
            offset = box.end
        }
        return nil
    }

    nonisolated private func readBox(at offset: UInt64, parentEnd: UInt64) throws -> MP4Box? {
        guard offset + 8 <= parentEnd else { return nil }
        let shortSize = try readUInt32(at: offset)
        let type = String(decoding: try readData(at: offset + 4, count: 4), as: UTF8.self)
        let headerSize: UInt64
        let size: UInt64
        switch shortSize {
        case 0:
            headerSize = 8
            size = parentEnd - offset
        case 1:
            headerSize = 16
            size = try readUInt64(at: offset + 8)
        default:
            headerSize = 8
            size = UInt64(shortSize)
        }
        guard size >= headerSize, size <= parentEnd - offset else { return nil }
        return MP4Box(type: type, start: offset, headerSize: headerSize, size: size)
    }

    nonisolated private func readUInt8(at offset: UInt64) throws -> UInt8 {
        try readData(at: offset, count: 1)[0]
    }

    nonisolated private func readUInt32(at offset: UInt64) throws -> UInt64 {
        try readData(at: offset, count: 4).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    nonisolated private func readUInt64(at offset: UInt64) throws -> UInt64 {
        try readData(at: offset, count: 8).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    nonisolated private func readData(at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    nonisolated private func seconds(duration: UInt64, timescale: UInt64) -> Double? {
        guard timescale > 0 else { return nil }
        return Double(duration) / Double(timescale)
    }
}

private final class MP4MetadataReader: @unchecked Sendable {
    nonisolated private static let maxMetadataDataBytes: UInt64 = 20 * 1_024 * 1_024

    private let handle: FileHandle
    private let fileSize: UInt64

    nonisolated init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        fileSize = try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    nonisolated func read() throws -> SasayakiAudiobookMetadata {
        guard let moov = try childBox(start: 0, end: fileSize, type: "moov") else { return .empty }
        let meta = try childBox(in: moov, type: "udta")
            .flatMap { try childBox(in: $0, type: "meta") }
            ?? childBox(in: moov, type: "meta")
        guard let meta, meta.contentStart + 4 <= meta.end,
              let itemList = try childBox(
                start: meta.contentStart + 4,
                end: meta.end,
                type: "ilst"
              ) else { return .empty }

        var title: String?
        var artist: String?
        var albumArtist: String?
        var artworkData: Data?
        for item in try childBoxes(start: itemList.contentStart, end: itemList.end) {
            guard let data = try metadataData(in: item) else { continue }
            switch item.type {
            case "\u{00a9}nam":
                title = title ?? normalizedText(data)
            case "\u{00a9}ART":
                artist = artist ?? normalizedText(data)
            case "aART":
                albumArtist = albumArtist ?? normalizedText(data)
            case "covr":
                artworkData = artworkData ?? data
            default:
                continue
            }
        }
        return SasayakiAudiobookMetadata(
            title: title,
            artist: artist ?? albumArtist,
            artworkData: artworkData
        )
    }

    nonisolated private func metadataData(in item: MP4Box) throws -> Data? {
        guard let dataBox = try childBox(in: item, type: "data"),
              dataBox.contentStart + 8 <= dataBox.end else { return nil }
        let byteCount = dataBox.end - dataBox.contentStart - 8
        guard byteCount > 0, byteCount <= Self.maxMetadataDataBytes else { return nil }
        return try readData(at: dataBox.contentStart + 8, count: Int(byteCount))
    }

    nonisolated private func normalizedText(_ data: Data) -> String? {
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private func childBox(in parent: MP4Box, type: String) throws -> MP4Box? {
        try childBox(start: parent.contentStart, end: parent.end, type: type)
    }

    nonisolated private func childBox(start: UInt64, end: UInt64, type: String) throws -> MP4Box? {
        try childBoxes(start: start, end: end).first { $0.type == type }
    }

    nonisolated private func childBoxes(start: UInt64, end: UInt64) throws -> [MP4Box] {
        var boxes: [MP4Box] = []
        var offset = start
        while offset + 8 <= end {
            guard let box = try readBox(at: offset, parentEnd: end) else { break }
            boxes.append(box)
            guard box.end > offset else { break }
            offset = box.end
        }
        return boxes
    }

    nonisolated private func readBox(at offset: UInt64, parentEnd: UInt64) throws -> MP4Box? {
        guard offset + 8 <= parentEnd else { return nil }
        let shortSize = try readUInt32(at: offset)
        let typeData = try readData(at: offset + 4, count: 4)
        guard let type = String(data: typeData, encoding: .isoLatin1) else { return nil }
        let headerSize: UInt64
        let size: UInt64
        switch shortSize {
        case 0:
            headerSize = 8
            size = parentEnd - offset
        case 1:
            headerSize = 16
            size = try readUInt64(at: offset + 8)
        default:
            headerSize = 8
            size = UInt64(shortSize)
        }
        guard size >= headerSize, size <= parentEnd - offset else { return nil }
        return MP4Box(type: type, start: offset, headerSize: headerSize, size: size)
    }

    nonisolated private func readUInt32(at offset: UInt64) throws -> UInt64 {
        try readData(at: offset, count: 4).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    nonisolated private func readUInt64(at offset: UInt64) throws -> UInt64 {
        try readData(at: offset, count: 8).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    nonisolated private func readData(at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }
}

private struct MP4Box: Sendable {
    let type: String
    let start: UInt64
    let headerSize: UInt64
    let size: UInt64

    nonisolated var contentStart: UInt64 { start + headerSize }
    nonisolated var end: UInt64 { start + size }
}

private struct RawChapter: Sendable {
    let title: String
    let startTime: Double
}
