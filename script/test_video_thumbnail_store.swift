import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private final class CountingThumbnailGenerator: VideoThumbnailGenerating {
    var calls = 0
    var data = Data([0x89, 0x50, 0x4E, 0x47])

    func thumbnailPNGData(for url: URL) async throws -> Data {
        calls += 1
        return data
    }
}

private func makeItem(
    url: URL,
    fileSize: Int64 = 4,
    modifiedAt: Date? = Date(timeIntervalSince1970: 100)
) -> VideoLibraryItem {
    VideoLibraryItem(
        path: url.standardizedFileURL.path,
        sourceID: UUID(),
        title: url.deletingPathExtension().lastPathComponent,
        parentFolder: url.deletingLastPathComponent().lastPathComponent,
        fileSize: fileSize,
        modifiedAt: modifiedAt,
        lastSeenAt: Date(timeIntervalSince1970: 200)
    )
}

@main
private enum VideoThumbnailStoreTests {
    static func main() async throws {
        try testDefaultThumbnailGeneratorUsesMpv()
        try await testThumbnailGenerationWritesAndReusesCache()
        try await testThumbnailCacheInvalidatesWhenFileMetadataChanges()
        try await testThumbnailInvalidationRegeneratesCachedImage()
        try await testMissingFileDoesNotGenerateThumbnail()
        print("Video thumbnail store tests passed")
    }

    private static func testDefaultThumbnailGeneratorUsesMpv() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Features/Video/VideoThumbnailStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        expect(
            source.contains("MpvVideoThumbnailGenerator"),
            "default thumbnail generator should be mpv-backed"
        )
        expect(
            !source.contains("AVAssetImageGenerator"),
            "video thumbnails should not default to AVFoundation image generation"
        )
    }

    private static func testThumbnailGenerationWritesAndReusesCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let video = root.appendingPathComponent("Episode.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: video.path, contents: Data([1, 2, 3, 4]))
        defer { try? FileManager.default.removeItem(at: root) }

        let generator = CountingThumbnailGenerator()
        let store = VideoThumbnailStore(
            cacheDirectory: cache,
            generator: generator,
            fileManager: .default
        )
        let item = makeItem(url: video)

        let firstURL = await store.thumbnailURL(for: item)
        expect(firstURL != nil, "thumbnail generation should return a cache URL")
        expect(generator.calls == 1, "first thumbnail request should invoke the generator")
        expect(
            FileManager.default.fileExists(atPath: firstURL?.path ?? ""),
            "generated thumbnail should be written to disk"
        )

        let secondURL = await store.thumbnailURL(for: item)
        expect(secondURL == firstURL, "repeated thumbnail request should reuse the same cache URL")
        expect(generator.calls == 1, "cached thumbnail request should not invoke the generator")
    }

    private static func testThumbnailCacheInvalidatesWhenFileMetadataChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let video = root.appendingPathComponent("Episode.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: video.path, contents: Data([1, 2, 3, 4]))
        defer { try? FileManager.default.removeItem(at: root) }

        let store = VideoThumbnailStore(
            cacheDirectory: cache,
            generator: CountingThumbnailGenerator(),
            fileManager: .default
        )
        let first = store.cacheURL(for: makeItem(
            url: video,
            fileSize: 4,
            modifiedAt: Date(timeIntervalSince1970: 100)
        ))
        let changedSize = store.cacheURL(for: makeItem(
            url: video,
            fileSize: 8,
            modifiedAt: Date(timeIntervalSince1970: 100)
        ))
        let changedDate = store.cacheURL(for: makeItem(
            url: video,
            fileSize: 4,
            modifiedAt: Date(timeIntervalSince1970: 200)
        ))

        expect(first != changedSize, "thumbnail cache key should include file size")
        expect(first != changedDate, "thumbnail cache key should include modified date")
    }

    private static func testThumbnailInvalidationRegeneratesCachedImage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let video = root.appendingPathComponent("Episode.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: video.path, contents: Data([1, 2, 3, 4]))
        defer { try? FileManager.default.removeItem(at: root) }

        let generator = CountingThumbnailGenerator()
        let store = VideoThumbnailStore(
            cacheDirectory: cache,
            generator: generator,
            fileManager: .default
        )
        let item = makeItem(url: video)

        let firstURL = await store.thumbnailURL(for: item)
        store.invalidateThumbnail(for: item)
        let secondURL = await store.thumbnailURL(for: item)

        expect(firstURL == secondURL, "thumbnail invalidation should keep a stable cache URL")
        expect(generator.calls == 2, "thumbnail invalidation should force regeneration")
    }

    private static func testMissingFileDoesNotGenerateThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let missingVideo = root.appendingPathComponent("Missing.mp4")
        let generator = CountingThumbnailGenerator()
        let store = VideoThumbnailStore(
            cacheDirectory: cache,
            generator: generator,
            fileManager: .default
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let thumbnailURL = await store.thumbnailURL(for: makeItem(url: missingVideo))

        expect(thumbnailURL == nil, "missing video file should not produce a thumbnail")
        expect(generator.calls == 0, "missing video file should not invoke the generator")
    }
}
