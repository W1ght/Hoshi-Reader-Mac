//
//  BookStorage.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import EPUBKit
import Foundation
import ZIPFoundation

enum FileNames: Sendable {
    static let metadata = "metadata.json"
    static let bookmark = "bookmark.json"
    static let bookinfo = "bookinfo.json"
    static let bookOrder = "book_order.json"
    static let shelves = "shelves.json"
    static let statistics = "statistics.json"
    static let sasayakiMatch = "sasayaki_match.json"
    static let sasayakiPlayback = "sasayaki_playback.json"
    static let highlights = "highlights.json"
}

struct BookStorage {
    static func getAppDirectory() throws -> URL {
        guard let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BookStorageError.appDirectoryNotFound
        }
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    static func migrateFromDocuments() {
        guard let appSupport = try? getAppDirectory(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let migrated = UserDefaults.standard.bool(forKey: "migratedToAppSupport")
        guard !migrated else { return }
        
        let items = ["Books", "Fonts", "Dictionaries", "Audio", "anki_words.json", "anki_config.json"]
        for item in items {
            let src = documents.appendingPathComponent(item)
            let dst = appSupport.appendingPathComponent(item)
            guard FileManager.default.fileExists(atPath: src.path(percentEncoded: false)),
                  !FileManager.default.fileExists(atPath: dst.path(percentEncoded: false)) else { continue }
            try? FileManager.default.moveItem(at: src, to: dst)
        }
        
        UserDefaults.standard.set(true, forKey: "migratedToAppSupport")
    }
    
    static func migrateBooks() {
        guard let booksDir = try? getBooksDirectory(),
              FileManager.default.fileExists(atPath: booksDir.path(percentEncoded: false)) else { return }
        
        let migrated = UserDefaults.standard.bool(forKey: "migratedBooks")
        guard !migrated else {
            return
        }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: booksDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for folder in contents {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            
            let destination = folder.appendingPathComponent(folder.lastPathComponent).appendingPathExtension("epub")
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }
            
            let mimetype = folder.appendingPathComponent("mimetype")
            guard FileManager.default.fileExists(atPath: mimetype.path(percentEncoded: false)) else { continue }
            
            let metadata = loadMetadata(root: folder)
            let coverName = metadata?.cover.map { URL(fileURLWithPath: $0).lastPathComponent }
            guard (try? repackEpub(folder: folder, destination: destination, coverName: coverName)) != nil else {
                continue
            }
            
            if let metadata {
                var updated = BookMetadata(
                    id: metadata.id,
                    title: metadata.title,
                    epub: folder.lastPathComponent + ".epub",
                    cover: metadata.cover,
                    folder: metadata.folder,
                    lastAccess: metadata.lastAccess,
                    profileId: metadata.profileId,
                    bookLanguage: metadata.bookLanguage
                )
                updated.renamedTitle = metadata.renamedTitle
                try? save(updated, inside: folder, as: FileNames.metadata)
            }
        }
        
        UserDefaults.standard.set(true, forKey: "migratedBooks")
    }
    
    private static func repackEpub(folder: URL, destination: URL, coverName: String?) throws {
        let tempURL = destination.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tempURL)
        let archive = try Archive(url: tempURL, accessMode: .create, pathEncoding: .utf8)
        
        let mimetype = folder.appendingPathComponent("mimetype")
        try archive.addEntry(with: "mimetype", fileURL: mimetype, compressionMethod: .none)
        
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        var filesToRemove: [URL] = []
        var dirsToRemove: [URL] = []
        for case let url as URL in enumerator {
            let relPath = url.standardizedFileURL.pathComponents
                .dropFirst(folder.standardizedFileURL.pathComponents.count)
                .joined(separator: "/")
            
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                dirsToRemove.append(url)
                continue
            }
            
            if relPath == "mimetype" || url.pathExtension == "json" || url.pathExtension == "tmp" {
                continue
            }
            
            try archive.addEntry(with: relPath, fileURL: url, compressionMethod: .deflate)
            
