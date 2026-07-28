import Foundation

nonisolated struct MangaReadingChapter:
    Identifiable,
    Equatable,
    Hashable,
    Sendable
{
    let id: String
    let title: String
    let suwayomiChapter: SuwayomiChapter?
}

nonisolated struct MangaPageReference:
    Identifiable,
    Equatable,
    Hashable,
    Sendable
{
    let id: String
    let index: Int
    let displayPath: String
    let ocrCacheIdentity: String
    let pageURL: String?
    let imageURL: String?
}

nonisolated struct MangaPagePayload: Sendable {
    let data: Data
    let fileExtension: String
    let embeddedTextRegions: [MangaOCRTextRegion]?
}

nonisolated protocol MangaPageContentProvider: Sendable {
    func pages(
        for chapter: MangaReadingChapter
    ) async throws -> [MangaPageReference]
    func payload(for page: MangaPageReference) async throws
        -> MangaPagePayload
    func hasEmbeddedText(
        for chapter: MangaReadingChapter
    ) async throws -> Bool
    func prefetch(pages: [MangaPageReference]) async
    func cancelPendingRequests() async
}

nonisolated extension MangaPageContentProvider {
    func prefetch(pages: [MangaPageReference]) async {}
}

nonisolated struct MangaReadingSession: Sendable {
    typealias ProgressWriter = @Sendable (
        _ chapter: MangaReadingChapter,
        _ pageIndex: Int,
        _ pageCount: Int,
        _ completed: Bool
    ) async -> Void
    typealias CoverWriter = @Sendable (_ data: Data) async throws -> Void

    let profileID: String
    let documentID: String
    let title: String
    let chapters: [MangaReadingChapter]
    let initialChapterIndex: Int
    let initialPageIndex: Int
    let initialPages: [MangaPageReference]
    let modifiedAt: Date?
    let allowsCoverUpdates: Bool
    let progressWriter: ProgressWriter
    let coverWriter: CoverWriter

    static func local(
        item: MangaLibraryItem,
        source: MangaLibrarySource,
        profileID: String
    ) throws -> (
        session: MangaReadingSession,
        provider: LocalMangaPageContentProvider
    ) {
        let provider = try LocalMangaPageContentProvider(
            item: item,
            source: source
        )
        let chapter = MangaReadingChapter(
            id: item.id,
            title: item.displayTitle,
            suwayomiChapter: nil
        )
        let itemID = item.id
        return (
            MangaReadingSession(
                profileID: profileID,
                documentID: item.id,
                title: item.title,
                chapters: [chapter],
                initialChapterIndex: 0,
                initialPageIndex: item.currentPageIndex,
                initialPages: provider.pageReferences,
                modifiedAt: item.modifiedAt,
                allowsCoverUpdates: true,
                progressWriter: { _, pageIndex, _, _ in
                    await MangaLibraryStore.shared.updateProgress(
                        itemID: itemID,
                        pageIndex: pageIndex,
                        updatedAt: Date()
                    )
                },
                coverWriter: { data in
                    try await MangaLibraryStore.shared.setCover(
                        itemID: itemID,
                        imageData: data
                    )
                }
            ),
            provider
        )
    }

    static func suwayomi(
        manga: SuwayomiManga,
        chapters sourceChapters: [SuwayomiChapter],
        initialChapterID: Int? = nil,
        profileID: String,
        client: SuwayomiClient,
        pageProvider: SuwayomiMangaPageContentProvider
    ) async throws -> MangaReadingSession {
        guard !sourceChapters.isEmpty else {
            throw SuwayomiConnectorError.chapterUnavailable
        }
        let serverID = client.serverID
        let chapters = sourceChapters.map { chapter in
            MangaReadingChapter(
                id: SuwayomiIdentity.chapterID(
                    serverID: serverID,
                    remoteID: chapter.id
                ),
                title: chapter.name,
                suwayomiChapter: chapter
            )
        }
        let lastReadIndex = sourceChapters.enumerated()
            .filter { $0.element.lastReadAt > 0 }
            .max { $0.element.lastReadAt < $1.element.lastReadAt }?
            .offset
        let firstUnreadIndex = sourceChapters.firstIndex { !$0.read }
        let selectedChapterIndex = initialChapterID.flatMap { chapterID in
            sourceChapters.firstIndex { $0.id == chapterID }
        }
        let initialChapterIndex =
            selectedChapterIndex ?? lastReadIndex ?? firstUnreadIndex ?? 0
        let initialChapter = chapters[initialChapterIndex]
        let initialPages = try await pageProvider.pages(
            for: initialChapter
        )
        let initialPageIndex = min(
            max(
                0,
                sourceChapters[initialChapterIndex].lastPageRead
            ),
            max(0, initialPages.count - 1)
        )
        return MangaReadingSession(
            profileID: profileID,
            documentID: SuwayomiIdentity.mangaID(
                serverID: serverID,
                remoteID: manga.id
            ),
            title: manga.title,
            chapters: chapters,
            initialChapterIndex: initialChapterIndex,
            initialPageIndex: initialPageIndex,
            initialPages: initialPages,
            modifiedAt: nil,
            allowsCoverUpdates: false,
            progressWriter: { chapter, pageIndex, _, completed in
                guard let remote = chapter.suwayomiChapter else { return }
                try? await client.updateProgress(
                    chapter: remote,
                    pageIndex: pageIndex,
                    completed: completed
                )
            },
            coverWriter: { _ in
                throw SuwayomiConnectorError.mangaUnavailable
            }
        )
    }
}

