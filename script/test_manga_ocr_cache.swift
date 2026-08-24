import Foundation

@main
private enum MangaOCRCacheTests {
    static func main() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "niratan-manga-ocr-cache-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let pagePaths = ["001.jpg", "002.jpg"]
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstKey = MangaOCRCacheKey(
            itemID: "book-a",
            pageIndex: 0,
            pagePath: pagePaths[0],
            modifiedAt: modifiedAt,
            language: .japanese
        )
        let region = MangaOCRTextRegion(
            id: "page-0-line-0",
            pageIndex: 0,
            blockID: "block-0",
            lineID: "line-0",
            sentence: "日本語",
            utf16Offset: 0,
            isVertical: true,
            normalizedBounds: CGRect(x: 0.2, y: 0.1, width: 0.1, height: 0.3)
        )

        let writer = MangaOCRService(cacheDirectory: cacheRoot)
        await writer.storeCachedRegions(
            [region],
            for: firstKey,
            pagePaths: pagePaths
        )
        let emptyKey = MangaOCRCacheKey(
            itemID: "book-a",
            pageIndex: 1,
            pagePath: pagePaths[1],
            modifiedAt: modifiedAt,
            language: .japanese
        )
        await writer.storeCachedRegions(
            [],
            for: emptyKey,
            pagePaths: pagePaths
        )
        let englishKey = MangaOCRCacheKey(
            itemID: "book-a",
            pageIndex: 0,
            pagePath: pagePaths[0],
            modifiedAt: modifiedAt,
            language: .english
        )
        let englishRegion = MangaOCRTextRegion(
            id: "page-0-line-0-en",
            pageIndex: 0,
            blockID: "block-0-en",
            lineID: "line-0-en",
            sentence: "Hello world",
            utf16Offset: 0,
            isVertical: false,
            normalizedBounds: CGRect(
                x: 0.2,
                y: 0.1,
                width: 0.3,
                height: 0.1
            )
        )
        await writer.storeCachedRegions(
            [englishRegion],
            for: englishKey,
            pagePaths: pagePaths
        )

        let reopened = MangaOCRService(cacheDirectory: cacheRoot)
        let reopenedRegions = await reopened.cachedRegions(
            for: firstKey,
            pagePaths: pagePaths
        )
        require(
            reopenedRegions == [region],
            "recognized regions should survive a service restart"
        )
        let reopenedEmptyRegions = await reopened.cachedRegions(
            for: emptyKey,
            pagePaths: pagePaths
        )
        require(
            reopenedEmptyRegions == [],
            "an OCR page with no text should still be cached"
        )
        let reopenedEnglishRegions = await reopened.cachedRegions(
            for: englishKey,
            pagePaths: pagePaths
        )
        require(
            reopenedEnglishRegions == [englishRegion],
            "English and Japanese OCR caches must remain isolated and reusable"
        )

        let changedSourceKey = MangaOCRCacheKey(
            itemID: "book-a",
            pageIndex: 0,
            pagePath: pagePaths[0],
            modifiedAt: modifiedAt.addingTimeInterval(1),
            language: .japanese
        )
        let changedSourceRegions = await reopened.cachedRegions(
            for: changedSourceKey,
            pagePaths: pagePaths
        )
        require(
            changedSourceRegions == nil,
            "changing the source modification date should invalidate cached OCR"
        )

        await reopened.storeCachedRegions(
            [region],
            for: changedSourceKey,
            pagePaths: pagePaths
        )
        let changedPagePaths = ["cover.jpg", "002.jpg"]
        let reorderedKey = MangaOCRCacheKey(
            itemID: "book-a",
            pageIndex: 0,
            pagePath: changedPagePaths[0],
            modifiedAt: changedSourceKey.modifiedAt,
            language: .japanese
        )
        let reorderedRegions = await reopened.cachedRegions(
            for: reorderedKey,
            pagePaths: changedPagePaths
        )
        require(
            reorderedRegions == nil,
            "changing the stable page path list should invalidate cached OCR"
        )

        print("Manga OCR cache tests passed")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