            if relPath != coverName {
                filesToRemove.append(url)
            }
        }
        
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        filesToRemove.append(mimetype)
        for file in filesToRemove {
            try? FileManager.default.removeItem(at: file)
        }
        for dir in dirsToRemove.sorted(by: { $0.path.count > $1.path.count }) {
            try? FileManager.default.removeItem(at: dir)
        }
    }
    
    static func getBooksDirectory() throws -> URL {
        try getAppDirectory().appendingPathComponent("Books")
    }
    
    @discardableResult
    static func copySecurityScopedFile(from fileURL: URL, to destinationPath: String? = nil) throws -> URL {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BookStorageError.accessDenied
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        let appDirectory = try getAppDirectory()
        let destinationURL = appDirectory.appendingPathComponent(destinationPath ?? fileURL.lastPathComponent)
        
        let destinationFolder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        try replaceFile(at: destinationURL, with: fileURL)
        return destinationURL
    }
    
    @discardableResult
    static func copyFile(from fileURL: URL, to destinationPath: String) throws -> URL {
        let appDirectory = try getAppDirectory()
        let destinationURL = appDirectory.appendingPathComponent(destinationPath)
        
        if destinationURL.path(percentEncoded: false) == fileURL.path(percentEncoded: false) {
            return destinationURL
        }
        
        let destinationFolder = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        try replaceFile(at: destinationURL, with: fileURL)
        return destinationURL
    }
    
    private static func replaceFile(at destination: URL, with source: URL) throws {
        try delete(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    static func delete(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
    
    static func save<T: Encodable>(_ object: T, inside directory: URL, as fileName: String) throws {
        let targetURL = directory.appendingPathComponent(fileName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(object)
        
        try data.write(to: targetURL, options: .atomic)
    }
    
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    static func loadBookmark(root: URL) -> Bookmark? {
        load(Bookmark.self, from: root.appendingPathComponent(FileNames.bookmark))
    }
    
    static func loadBookInfo(root: URL) -> BookInfo? {
        load(BookInfo.self, from: root.appendingPathComponent(FileNames.bookinfo))
    }
    
    static func loadMetadata(root: URL) -> BookMetadata? {
        load(BookMetadata.self, from: root.appendingPathComponent(FileNames.metadata))
    }
    
    static func loadStatistics(root: URL) -> [Statistics]? {
        load([Statistics].self, from: root.appendingPathComponent(FileNames.statistics))
    }
    
    static func loadSasayakiMatch(root: URL) -> SasayakiMatchData? {
        load(SasayakiMatchData.self, from: root.appendingPathComponent(FileNames.sasayakiMatch))
    }
    
    static func loadSasayakiPlayback(root: URL) -> SasayakiPlaybackData? {
        load(SasayakiPlaybackData.self, from: root.appendingPathComponent(FileNames.sasayakiPlayback))
    }
    
    static func loadHighlights(root: URL) -> [Highlight]? {
        load([Highlight].self, from: root.appendingPathComponent(FileNames.highlights))
    }
    
    static func loadShelves() -> [BookShelf]? {
        load([BookShelf].self, from: try! getBooksDirectory().appendingPathComponent(FileNames.shelves))
    }

    static func loadBookOrder() -> [UUID]? {
        load([UUID].self, from: try! getBooksDirectory().appendingPathComponent(FileNames.bookOrder))
    }

    static func saveBookOrder(_ order: [UUID]) throws {
        try save(order, inside: try getBooksDirectory(), as: FileNames.bookOrder)
    }
    
    static func loadAllBooks() throws -> [BookMetadata] {
        let booksDirectory = try getBooksDirectory()
        
        if !FileManager.default.fileExists(atPath: booksDirectory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }
        
        var books: [BookMetadata] = []
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: booksDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for url in contents {
            let resources = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard resources.isDirectory == true else {
                continue
            }
            
            let metadataURL = url.appendingPathComponent(FileNames.metadata)
            
            if FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) {
                let data = try Data(contentsOf: metadataURL)
                let book = try JSONDecoder().decode(BookMetadata.self, from: data)
                books.append(book)
            }
        }
        
        return books
    }

    static func backfillBookLanguageIfNeeded(_ book: BookMetadata) -> BookMetadata {
        guard book.bookLanguage == nil, let epub = book.epub,
              let booksDirectory = try? getBooksDirectory() else { return book }
        let root = booksDirectory.appendingPathComponent(book.folder)
        let epubURL = root.appendingPathComponent(epub)
        guard let language = readEPUBLanguage(at: epubURL)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty else { return book }

        var updated = book
        updated.bookLanguage = language
        try? save(updated, inside: root, as: FileNames.metadata)
        return updated
    }

    static func readEPUBLanguage(at epubURL: URL) -> String? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: epubURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(
                at: epubURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return nil }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "opf" {
                if let data = try? Data(contentsOf: file), let language = languageFromOPF(data) {
                    return language
                }
            }
            return nil
        }

        guard let archive = try? Archive(url: epubURL, accessMode: .read, pathEncoding: .utf8),
              let containerEntry = archive["META-INF/container.xml"],
              let containerData = readArchiveEntry(containerEntry, from: archive),
              let container = String(data: containerData, encoding: .utf8),
              let packagePath = firstMatch(in: container, pattern: #"full-path\s*=\s*["']([^"']+)["']"#),
              let packageEntry = archive[packagePath],
              let packageData = readArchiveEntry(packageEntry, from: archive) else { return nil }
        return languageFromOPF(packageData)
    }

    private static func readArchiveEntry(_ entry: Entry, from archive: Archive) -> Data? {
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in data.append(chunk) }
            return data
        } catch {
            return nil
        }
    }

    private static func languageFromOPF(_ data: Data) -> String? {
        guard let package = String(data: data, encoding: .utf8) else { return nil }
        return firstMatch(
            in: package,
            pattern: #"<(?:[A-Za-z0-9_.-]+:)?language(?:\s[^>]*)?>([^<]+)</(?:[A-Za-z0-9_.-]+:)?language\s*>"#
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[range])
    }
    
    static func loadEpub(_ path: URL) throws -> EPUBDocument {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path.path(percentEncoded: false), isDirectory: &isDirectory),
           isDirectory.boolValue {
            let parser = EPUBParser()
            do {
                return try parser.parse(documentAt: path)
            } catch {
                throw BookStorageError.epubImportFailed(error)
            }
        }

        let tempDirectory = try getAppDirectory().appendingPathComponent("Temp")
        try? FileManager.default.removeItem(at: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let destination = tempDirectory.appendingPathComponent(path.deletingPathExtension().lastPathComponent)
        try FileManager.default.unzipItem(at: path, to: destination)
        
        let parser = EPUBParser()
        do {
            return try parser.parse(documentAt: destination)
        } catch {
            throw BookStorageError.epubImportFailed(error)
        }
    }

    static func sanitizeFileName(_ string: String) -> String {
        string
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.newlines).union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    enum BookStorageError: LocalizedError {
        case accessDenied
        case appDirectoryNotFound
        case epubImportFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return String(localized: "Could not access .epub file")
            case .appDirectoryNotFound:
                return String(localized: "App directory not found")
            case .epubImportFailed(let error):
                return String(localized: "Could not import .epub file: \(error.localizedDescription)")
            }
        }
    }
}