nonisolated struct MangaRemoteReadingResult: Sendable {
    let session: MangaReadingSession
    let pageProvider: any MangaPageContentProvider
}

nonisolated struct MangaRemoteReadingRequest:
    Identifiable,
    Sendable
{
    let id = UUID()
    let manga: SuwayomiManga
    let initialChapterID: Int?
    let profileID: String
    let client: SuwayomiClient
    let cachedManga: SuwayomiManga?
    let cachedChapters: [SuwayomiChapter]

    var title: String { cachedManga?.title ?? manga.title }

    func load() async throws -> MangaRemoteReadingResult {
        let loadedManga: SuwayomiManga
        let chapters: [SuwayomiChapter]
        if let cachedManga, !cachedChapters.isEmpty {
            loadedManga = cachedManga
            chapters = cachedChapters
        } else {
            loadedManga = try await client.manga(
                id: manga.id,
                onlineFetch: true
            )
            try Task.checkCancellation()
            chapters = try await client.chapters(
                mangaID: manga.id,
                onlineFetch: true
            )
        }
        try Task.checkCancellation()
        let provider = try await SuwayomiMangaPageContentProvider(
            client: client,
            profileID: profileID
        )
        let session = try await MangaReadingSession.suwayomi(
            manga: loadedManga,
            chapters: chapters,
            initialChapterID: initialChapterID,
            profileID: profileID,
            client: client,
            pageProvider: provider
        )
        return MangaRemoteReadingResult(
            session: session,
            pageProvider: provider
        )
    }
}

nonisolated final class LocalMangaPageContentProvider:
    MangaPageContentProvider,
    @unchecked Sendable
{
    let pageReferences: [MangaPageReference]
    private let loader: MangaPageLoader

    init(item: MangaLibraryItem, source: MangaLibrarySource) throws {
        let loader = try MangaPageLoader(item: item, source: source)
        self.loader = loader
        pageReferences = loader.pages.enumerated().map { index, page in
            MangaPageReference(
                id: "\(item.id):\(index)",
                index: index,
                displayPath: page.path,
                ocrCacheIdentity: page.path,
                pageURL: nil,
                imageURL: nil
            )
        }
    }

    func pages(
        for chapter: MangaReadingChapter
    ) async throws -> [MangaPageReference] {
        pageReferences
    }

    func payload(
        for page: MangaPageReference
    ) async throws -> MangaPagePayload {
        guard loader.pages.indices.contains(page.index) else {
            throw MangaPageLoaderError.pageUnavailable
        }
        return MangaPagePayload(
            data: try loader.imageData(at: page.index),
            fileExtension: URL(
                fileURLWithPath: loader.pages[page.index].path
            ).pathExtension,
            embeddedTextRegions: try loader.mokuroRegions(at: page.index)
        )
    }

    func hasEmbeddedText(
        for chapter: MangaReadingChapter
    ) async throws -> Bool {
        try loader.hasMokuroMetadata()
    }

    func cancelPendingRequests() async {}
}

