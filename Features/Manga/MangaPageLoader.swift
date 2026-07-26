import AppKit
import Foundation
import ImageIO
import ZIPFoundation

nonisolated enum MangaPageLoaderError: LocalizedError {
    case sourceUnavailable
    case unsupportedContainer
    case pageUnavailable
    case pageTooLarge

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            String(localized: "The manga source is no longer available.")
        case .unsupportedContainer:
            String(localized: "This manga format is not supported.")
        case .pageUnavailable:
            String(localized: "The manga page could not be loaded.")
        case .pageTooLarge:
            String(localized: "The manga page is too large to open safely.")
        }
    }
}

nonisolated struct MangaMokuroArchiveBook: Equatable, Sendable {
    let metadataPath: String
    let title: String
    let imagePaths: [String]
}

nonisolated final class MangaPageLoader: @unchecked Sendable {
    static let maximumExpandedPageBytes: UInt64 = 256 * 1_024 * 1_024
    static let maximumMokuroMetadataBytes: UInt64 = 64 * 1_024 * 1_024
    static let maximumEPUBDocumentBytes: UInt64 = 16 * 1_024 * 1_024

    let pages: [MangaPageDescriptor]

    private let sourceURL: URL
    private let itemURL: URL
    private let item: MangaLibraryItem
    private let isAccessingSecurityScope: Bool
    private let lock = NSLock()
    private let dataCache = NSCache<NSNumber, NSData>()
    private var didResolveMokuroData = false
    private var cachedMokuroData: Data?

    init(item: MangaLibraryItem, source: MangaLibrarySource) throws {
        var isStale = false
        sourceURL = try URL(
            resolvingBookmarkData: source.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
        isAccessingSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        self.item = item
        let resolvedItemURL = source.kind == .archive
            ? sourceURL
            : sourceURL.appendingPathComponent(item.relativePath).standardizedFileURL
        if source.kind != .archive,
           !Self.contains(resolvedItemURL, inside: sourceURL) {
            if isAccessingSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            throw MangaPageLoaderError.sourceUnavailable
        }
        itemURL = resolvedItemURL
        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            if isAccessingSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            throw MangaPageLoaderError.sourceUnavailable
        }
        do {
            pages = try Self.inspectPages(
                at: itemURL,
                kind: item.containerKind,
                archiveMetadataPath: source.kind == .archive
                    && item.containerKind == .zipArchive
                    && !item.relativePath.isEmpty
                    ? item.relativePath
                    : nil
            )
        } catch {
            if isAccessingSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
        dataCache.totalCostLimit = 96 * 1_024 * 1_024
    }

    deinit {
        if isAccessingSecurityScope {
            sourceURL.stopAccessingSecurityScopedResource()
        }
    }

    func imageData(at index: Int) throws -> Data {
        guard pages.indices.contains(index) else {
            throw MangaPageLoaderError.pageUnavailable
        }
        if let cached = dataCache.object(forKey: NSNumber(value: index)) {
            return cached as Data
        }

        let data = try lock.withLock {
            switch item.containerKind {
            case .directory:
                let pageURL = itemURL.appendingPathComponent(pages[index].path)
                let values = try pageURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   UInt64(fileSize) > Self.maximumExpandedPageBytes {
                    throw MangaPageLoaderError.pageTooLarge
                }
                return try Data(contentsOf: pageURL, options: [.mappedIfSafe])
            case .zipArchive, .epubArchive:
                let archive = try Archive(url: itemURL, accessMode: .read)
                guard let entry = archive.first(where: { $0.path == pages[index].path }) else {
                    throw MangaPageLoaderError.pageUnavailable
                }
                guard entry.uncompressedSize <= Self.maximumExpandedPageBytes else {
                    throw MangaPageLoaderError.pageTooLarge
                }
                var data = Data()
                data.reserveCapacity(Int(entry.uncompressedSize))
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                return data
            }
        }
        dataCache.setObject(data as NSData, forKey: NSNumber(value: index), cost: data.count)
        return data
    }

    func mokuroRegions(at index: Int) throws -> [MangaOCRTextRegion]? {
        guard pages.indices.contains(index) else {
            throw MangaPageLoaderError.pageUnavailable
        }
        let metadata = try lock.withLock {
            try resolveMokuroData()
        }
        guard let metadata else { return nil }
        return try MangaMokuroParser.regions(
            in: metadata,
            pagePath: pages[index].path,
            pageIndex: index
        )
    }

    func hasMokuroMetadata() throws -> Bool {
        try lock.withLock {
            try resolveMokuroData() != nil
        }
    }

    static func inspectPages(
        at url: URL,
        kind: MangaContainerKind,
        archiveMetadataPath: String? = nil
    ) throws -> [MangaPageDescriptor] {
        let paths: [String]
        switch kind {
        case .directory:
            paths = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { candidate in
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && MangaMediaTypes.isImage(candidate)
            }
            .map(\.lastPathComponent)
        case .zipArchive:
            let archive = try Archive(url: url, accessMode: .read)
            if let archiveMetadataPath {
                guard let book = try mokuroArchiveBooks(in: archive).first(where: {
                    $0.metadataPath == archiveMetadataPath
                }) else {
                    throw MangaPageLoaderError.pageUnavailable
                }
                paths = book.imagePaths
            } else {
                paths = archive.compactMap { entry in
                    guard entry.type == .file,
                          MangaMediaTypes.isImagePath(entry.path),
                          !Self.isUnsafeArchivePath(entry.path),
                          !Self.isIgnoredArchivePagePath(entry.path) else {
                        return nil
                    }
                    return entry.path
                }
            }
        case .epubArchive:
            do {
                let archive = try Archive(url: url, accessMode: .read)
                paths = try inspectEPUBPages(in: archive)
            } catch {
                throw MangaPageLoaderError.unsupportedContainer
            }
        }

        let orderedPaths = kind == .epubArchive
            ? paths
            : paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return orderedPaths
            .enumerated()
            .map { MangaPageDescriptor(index: $0.offset, path: $0.element) }
    }

    static func coverData(
        at url: URL,
        kind: MangaContainerKind,
        firstPagePath: String? = nil,
        archiveMetadataPath: String? = nil
    ) throws -> Data? {
        let resolvedFirstPath: String?
        if let firstPagePath {
            resolvedFirstPath = firstPagePath
        } else {
            resolvedFirstPath = try inspectPages(
                at: url,
                kind: kind,
                archiveMetadataPath: archiveMetadataPath
            ).first?.path
        }
        guard let firstPath = resolvedFirstPath else {
            return nil
        }
        switch kind {
        case .directory:
            let pageURL = url.appendingPathComponent(firstPath)
            let values = try pageURL.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize,
               UInt64(fileSize) > maximumExpandedPageBytes {
                throw MangaPageLoaderError.pageTooLarge
            }
            return try Data(
                contentsOf: pageURL,
                options: [.mappedIfSafe]
            )
        case .zipArchive, .epubArchive:
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive.first(where: { $0.path == firstPath }),
                  entry.uncompressedSize <= maximumExpandedPageBytes else {
                return nil
            }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return data
        }
    }

    private func resolveMokuroData() throws -> Data? {
        if didResolveMokuroData {
            return cachedMokuroData
        }
        didResolveMokuroData = true
        cachedMokuroData = try Self.mokuroData(
            at: itemURL,
            kind: item.containerKind,
            archiveMetadataPath: item.containerKind == .zipArchive
                && !item.relativePath.isEmpty
                ? item.relativePath
                : nil
        )
        return cachedMokuroData
    }

    static func hasMokuroMetadata(
        at itemURL: URL,
        kind: MangaContainerKind
    ) -> Bool {
        if kind == .zipArchive,
           let books = try? mokuroArchiveBooks(at: itemURL),
           !books.isEmpty {
            return true
        }
        guard let data = try? mokuroData(at: itemURL, kind: kind) else {
            return false
        }
        return MangaMokuroParser.isMetadata(data)
    }

    static func mokuroArchiveBooks(
        at itemURL: URL
    ) throws -> [MangaMokuroArchiveBook] {
        let archive = try Archive(url: itemURL, accessMode: .read)
        return try mokuroArchiveBooks(in: archive)
    }

    static func mokuroDirectoryURLs(
        at root: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var directories: [URL] = []
        if try isMokuroImageDirectory(root, fileManager: fileManager) {
            directories.append(root)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MangaPageLoaderError.sourceUnavailable
        }
        for case let candidate as URL in enumerator {
            try Task.checkCancellation()
            let values = try candidate.resourceValues(forKeys: keys)
            guard values.isDirectory == true else { continue }
            if values.isHidden == true || values.isPackage == true {
                enumerator.skipDescendants()
                continue
            }
            if try isMokuroImageDirectory(candidate, fileManager: fileManager) {
                directories.append(candidate)
                enumerator.skipDescendants()
            }
        }
        return directories.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private static func mokuroData(
        at itemURL: URL,
        kind: MangaContainerKind,
        archiveMetadataPath: String? = nil
    ) throws -> Data? {
        let candidates: [URL]
        switch kind {
        case .directory:
            var urls = [
                itemURL.appendingPathExtension("mokuro"),
                itemURL.appendingPathExtension("json"),
                itemURL.appendingPathComponent(".mokuro"),
                itemURL.appendingPathComponent("mokuro.json"),
            ]
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: itemURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            ) {
                urls.append(contentsOf: contents.filter { url in
                    let name = url.lastPathComponent.lowercased()
                    return name.hasSuffix(".mokuro") || name == "mokuro.json"
                })
            }
            candidates = uniqueURLs(urls)
        case .zipArchive, .epubArchive:
            candidates = [
                itemURL.deletingPathExtension().appendingPathExtension("mokuro"),
            ]
        }

        for candidate in candidates {
            let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            if let fileSize = values?.fileSize,
               UInt64(fileSize) > Self.maximumMokuroMetadataBytes {
                throw MangaMokuroError.invalidMetadata
            }
            return try Data(
                contentsOf: candidate,
                options: [.mappedIfSafe]
            )
        }

        if kind == .zipArchive {
            let archive = try Archive(url: itemURL, accessMode: .read)
            if let archiveMetadataPath {
                guard !isUnsafeArchivePath(archiveMetadataPath),
                      let entry = archive.first(where: {
                          $0.type == .file && $0.path == archiveMetadataPath
                      }) else {
                    return nil
                }
                return try archiveData(
                    entry: entry,
                    in: archive,
                    maximumBytes: maximumMokuroMetadataBytes
                )
            }
            let metadataEntries = archive.filter { entry in
                guard entry.type == .file, !isUnsafeArchivePath(entry.path) else {
                    return false
                }
                let name = URL(fileURLWithPath: entry.path).lastPathComponent.lowercased()
                return name.hasSuffix(".mokuro") || name == "mokuro.json"
            }.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            if let entry = metadataEntries.first {
                return try archiveData(
                    entry: entry,
                    in: archive,
                    maximumBytes: maximumMokuroMetadataBytes
                )
            }
        }

        let adjacentJSON = itemURL
            .deletingPathExtension()
            .appendingPathExtension("json")
        let values = try? adjacentJSON.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true else { return nil }
        if let fileSize = values?.fileSize,
           UInt64(fileSize) > maximumMokuroMetadataBytes {
            throw MangaMokuroError.invalidMetadata
        }
        return try Data(contentsOf: adjacentJSON, options: [.mappedIfSafe])
    }

    private static func mokuroArchiveBooks(
        in archive: Archive
    ) throws -> [MangaMokuroArchiveBook] {
        let imageEntries = archive.filter { entry in
            entry.type == .file
                && MangaMediaTypes.isImagePath(entry.path)
                && !isUnsafeArchivePath(entry.path)
        }
        var imagePathsByLowercase: [String: String] = [:]
        for entry in imageEntries {
            imagePathsByLowercase[entry.path.lowercased(), default: entry.path] = entry.path
        }
        let metadataEntries = archive.filter { entry in
            guard entry.type == .file, !isUnsafeArchivePath(entry.path) else {
                return false
            }
            let name = URL(fileURLWithPath: entry.path).lastPathComponent.lowercased()
            return name.hasSuffix(".mokuro") || name == "mokuro.json"
        }.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        var books: [MangaMokuroArchiveBook] = []
        var seenPageSets: Set<[String]> = []
        let rootsWithMultipleMetadata = Dictionary(
            grouping: metadataEntries,
            by: { NSString(string: $0.path).deletingLastPathComponent.lowercased() }
        ).mapValues(\.count)

        for entry in metadataEntries {
            let data = try archiveData(
                entry: entry,
                in: archive,
                maximumBytes: maximumMokuroMetadataBytes
            )
            guard let referencedPaths = try? MangaMokuroParser.pagePaths(in: data),
                  !referencedPaths.isEmpty else {
                continue
            }
            let root = NSString(string: entry.path).deletingLastPathComponent
            let rootPrefix = root.isEmpty ? "" : "\(root)/"
            let imagesInRoot = imageEntries.map(\.path).filter {
                rootPrefix.isEmpty || $0.lowercased().hasPrefix(rootPrefix.lowercased())
            }
            let metadataName = URL(fileURLWithPath: entry.path)
                .deletingPathExtension()
                .lastPathComponent
            let siblingImageRoot: String?
            if metadataName.caseInsensitiveCompare("mokuro") == .orderedSame {
                siblingImageRoot = nil
            } else {
                siblingImageRoot = root.isEmpty
                    ? metadataName
                    : NSString(string: root).appendingPathComponent(metadataName)
            }
            let imagesInSiblingRoot: [String] = siblingImageRoot.map { siblingImageRoot in
                let prefix = "\(siblingImageRoot)/".lowercased()
                return imagesInRoot.filter { $0.lowercased().hasPrefix(prefix) }
            } ?? []
            var resolvedImagePaths: [String] = []
            for reference in referencedPaths {
                if let siblingImageRoot,
                   let siblingResolved = MangaEPUBParser.resolve(
                       reference: reference,
                       relativeTo: "\(siblingImageRoot)/.mokuro"
                   ),
                   let exact = imagePathsByLowercase[siblingResolved.lowercased()] {
                    resolvedImagePaths.append(exact)
                    continue
                }
                let resolved = MangaEPUBParser.resolve(
                    reference: reference,
                    relativeTo: entry.path
                )
                if let resolved,
                   let exact = imagePathsByLowercase[resolved.lowercased()] {
                    resolvedImagePaths.append(exact)
                    continue
                }
                let basename = URL(fileURLWithPath: reference).lastPathComponent
                let siblingMatches = imagesInSiblingRoot.filter {
                    URL(fileURLWithPath: $0).lastPathComponent
                        .caseInsensitiveCompare(basename) == .orderedSame
                }
                if siblingMatches.count == 1, let match = siblingMatches.first {
                    resolvedImagePaths.append(match)
                    continue
                }
                let rootMatches = imagesInRoot.filter {
                    URL(fileURLWithPath: $0).lastPathComponent
                        .caseInsensitiveCompare(basename) == .orderedSame
                }
                if rootMatches.count == 1, let match = rootMatches.first {
                    resolvedImagePaths.append(match)
                }
            }
            guard !resolvedImagePaths.isEmpty,
                  seenPageSets.insert(resolvedImagePaths.map { $0.lowercased() }).inserted else {
                continue
            }

            let title: String
            if !root.isEmpty, rootsWithMultipleMetadata[root.lowercased(), default: 0] == 1 {
                title = URL(fileURLWithPath: root).lastPathComponent
            } else if metadataName.caseInsensitiveCompare("mokuro") == .orderedSame,
                      !root.isEmpty {
                title = URL(fileURLWithPath: root).lastPathComponent
            } else {
                title = metadataName
            }
            books.append(
                MangaMokuroArchiveBook(
                    metadataPath: entry.path,
                    title: title,
                    imagePaths: resolvedImagePaths
                )
            )
        }
        return books
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var paths: Set<String> = []
        return urls.filter {
            paths.insert($0.standardizedFileURL.path).inserted
        }
    }

    private static func contains(_ candidate: URL, inside root: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func isMokuroImageDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let containsImages = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).contains { candidate in
            let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && MangaMediaTypes.isImage(candidate)
        }
        return containsImages
            && hasMokuroMetadata(at: directory, kind: .directory)
    }

    private static func isUnsafeArchivePath(_ path: String) -> Bool {
        let components = NSString(string: path).standardizingPath.split(separator: "/")
        return path.hasPrefix("/") || components.contains("..")
    }

    private static func isIgnoredArchivePagePath(_ path: String) -> Bool {
        path.split(separator: "/").contains { component in
            component == "__MACOSX" || component.hasPrefix(".")
        }
    }

    private static func inspectEPUBPages(in archive: Archive) throws -> [String] {
        let containerData = try archiveData(
            at: "META-INF/container.xml",
            in: archive,
            maximumBytes: maximumEPUBDocumentBytes
        )
        let packagePath = try MangaEPUBParser.packagePath(in: containerData)
        let packageData = try archiveData(
            at: packagePath,
            in: archive,
            maximumBytes: maximumEPUBDocumentBytes
        )
        let package = try MangaEPUBParser.package(
            at: packagePath,
            data: packageData
        )
        let availablePaths = Set(archive.compactMap { entry in
            entry.type == .file && !isUnsafeArchivePath(entry.path)
                ? entry.path
                : nil
        })
        return try package.orderedImagePaths { path in
            guard availablePaths.contains(path),
                  let entry = archive.first(where: { $0.path == path }),
                  entry.uncompressedSize <= maximumEPUBDocumentBytes else {
                return nil
            }
            return try archiveData(
                entry: entry,
                in: archive,
                maximumBytes: maximumEPUBDocumentBytes
            )
        }.filter(availablePaths.contains)
    }

    private static func archiveData(
        at path: String,
        in archive: Archive,
        maximumBytes: UInt64
    ) throws -> Data {
        guard !isUnsafeArchivePath(path),
              let entry = archive.first(where: { $0.path == path }) else {
            throw MangaPageLoaderError.unsupportedContainer
        }
        return try archiveData(
            entry: entry,
            in: archive,
            maximumBytes: maximumBytes
        )
    }

    private static func archiveData(
        entry: Entry,
        in archive: Archive,
        maximumBytes: UInt64
    ) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= maximumBytes else {
            throw MangaPageLoaderError.pageTooLarge
        }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }
}

nonisolated private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
