import Foundation

enum ReaderChapterIndexContractTests {
    private static func read(_ path: String) -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            fputs("FAIL: could not read \(path): \(error)\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let model = read("Models/Book.swift")
        let processor = read("Util/BookProcessor.swift")
        let reader = read("NativeMac/NativeReaderView.swift")
        let chapterList = read("Features/Reader/ChapterListView/ChapterListViewModel.swift")
        let statistics = read("Features/Reader/StatisticsView.swift")
        let project = read("Niratan.xcodeproj/project.pbxproj")

        expect(
            model.contains("var fragmentOffsets: [String: Int]?")
                && model.contains("func mergingMissingFragmentOffsets"),
            "bookinfo should decode legacy sidecars and merge fragment offsets without replacing other fields"
        )
        expect(
            processor.contains("fragmentOffsets: ReaderChapterIndex.fragmentOffsets")
                && processor.contains("static func fragmentOffsetSources"),
            "new imports and legacy books should share the fragment-offset calculator"
        )
        expect(
            reader.contains("Task.detached(priority: .utility)")
                && reader.contains("ReaderChapterIndex.fragmentOffsets(")
                && reader.contains("BookStorage.loadBookInfo(root: root) ?? self.bookInfo")
                && reader.contains("latestChapter.chapterCount == source.expectedChapterCount")
                && reader.contains("mergingMissingFragmentOffsets(compatibleOffsets)"),
            "legacy fragment backfill should run off-main and merge only into a compatible latest sidecar snapshot"
        )
        expect(
            reader.contains("chapterIndexGeneration = nil")
                && reader.contains("chapterIndexTask?.cancel()"),
            "closing Reader should cancel and invalidate the fragment backfill"
        )
        expect(
            chapterList.contains("currentCharacter: Int")
                && chapterList.contains("ReaderChapterIndex.chapterStart")
                && !chapterList.contains("index == currentIndex"),
            "chapter selection should use fragment-aware global character positions"
        )
        expect(
            reader.contains("var currentChapterCharactersRemaining: Int")
                && reader.contains("currentTOCChapterRange.remaining(at: currentCharacter)")
                && statistics.contains("let chapterCharactersRemaining: Int")
                && statistics.contains("Double(max(chapterCharactersRemaining, 0))"),
            "time-to-finish chapter should use the current TOC chapter range"
        )
        expect(
            !statistics.contains("currentChapterCount - currentCharacter"),
            "statistics must not subtract a global character position from an XHTML end offset"
        )
        expect(
            project.contains("Reader/ReaderChapterIndex.swift"),
            "the chapter index must belong to the native target"
        )

        print("Reader chapter index contract passed")
    }
}

ReaderChapterIndexContractTests.main()