nonisolated struct UnavailableMangaPageContentProvider:
    MangaPageContentProvider
{
    func pages(
        for chapter: MangaReadingChapter
    ) async throws -> [MangaPageReference] {
        throw MangaPageLoaderError.sourceUnavailable
    }

    func payload(
        for page: MangaPageReference
    ) async throws -> MangaPagePayload {
        throw MangaPageLoaderError.pageUnavailable
    }

    func hasEmbeddedText(
        for chapter: MangaReadingChapter
    ) async throws -> Bool {
        false
    }

    func cancelPendingRequests() async {}
}

actor SuwayomiMangaPageContentProvider:
    MangaPageContentProvider
{
    private static let maximumPageCacheBytes: Int64 =
        1_024 * 1_024 * 1_024
    private static let maximumPageCacheFiles = 1_024

    private struct InFlightPageRequest {
        let id: UUID
        let task: Task<Data, Error>
    }

    private struct PageLocation: Sendable {
        let mangaID: Int
        let sourceOrder: Int
        let pageIndex: Int
    }

    private let client: SuwayomiClient
    private let serverID: String
    private let profileID: String
    private let memoryCache = NSCache<NSString, NSData>()
    private let cacheDirectory: URL
    private var generation = UUID()
    private var locations: [String: PageLocation] = [:]
    private var inFlightPageRequests: [String: InFlightPageRequest] = [:]

    init(
        client: SuwayomiClient,
        profileID: String
    ) async throws {
        self.client = client
        self.profileID = profileID
        serverID = client.serverID
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
        cacheDirectory = try Self.makeCacheDirectory(
            profileID: profileID,
            serverID: serverID
        )
        Self.pruneCache(in: cacheDirectory, protecting: nil)
    }

    func pages(
        for chapter: MangaReadingChapter
    ) async throws -> [MangaPageReference] {
        guard let remote = chapter.suwayomiChapter else {
            throw SuwayomiConnectorError.chapterUnavailable
        }
        let requestedGeneration = generation
        let prepared = try await client.prepareChapter(
            mangaID: remote.mangaId,
            sourceOrder: remote.index
        )
        guard requestedGeneration == generation else {
            throw CancellationError()
        }
        guard prepared.pageCount > 0 else {
            throw SuwayomiConnectorError.chapterUnavailable
        }
        return (0..<prepared.pageCount).map { index in
            let identity = SuwayomiIdentity.sha256(
                [
                    profileID,
                    serverID,
                    String(prepared.id),
                    String(prepared.fetchedAt),
                    String(prepared.pageCount),
                    String(index),
                ].joined(separator: "\u{1f}")
            )
            locations[identity] = PageLocation(
                mangaID: prepared.mangaId,
                sourceOrder: prepared.index,
                pageIndex: index
            )
            return MangaPageReference(
                id: identity,
                index: index,
                displayPath: String(
                    format: "suwayomi-%06d.jpg",
                    index
                ),
                ocrCacheIdentity: identity,
                pageURL: client.pageURL(
                    mangaID: prepared.mangaId,
                    sourceOrder: prepared.index,
                    pageIndex: index
                ).absoluteString,
                imageURL: nil
            )
        }
    }

    func payload(
        for page: MangaPageReference
    ) async throws -> MangaPagePayload {
        let requestedGeneration = generation
        let key = page.id as NSString
        if let cached = memoryCache.object(forKey: key) {
            return makePayload(
                data: cached as Data
            )
        }
        let diskURL = cacheDirectory.appendingPathComponent(page.id)
        if let values = try? diskURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let size = values.fileSize,
        size > 0,
        size <= SuwayomiConstants.maximumImageBytes,
        let data = try? Data(
            contentsOf: diskURL,
            options: [.mappedIfSafe]
        ) {
            memoryCache.setObject(
                data as NSData,
                forKey: key,
                cost: data.count
            )
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: diskURL.path
            )
            return makePayload(data: data)
        }
        guard let location = locations[page.id] else {
            throw SuwayomiConnectorError.chapterUnavailable
        }
        let request: InFlightPageRequest
        if let inFlight = inFlightPageRequests[page.id] {
            request = inFlight
        } else {
            let requestID = UUID()
            let task = Task {
                try await client.pageData(
                    mangaID: location.mangaID,
                    sourceOrder: location.sourceOrder,
                    pageIndex: location.pageIndex
                )
            }
            request = InFlightPageRequest(id: requestID, task: task)
            inFlightPageRequests[page.id] = request
        }

        let data: Data
        do {
            data = try await request.task.value
        } catch {
            removeInFlightRequest(pageID: page.id, requestID: request.id)
            throw error
        }
        removeInFlightRequest(pageID: page.id, requestID: request.id)
        try Task.checkCancellation()
        guard generation == requestedGeneration else {
            throw CancellationError()
        }
        guard data.count <= SuwayomiConstants.maximumImageBytes else {
            throw SuwayomiConnectorError.responseTooLarge
        }
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
        if (try? data.write(to: diskURL, options: .atomic)) != nil {
            Self.pruneCache(
                in: cacheDirectory,
                protecting: diskURL
            )
        }
        return makePayload(data: data)
    }

    func hasEmbeddedText(
        for chapter: MangaReadingChapter
    ) async throws -> Bool {
        false
    }

    func cancelPendingRequests() async {
        generation = UUID()
        for request in inFlightPageRequests.values {
            request.task.cancel()
        }
        inFlightPageRequests.removeAll()
    }

    func prefetch(pages: [MangaPageReference]) async {
        await withTaskGroup(of: Void.self) { group in
            for page in pages.prefix(4) {
                group.addTask {
                    _ = try? await self.payload(for: page)
                }
            }
        }
    }

    private func makePayload(data: Data) -> MangaPagePayload {
        return MangaPagePayload(
            data: data,
            fileExtension: Self.detectedFileExtension(data),
            embeddedTextRegions: nil
        )
    }

    private func removeInFlightRequest(
        pageID: String,
        requestID: UUID
    ) {
        guard inFlightPageRequests[pageID]?.id == requestID else { return }
        inFlightPageRequests[pageID] = nil
    }

    private static func detectedFileExtension(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if bytes.count >= 12,
           Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46],
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
            return "webp"
        }
        return "jpg"
    }

    private static func makeCacheDirectory(
        profileID: String,
        serverID: String
    ) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        guard !profileID.isEmpty,
              profileID.unicodeScalars.allSatisfy(allowed.contains),
              profileID != ".",
              profileID != ".." else {
            throw ProfileRepositoryError.unsafeProfileID
        }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SuwayomiConnectorError.serverUnavailable
        }
        let directory = applicationSupport
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("SuwayomiCache", isDirectory: true)
            .appendingPathComponent(serverID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func pruneCache(
        in directory: URL,
        protecting protectedURL: URL?
    ) {
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        var entries: [(url: URL, size: Int64, modifiedAt: Date)] =
            urls.compactMap { url in
                guard let values = try? url.resourceValues(
                    forKeys: resourceKeys
                ),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let size = values.fileSize,
                size >= 0 else {
                    return nil
                }
                return (
                    url.standardizedFileURL,
                    Int64(size),
                    values.contentModificationDate ?? .distantPast
                )
            }
        entries.sort { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt < rhs.modifiedAt
            }
            return lhs.url.path < rhs.url.path
        }

        var totalBytes = entries.reduce(Int64(0)) { $0 + $1.size }
        let protectedURL = protectedURL?.standardizedFileURL
        while entries.count > maximumPageCacheFiles
            || totalBytes > maximumPageCacheBytes {
            guard let removalIndex = entries.firstIndex(where: {
                $0.url != protectedURL
            }) else {
                return
            }
            let entry = entries.remove(at: removalIndex)
            do {
                try FileManager.default.removeItem(at: entry.url)
                totalBytes -= entry.size
            } catch {
                continue
            }
        }
    }
}
