import Foundation
import Testing
@testable import AidokuRuntime

@Test func aidokuPartialResultsAreInvocationScopedAndDrained() {
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: nil,
        defaultsWriter: { _ in }
    )

    store.appendPartialResult(Data([1]))
    store.appendPartialResult(Data([2]))
    #expect(store.takePartialResults() == [Data([1]), Data([2])])
    #expect(store.takePartialResults().isEmpty)

    store.appendPartialResult(Data([3]))
    store.resetCancellation()
    #expect(store.takePartialResults().isEmpty)
}

@Test func aidokuHomePartialsUseOfficialLayoutAndComponentStateMachine() throws {
    let partialResults = [
        homePartialLayoutFixture([
            ("Popular", [AidokuManga(key: "old-popular", title: "Old Popular")]),
            ("Fresh", [AidokuManga(key: "old-fresh", title: "Old Fresh")]),
        ]),
        homePartialComponentFixture(
            title: "Popular",
            manga: [AidokuManga(key: "new-popular", title: "New Popular")]
        ),
        homePartialComponentFixture(
            title: "Latest",
            manga: [AidokuManga(key: "old-latest", title: "Old Latest")]
        ),
        // A later Layout replaces the complete accumulated Home.
        homePartialLayoutFixture([
            ("Reset", [AidokuManga(key: "old-reset", title: "Old Reset")]),
        ]),
        // Components then replace a same-title component or append a new one.
        homePartialComponentFixture(
            title: "Reset",
            manga: [AidokuManga(key: "new-reset", title: "New Reset")]
        ),
        homePartialComponentFixture(
            title: "Appended",
            manga: [AidokuManga(key: "appended", title: "Appended")]
        ),
    ]

    let result = try AidokuPostcardModels.resolvedHomeManga(
        finalResult: homeLayoutFixture([]),
        partialResults: partialResults
    )

    #expect(result.map(\.key) == ["new-reset", "appended"])
}

@Test func aidokuHomeFinalResultWinsWhenItContainsComponents() throws {
    let result = try AidokuPostcardModels.resolvedHomeManga(
        finalResult: homeLayoutFixture([
            ("Final", [AidokuManga(key: "final", title: "Final")]),
        ]),
        partialResults: [
            homePartialLayoutFixture([
                ("Partial", [AidokuManga(key: "partial", title: "Partial")]),
            ]),
        ]
    )

    #expect(result.map(\.key) == ["final"])
}

@Test func aidokuHomeSurfacesPartialDecodeFailureAfterFinalDecode() throws {
    do {
        _ = try AidokuPostcardModels.resolvedHomeManga(
            finalResult: homeLayoutFixture([
                ("Final", [AidokuManga(key: "final", title: "Final")]),
            ]),
            partialResults: [Data([2])]
        )
        Issue.record("Malformed Home partial unexpectedly decoded")
    } catch let error as AidokuRuntimeError {
        #expect(error == .malformedPostcard)
    }
}

@Test func aidokuMangaDetailsUseOnlyFinalResultAndIgnorePartials() throws {
    let final = AidokuManga(
        key: "series",
        title: "Final Title",
        chapters: [AidokuChapter(key: "final-chapter", title: "Final Chapter")]
    )
    let transient = AidokuManga(
        key: "series",
        title: "Transient Title",
        chapters: [AidokuChapter(key: "partial-chapter", title: "Partial Chapter")]
    )

    let result = try AidokuPostcardModels.resolvedMangaDetails(
        finalResult: AidokuPostcardModels.encode(final),
        partialResults: [
            AidokuPostcardModels.encode(transient),
            Data([0xff]), // Manga partial decoding errors are ignored by AidokuRunner.
        ]
    )

    #expect(result == final)
}

private typealias HomeComponentFixture = (title: String?, manga: [AidokuManga])

private func homePartialLayoutFixture(_ components: [HomeComponentFixture]) -> Data {
    var writer = AidokuPostcardWriter()
    writer.writeVarUInt(0) // HomePartialResult::Layout
    writeHomeLayoutFixture(components, to: &writer)
    return writer.data
}

private func homePartialComponentFixture(
    title: String?,
    manga: [AidokuManga]
) -> Data {
    var writer = AidokuPostcardWriter()
    writer.writeVarUInt(1) // HomePartialResult::Component
    writeHomeComponentFixture(title: title, manga: manga, to: &writer)
    return writer.data
}

private func homeLayoutFixture(_ components: [HomeComponentFixture]) -> Data {
    var writer = AidokuPostcardWriter()
    writeHomeLayoutFixture(components, to: &writer)
    return writer.data
}

private func writeHomeLayoutFixture(
    _ components: [HomeComponentFixture],
    to writer: inout AidokuPostcardWriter
) {
    writer.write(components) { writer, component in
        writeHomeComponentFixture(
            title: component.title,
            manga: component.manga,
            to: &writer
        )
    }
}

private func writeHomeComponentFixture(
    title: String?,
    manga: [AidokuManga],
    to writer: inout AidokuPostcardWriter
) {
    writer.write(title) { $0.write($1) }
    writer.write(Optional<String>.none) { $0.write($1) }
    writer.writeVarUInt(1) // HomeComponentValue::BigScroller
    writer.write(manga) { writer, manga in
        writeMangaFixture(manga, to: &writer)
    }
    writer.write(Optional<Float>.none) { $0.write($1) }
}

private func writeMangaFixture(
    _ manga: AidokuManga,
    to writer: inout AidokuPostcardWriter
) {
    writer.write(manga.key)
    writer.write(manga.title)
    writer.write(manga.coverURL) { $0.write($1) }
    writer.write(manga.artists) { writer, values in
        writer.write(values) { $0.write($1) }
    }
    writer.write(manga.authors) { writer, values in
        writer.write(values) { $0.write($1) }
    }
    writer.write(manga.summary) { $0.write($1) }
    writer.write(manga.url) { $0.write($1) }
    writer.write(manga.tags) { writer, values in
        writer.write(values) { $0.write($1) }
    }
    writer.write(manga.status.rawValue)
    writer.write(manga.contentRating.rawValue)
    writer.write(manga.viewer.rawValue)
    writer.write(UInt8(0))
    writer.write(Optional<Int64>.none) { $0.write($1) }
    writer.write(manga.chapters) { writer, chapters in
        writer.write(chapters) { writer, chapter in
            writer.write(chapter.key)
            writer.write(chapter.title) { $0.write($1) }
            writer.write(chapter.chapterNumber) { $0.write($1) }
            writer.write(chapter.volumeNumber) { $0.write($1) }
            writer.write(chapter.dateUploaded) { $0.write($1) }
            writer.write(chapter.scanlators) { writer, values in
                writer.write(values) { $0.write($1) }
            }
            writer.write(chapter.url) { $0.write($1) }
            writer.write(chapter.language) { $0.write($1) }
            writer.write(chapter.thumbnailURL) { $0.write($1) }
            writer.write(chapter.locked)
        }
    }
}
