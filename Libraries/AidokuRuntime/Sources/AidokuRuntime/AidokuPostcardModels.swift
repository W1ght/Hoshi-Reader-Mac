import Foundation

public enum AidokuPostcardModels {
    public static func encode(_ manga: AidokuManga) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(manga.key)
        writer.write(manga.title)
        writer.write(manga.coverURL) { $0.write($1) }
        writer.write(manga.artists) { writer, values in writer.write(values) { $0.write($1) } }
        writer.write(manga.authors) { writer, values in writer.write(values) { $0.write($1) } }
        writer.write(manga.summary) { $0.write($1) }
        writer.write(manga.url) { $0.write($1) }
        writer.write(manga.tags) { writer, values in writer.write(values) { $0.write($1) } }
        writer.write(manga.status.rawValue)
        writer.write(manga.contentRating.rawValue)
        writer.write(manga.viewer.rawValue)
        writer.write(UInt8(0)) // UpdateStrategy.always
        writer.write(Optional<Int64>.none) { $0.write($1) }
        writer.write(manga.chapters) { writer, chapters in
            writer.write(chapters) { writer, chapter in write(chapter, to: &writer) }
        }
        return writer.data
    }

    public static func decodeMangaPage(_ data: Data) throws -> AidokuMangaPage {
        var reader = AidokuPostcardReader(data: data)
        let entries = try reader.readArray { try readManga(from: &$0) }
        let hasNextPage = try reader.readBool()
        try reader.finish()
        return AidokuMangaPage(entries: entries, hasNextPage: hasNextPage)
    }

    public static func decodeManga(_ data: Data) throws -> AidokuManga {
        var reader = AidokuPostcardReader(data: data)
        let manga = try readManga(from: &reader)
        try reader.finish()
        return manga
    }

    public static func encode(_ chapter: AidokuChapter) -> Data {
        var writer = AidokuPostcardWriter()
        write(chapter, to: &writer)
        return writer.data
    }

    public static func decodePages(
        _ data: Data,
        imageResolver: (Int32) -> Data?
    ) throws -> [AidokuPage] {
        var reader = AidokuPostcardReader(data: data)
        let pages = try reader.readArray { reader -> AidokuPage in
            let contentKind = try reader.readVarUInt()
            let content: AidokuPageContent
            switch contentKind {
            case 0:
                let url = try reader.readString()
                let context = try reader.readOptional { reader in
                    try reader.readDictionary(
                        key: { try $0.readString() },
                        value: { try $0.readString() }
                    )
                } ?? [:]
                content = .url(url, context: context)
            case 1:
                content = .text(try reader.readString())
            case 2:
                let rid = try reader.readInt32()
                guard let data = imageResolver(rid), data.count <= AidokuLimits.maximumImageBytes else {
                    throw AidokuRuntimeError.responseTooLarge
                }
                content = .image(data)
            case 3:
                content = .zip(url: try reader.readString(), path: try reader.readString())
            default:
                throw AidokuRuntimeError.malformedPostcard
            }
            let thumbnail = try reader.readOptional { try $0.readString() }
            let hasDescription = try reader.readBool()
            let description = try reader.readOptional { try $0.readString() }
            let index = 0 // replaced after decoding
            return AidokuPage(
                id: "page-\(index)",
                index: index,
                content: content,
                thumbnailURL: thumbnail,
                hasDescription: hasDescription,
                description: description
            )
        }
        try reader.finish()
        return pages.enumerated().map { index, page in
            AidokuPage(
                id: "page-\(index)",
                index: index,
                content: page.content,
                thumbnailURL: page.thumbnailURL,
                hasDescription: page.hasDescription,
                description: page.description
            )
        }
    }

    public static func decodeListings(_ data: Data) throws -> [AidokuListing] {
        var reader = AidokuPostcardReader(data: data)
        let values = try reader.readArray { reader -> AidokuListing in
            let id = try reader.readString()
            let name = try reader.readString()
            guard let kind = AidokuListingKind(rawValue: try reader.readUInt8()) else {
                throw AidokuRuntimeError.malformedPostcard
            }
            return AidokuListing(id: id, name: name, kind: kind)
        }
        try reader.finish()
        return values
    }

    public static func decodeHomeManga(_ data: Data) throws -> [AidokuManga] {
        var reader = AidokuPostcardReader(data: data)
        let components = try readHomeLayout(from: &reader)
        try reader.finish()
        return deduplicatingMangaEntries(components.flatMap(\.manga))
    }

    static func resolvedHomeManga(
        finalResult: Data,
        partialResults: [Data]
    ) throws -> [AidokuManga] {
        var finalReader = AidokuPostcardReader(data: finalResult)
        let finalComponents = try readHomeLayout(from: &finalReader)
        try finalReader.finish()

        var partialComponents: [DecodedHomeComponent]?
        var partialDecodingError: Error?
        for partialResult in partialResults {
            do {
                switch try decodeHomePartialResult(partialResult) {
                case .layout(let components):
                    partialComponents = components
                case .component(let component):
                    var components = partialComponents ?? []
                    if let index = components.firstIndex(where: {
                        $0.title == component.title
                    }) {
                        components[index] = component
                    } else {
                        components.append(component)
                    }
                    partialComponents = components
                }
            } catch {
                // AidokuRunner keeps processing later partial values, but surfaces any partial
                // decoding failure after the source has returned and its final Home has decoded.
                partialDecodingError = error
            }
        }
        if let partialDecodingError { throw partialDecodingError }

        let components = finalComponents.isEmpty
            ? (partialComponents ?? finalComponents)
            : finalComponents
        return deduplicatingMangaEntries(components.flatMap(\.manga))
    }

    static func resolvedMangaDetails(
        finalResult: Data,
        partialResults: [Data]
    ) throws -> AidokuManga {
        // Official Aidoku behavior publishes partial Manga values only as transient updates.
        // This synchronous API has no publisher, so the final export remains authoritative and
        // malformed partial Manga payloads are deliberately ignored.
        _ = partialResults
        return try decodeManga(finalResult)
    }

    public static func encode(
        filterValues: [(id: String, value: AidokuFilterValue)]
    ) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(filterValues) { writer, item in
            switch item.value {
            case .text(let value):
                writer.writeVarUInt(0)
                writer.write(item.id)
                writer.write(value)
            case .sort(let index, let ascending):
                writer.writeVarUInt(1)
                writer.write(item.id)
                writer.write(Int32(index))
                writer.write(ascending)
            case .check(let value):
                writer.writeVarUInt(2)
                writer.write(item.id)
                writer.write(Int32(value))
            case .select(let value):
                writer.writeVarUInt(3)
                writer.write(item.id)
                writer.write(value)
            case .multiSelect(let include, let exclude):
                writer.writeVarUInt(4)
                writer.write(item.id)
                writer.write(include.sorted()) { $0.write($1) }
                writer.write(exclude.sorted()) { $0.write($1) }
            case .range(let lower, let upper):
                writer.writeVarUInt(5)
                writer.write(item.id)
                writer.write(lower) { $0.write($1) }
                writer.write(upper) { $0.write($1) }
            }
        }
        return writer.data
    }

    public static func encode(_ string: String) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(string)
        return writer.data
    }

    public static func encode(_ strings: [String]) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(strings) { $0.write($1) }
        return writer.data
    }

    public static func decodeBool(_ data: Data) throws -> Bool {
        var reader = AidokuPostcardReader(data: data)
        let value = try reader.readBool()
        try reader.finish()
        return value
    }

    public static func decodeString(_ data: Data) throws -> String {
        var reader = AidokuPostcardReader(data: data)
        let value = try reader.readString()
        try reader.finish()
        return value
    }

    public static func decodeInt32(_ data: Data) throws -> Int32 {
        var reader = AidokuPostcardReader(data: data)
        let value = try reader.readInt32()
        try reader.finish()
        return value
    }

    public static func encodePageContext(_ context: [String: String]) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(context, key: { $0.write($1) }, value: { $0.write($1) })
        return writer.data
    }

    public static func encodeImageResponse(
        statusCode: UInt16,
        responseHeaders: [String: String],
        requestURL: String,
        requestHeaders: [String: String],
        imageDescriptor: Int32
    ) -> Data {
        var writer = AidokuPostcardWriter()
        writer.write(statusCode)
        writer.write(responseHeaders, key: { $0.write($1) }, value: { $0.write($1) })
        writer.write(Optional(requestURL)) { $0.write($1) }
        writer.write(requestHeaders, key: { $0.write($1) }, value: { $0.write($1) })
        writer.write(imageDescriptor)
        return writer.data
    }

    private static func readManga(from reader: inout AidokuPostcardReader) throws -> AidokuManga {
        let key = try reader.readString()
        let title = try reader.readString()
        let cover = try reader.readOptional { try $0.readString() }
        let artists = try reader.readOptional { try $0.readArray { try $0.readString() } }
        let authors = try reader.readOptional { try $0.readArray { try $0.readString() } }
        let summary = try reader.readOptional { try $0.readString() }
        let url = try reader.readOptional { try $0.readString() }
        let tags = try reader.readOptional { try $0.readArray(maximumCount: 255) { try $0.readString() } }
        guard let status = AidokuMangaStatus(rawValue: try reader.readUInt8()),
              let contentRating = AidokuMangaContentRating(rawValue: try reader.readUInt8()),
              let viewer = AidokuViewer(rawValue: try reader.readUInt8()) else {
            throw AidokuRuntimeError.malformedPostcard
        }
        _ = try reader.readUInt8() // update strategy
        _ = try reader.readOptional { try $0.readInt64() }
        let chapters = try reader.readOptional { reader in
            try reader.readArray { try readChapter(from: &$0) }
        }
        return AidokuManga(
            key: key,
            title: title,
            coverURL: cover,
            artists: artists,
            authors: authors,
            summary: summary,
            url: url,
            tags: tags,
            status: status,
            contentRating: contentRating,
            viewer: viewer,
            chapters: chapters
        )
    }

    private struct DecodedHomeComponent {
        let title: String?
        let manga: [AidokuManga]
    }

    private enum DecodedHomePartialResult {
        case layout([DecodedHomeComponent])
        case component(DecodedHomeComponent)
    }

    private static func decodeHomePartialResult(
        _ data: Data
    ) throws -> DecodedHomePartialResult {
        var reader = AidokuPostcardReader(data: data)
        let result: DecodedHomePartialResult
        switch try reader.readVarUInt() {
        case 0:
            result = .layout(try readHomeLayout(from: &reader))
        case 1:
            result = .component(try readHomeComponent(from: &reader))
        default:
            throw AidokuRuntimeError.malformedPostcard
        }
        try reader.finish()
        return result
    }

    private static func readHomeLayout(
        from reader: inout AidokuPostcardReader
    ) throws -> [DecodedHomeComponent] {
        try reader.readArray { try readHomeComponent(from: &$0) }
    }

    private static func readHomeComponent(
        from reader: inout AidokuPostcardReader
    ) throws -> DecodedHomeComponent {
        let title = try reader.readOptional { try $0.readString() }
        _ = try reader.readOptional { try $0.readString() }
        var manga: [AidokuManga] = []
        switch try reader.readVarUInt() {
        case 0:
            // Image scrollers are promotional banners rather than manga cards. Their links
            // commonly contain an episode-only key and no title, so flattening them into the
            // browse grid creates blank, non-actionable cards.
            var ignoredManga: [AidokuManga] = []
            _ = try reader.readArray { reader in
                try readHomeLink(from: &reader, manga: &ignoredManga)
            }
            _ = try reader.readOptional { try $0.readFloat() }
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readOptional { try $0.readInt32() }
        case 1:
            manga.append(contentsOf: try reader.readArray { try readManga(from: &$0) })
            _ = try reader.readOptional { try $0.readFloat() }
        case 2:
            _ = try reader.readArray { reader in
                try readHomeLink(from: &reader, manga: &manga)
            }
            try skipOptionalListing(&reader)
        case 3:
            _ = try reader.readBool()
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readArray { reader in
                try readHomeLink(from: &reader, manga: &manga)
            }
            try skipOptionalListing(&reader)
        case 4:
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readArray { reader -> Bool in
                manga.append(try readManga(from: &reader))
                _ = try readChapter(from: &reader)
                return true
            }
            try skipOptionalListing(&reader)
        case 5:
            _ = try reader.readArray { reader -> Bool in
                _ = try reader.readString()
                _ = try reader.readOptional { reader in
                    try reader.readArray { try skipFilterValue(&$0) }
                }
                return true
            }
        case 6:
            _ = try reader.readArray { reader in
                try readHomeLink(from: &reader, manga: &manga)
            }
        default:
            throw AidokuRuntimeError.malformedPostcard
        }
        return DecodedHomeComponent(title: title, manga: manga)
    }

    private static func deduplicatingMangaEntries(
        _ entries: [AidokuManga]
    ) -> [AidokuManga] {
        var seen: Set<String> = []
        return entries.filter { seen.insert($0.key).inserted }
    }

    private static func readHomeLink(from reader: inout AidokuPostcardReader, manga: inout [AidokuManga]) throws -> Bool {
        let title = try reader.readString()
        let subtitle = try reader.readOptional { try $0.readString() }
        let imageURL = try reader.readOptional { try $0.readString() }
        guard try reader.readBool() else { return true }
        switch try reader.readVarUInt() {
        case 0: _ = try reader.readString()
        case 1: try skipListing(&reader)
        case 2:
            var entry = try readManga(from: &reader)
            if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.title = title
            }
            if entry.coverURL == nil { entry.coverURL = imageURL }
            if entry.summary == nil { entry.summary = subtitle }
            manga.append(entry)
        default: throw AidokuRuntimeError.malformedPostcard
        }
        return true
    }

    private static func skipOptionalListing(_ reader: inout AidokuPostcardReader) throws {
        _ = try reader.readOptional { reader -> Bool in try skipListing(&reader); return true }
    }

    private static func skipListing(_ reader: inout AidokuPostcardReader) throws {
        _ = try reader.readString()
        _ = try reader.readString()
        _ = try reader.readUInt8()
    }

    private static func skipFilterValue(_ reader: inout AidokuPostcardReader) throws -> Bool {
        switch try reader.readVarUInt() {
        case 0: _ = try reader.readString(); _ = try reader.readString()
        case 1: _ = try reader.readString(); _ = try reader.readInt32(); _ = try reader.readBool()
        case 2: _ = try reader.readString(); _ = try reader.readInt32()
        case 3: _ = try reader.readString(); _ = try reader.readString()
        case 4:
            _ = try reader.readString()
            _ = try reader.readArray { try $0.readString() }
            _ = try reader.readArray { try $0.readString() }
        case 5:
            _ = try reader.readString()
            _ = try reader.readOptional { try $0.readFloat() }
            _ = try reader.readOptional { try $0.readFloat() }
        default: throw AidokuRuntimeError.malformedPostcard
        }
        return true
    }

    private static func readChapter(from reader: inout AidokuPostcardReader) throws -> AidokuChapter {
        AidokuChapter(
            key: try reader.readString(),
            title: try reader.readOptional { try $0.readString() },
            chapterNumber: try reader.readOptional { try $0.readFloat() },
            volumeNumber: try reader.readOptional { try $0.readFloat() },
            dateUploaded: try reader.readOptional { try $0.readInt64() },
            scanlators: try reader.readOptional { try $0.readArray { try $0.readString() } },
            url: try reader.readOptional { try $0.readString() },
            language: try reader.readOptional { try $0.readString() },
            thumbnailURL: try reader.readOptional { try $0.readString() },
            locked: try reader.readBool()
        )
    }

    private static func write(_ chapter: AidokuChapter, to writer: inout AidokuPostcardWriter) {
        writer.write(chapter.key)
        writer.write(chapter.title) { $0.write($1) }
        writer.write(chapter.chapterNumber) { $0.write($1) }
        writer.write(chapter.volumeNumber) { $0.write($1) }
        writer.write(chapter.dateUploaded) { $0.write($1) }
        writer.write(chapter.scanlators) { writer, values in writer.write(values) { $0.write($1) } }
        writer.write(chapter.url) { $0.write($1) }
        writer.write(chapter.language) { $0.write($1) }
        writer.write(chapter.thumbnailURL) { $0.write($1) }
        writer.write(chapter.locked)
    }
}
