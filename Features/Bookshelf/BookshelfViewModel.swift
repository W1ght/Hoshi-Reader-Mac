//
//  BookshelfViewModel.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

enum BookImportResult: Equatable {
    case imported
    case alreadyExists
}

@Observable
@MainActor
class BookshelfViewModel {
    var books: [BookMetadata] = []
    var shelves: [BookShelf] = []
    var googleDriveBooks: [BookMetadata] = []
    var isImporting: Bool = false
    var shouldShowError: Bool = false
    var errorMessage: String = ""
    var shouldShowSuccess: Bool = false
    var successMessage: String = ""
    var isSyncing: Bool = false
    var isDownloading: Bool = false
    var isLoadingGoogleDriveBooks: Bool = false
    var isInitialPresentationReady: Bool = false
    var importBooksProgress: String?
    var downloadingBooks: [UUID: Double] = [:]
    
    private var bookProgress: [UUID: Double] = [:]
    private var googleDriveSyncFiles: [UUID: DriveSyncFiles] = [:]
    private var manualBookOrder: [UUID] = []

    func prepareInitialPresentation() async {
        guard !isInitialPresentationReady else { return }
        loadBooks()
        await CoverThumbnailCache.preheat(
            urls: books.compactMap(\.coverURL),
            maxPixelSize: 768
        )
        guard !Task.isCancelled else { return }
        isInitialPresentationReady = true
    }
    
    func loadBooks() {
        do {
            books = try BookStorage.loadAllBooks()
            loadBookProgress()
            loadShelves()
            loadManualBookOrder()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func loadShelves() {
        shelves = BookStorage.loadShelves() ?? []
        normalizeShelves()
    }
    
    func saveShelves() {
        guard let directory = try? BookStorage.getBooksDirectory() else { return }
        try? BookStorage.save(shelves, inside: directory, as: FileNames.shelves)
    }
    
    func createShelf(name: String) {
        if !shelves.contains(where: { $0.name == name }) {
            shelves.append(BookShelf(name: name, bookIds: []))
            saveShelves()
        }
    }
    
    func deleteShelf(name: String) {
        shelves.removeAll(where: { $0.name == name })
        saveShelves()
    }
    
    func moveShelves(from source: IndexSet, to destination: Int) {
        shelves.move(fromOffsets: source, toOffset: destination)
        saveShelves()
    }
    
    func moveBook(_ id: UUID, to name: String?) {
        for i in shelves.indices {
            shelves[i].bookIds.removeAll { $0 == id }
        }
        if let name,
           let index = shelves.firstIndex(where: { $0.name == name }) {
            shelves[index].bookIds.append(id)
        }
        saveShelves()
    }
    
    func moveBooks(_ books: Set<BookMetadata>, to name: String?) {
        for book in books {
            moveBook(book.id, to: name)
        }
    }

    func moveBook(_ sourceID: UUID, in section: ShelfSection, before targetID: UUID) {
        guard !section.isReading, !section.isGoogleDrive else { return }

        if let shelf = section.shelf,
           let shelfIndex = shelves.firstIndex(where: { $0.name == shelf.name }) {
            var order = shelves[shelfIndex].bookIds
            reorder(&order, sourceID: sourceID, targetID: targetID, fallbackIDs: section.books.map(\.id))
            shelves[shelfIndex].bookIds = order
            saveShelves()
            return
        }

        let sectionIDs = section.books.map(\.id)
        var sectionOrder = manualBookOrder.filter { sectionIDs.contains($0) }
        appendMissingIDs(sectionIDs, to: &sectionOrder)
        reorder(&sectionOrder, sourceID: sourceID, targetID: targetID, fallbackIDs: sectionIDs)

        manualBookOrder.removeAll { sectionIDs.contains($0) }
        manualBookOrder.append(contentsOf: sectionOrder)
        persistManualBookOrder()
    }
    
    func deleteBooks(_ books: Set<BookMetadata>) {
        for book in books {
            deleteBook(book)
        }
    }
    
    func shelfSections(sortedBy: SortOption, showReading: Bool = false) -> [ShelfSection] {
        var sections: [ShelfSection] = []
        
        if showReading {
            let reading = books.filter {
                let p = progress(for: $0)
                return p > 0 && p < 0.999
            }
            if !reading.isEmpty {
                sections.append(ShelfSection(
                    shelf: BookShelf(name: "Reading", bookIds: []),
                    books: sortBooks(reading, by: sortedBy, manualOrder: manualBookOrder),
                    isReading: true
                ))
            }
        }
        
        for shelf in shelves {
            let shelvedBooks = books.filter { shelf.bookIds.contains($0.id) }
            sections.append(ShelfSection(
                shelf: shelf,
                books: sortBooks(shelvedBooks, by: sortedBy, manualOrder: shelf.bookIds)
            ))
        }

        if !googleDriveBooks.isEmpty {
            sections.append(ShelfSection(
                shelf: BookShelf(name: "Google Drive", bookIds: []),
                books: sortBooks(googleDriveBooks, by: sortedBy == .manual ? .title : sortedBy),
                isGoogleDrive: true
            ))
        }
        
        let shelvedIds = Set(shelves.flatMap { $0.bookIds })
        let unshelved = books.filter { !shelvedIds.contains($0.id) }
        sections.append(ShelfSection(
            shelf: nil,
            books: sortBooks(unshelved, by: sortedBy, manualOrder: manualBookOrder)
        ))
        
        return sections
    }
    
    func sortBooks(_ books: [BookMetadata], by option: SortOption) -> [BookMetadata] {
        sortBooks(books, by: option, manualOrder: manualBookOrder)
    }

    func sortBooks(_ books: [BookMetadata], by option: SortOption, manualOrder: [UUID]) -> [BookMetadata] {
        switch option {
        case .manual:
            let order = Dictionary(uniqueKeysWithValues: manualOrder.enumerated().map { ($1, $0) })
            return books.sorted {
                switch (order[$0.id], order[$1.id]) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                }
            }
        case .recent:
            return books.sorted { $0.lastAccess > $1.lastAccess }
        case .title:
            return books.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
    }
    
    func sortedBooks(by option: SortOption) -> [BookMetadata] {
        sortBooks(books, by: option)
    }
    
    private func loadBookProgress() {
        guard let directory = try? BookStorage.getBooksDirectory() else {
            return
        }
        
        for book in books {
            let root = directory.appendingPathComponent(book.folder)
            
            let bookInfo = BookStorage.loadBookInfo(root: root)
            let bookmark = BookStorage.loadBookmark(root: root)
            
            if let total = bookInfo?.characterCount, total > 0,
               let current = bookmark?.characterCount {
                bookProgress[book.id] = Double(current) / Double(total)
            } else {
                bookProgress[book.id] = 0.0
            }
        }
    }
    
    func progress(for book: BookMetadata) -> Double {
        bookProgress[book.id] ?? 0.0
    }
    
    func deleteBook(_ book: BookMetadata) {
        do {
            let bookURL = try BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
            try BookStorage.delete(at: bookURL)
            books.removeAll { $0.id == book.id }
            for i in shelves.indices {
                shelves[i].bookIds.removeAll { $0 == book.id }
            }
            saveShelves()
            manualBookOrder.removeAll { $0 == book.id }
            persistManualBookOrder()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func renameBook(_ book: BookMetadata, title: String) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else {
            return
        }
        
        let bookURL = try! BookStorage.getBooksDirectory().appendingPathComponent(book.folder)
        books[index].renamedTitle = title.isEmpty ? nil : title
        try? BookStorage.save(books[index], inside: bookURL, as: FileNames.metadata)
    }

    func importBook(result: Result<URL, Error>) {
        do {
            let importResult = try importBook(from: try result.get())
            if importResult == .imported {
                loadBooks()
            }
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func importDownloadedBook(
        from url: URL,
        sourceID: String,
        isbn: String?
    ) throws -> BookImportResult {
        let result = try importBook(
            from: url,
            externalSourceID: sourceID,
            externalISBN: isbn
        )
        if result == .imported {
            loadBooks()
        }
        return result
    }

    func containsImportedBook(
        sourceID: String,
        isbn: String?,
        title: String
    ) -> Bool {
        if books.contains(where: { $0.externalSourceID == sourceID }) {
            return true
        }
        let normalizedISBN = isbn?.filter(\.isNumber)
        if let normalizedISBN, !normalizedISBN.isEmpty,
           books.contains(where: { $0.externalISBN?.filter(\.isNumber) == normalizedISBN }) {
            return true
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let folder = BookStorage.sanitizeFileName(title)
        return books.contains {
            $0.folder.caseInsensitiveCompare(folder) == .orderedSame
        }
    }
    
    func importBooks(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if urls.isEmpty {
                return
            }
            
            if urls.count == 1 {
                importBook(result: .success(urls[0]))
                return
            }
            
            importBooksProgress = "Importing 1 / \(urls.count)..."
            Task {
                defer { importBooksProgress = nil }
                await Task.yield()
                
                var failed: [String] = []
                for (index, url) in urls.enumerated() {
                    autoreleasepool {
                        do {
                            _ = try importBook(from: url)
                        } catch {
                            failed.append(url.lastPathComponent)
                        }
                    }
                    let next = index + 1
                    if next < urls.count {
                        importBooksProgress = "Importing \(next + 1) / \(urls.count)..."
                        await Task.yield()
                    }
                }
                loadBooks()
                
                if !failed.isEmpty {
                    showError(message: "Failed to import:\n\(failed.joined(separator: "\n"))")
                }
            }
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    func importDroppedEPUBs(_ urls: [URL]) -> Bool {
        let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
        guard !epubs.isEmpty else { return false }
        importBooks(result: .success(epubs))
        return true
    }
    
    func importRemoteBook(from url: URL) {
        isDownloading = true
        Task {
            defer {
                isDownloading = false
            }
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                _ = try processImport(sourceURL: tempURL)
                loadBooks()
            } catch {
                showError(message: String(localized: "Download failed: \(error.localizedDescription)"))
            }
        }
    }

    func syncBook(book: BookMetadata, direction: SyncDirection? = nil, syncBookData: Bool, syncStats: Bool, statsSyncMode: StatisticsSyncMode, syncAudioBook: Bool) {
        isSyncing = true
        Task {
            defer {
                isSyncing = false
            }
            do {
                let result = try await SyncManager.shared.syncBook(
                    book: book,
                    direction: direction,
                    syncBookData: syncBookData,
                    syncStats: syncStats,
                    statsSyncMode: statsSyncMode,
                    syncAudioBook: syncAudioBook
                )
                handleSyncResult(result)
            } catch {
                showError(message: String(localized: "Sync failed: \(error.localizedDescription)"))
            }
        }
    }

    func loadGoogleDriveBooks(suppressOfflineErrors: Bool = false) async {
        guard !isLoadingGoogleDriveBooks else { return }
        isLoadingGoogleDriveBooks = true
        defer { isLoadingGoogleDriveBooks = false }

        do {
            let root = try await GoogleDriveHandler.shared.findRootFolder()
            let folders = try await GoogleDriveHandler.shared.listBooks(rootFolder: root)
            var localTitles = Set<String>()
            for book in books {
                localTitles.insert(GoogleDriveHandler.sanitizeTtuFilename(book.title))
                localTitles.insert(GoogleDriveHandler.sanitizeTtuFilename(book.displayTitle))
            }
            let remoteFolders = folders.filter { !localTitles.contains($0.name) }
            let allFiles = try await GoogleDriveHandler.shared.listSyncFiles(folderIds: remoteFolders.map(\.id))
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("gdrive-covers")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            var results: [(BookMetadata, DriveSyncFiles)] = []
            for folder in remoteFolders {
                guard let files = allFiles[folder.id], files.bookData != nil else { continue }

                var cover: String?
                if let thumbnailURL = files.cover?.thumbnailLink?
                    .replacingOccurrences(of: "=s\\d+$", with: "=s768", options: .regularExpression),
                   let url = URL(string: thumbnailURL) {
                    let cached = cacheDir.appendingPathComponent(folder.id)
                    if !FileManager.default.fileExists(atPath: cached.path(percentEncoded: false)),
                       let (data, _) = try? await URLSession.shared.data(from: url) {
                        try? data.write(to: cached, options: .atomic)
                    }
                    if FileManager.default.fileExists(atPath: cached.path(percentEncoded: false)) {
                        cover = cached.path(percentEncoded: false)
                    }
                }

                let title = GoogleDriveHandler.desanitizeTtuFilename(folder.name)
                let book = BookMetadata(title: title, cover: cover, folder: folder.id, lastAccess: .distantPast)
                results.append((book, files))
            }

            var remoteSyncFiles: [UUID: DriveSyncFiles] = [:]
            for (book, files) in results {
                remoteSyncFiles[book.id] = files
                if let name = files.progress?.name.dropLast(5),
                   let value = name.split(separator: "_").last.flatMap({ Double($0) }) {
                    bookProgress[book.id] = value
                }
            }

            googleDriveBooks = results.map(\.0).sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
            googleDriveSyncFiles = remoteSyncFiles
        } catch let error as URLError where error.code == .cancelled {
        } catch let error as URLError where suppressOfflineErrors && [.notConnectedToInternet, .timedOut, .networkConnectionLost].contains(error.code) {
        } catch {
            showError(message: String(localized: "Failed to fetch books from Google Drive: \(error.localizedDescription)"))
        }
    }

    func importGoogleDriveBook(_ book: BookMetadata, syncStats: Bool, syncAudioBook: Bool) {
        guard let syncFiles = googleDriveSyncFiles[book.id],
              downloadingBooks[book.id] == nil else {
            return
        }

        downloadingBooks[book.id] = 0
        Task {
            defer {
                downloadingBooks.removeValue(forKey: book.id)
            }
            do {
                _ = try await SyncManager.shared.importGoogleDriveBook(
                    syncFiles: syncFiles,
                    syncStats: syncStats,
                    syncAudioBook: syncAudioBook
                ) { progress in
                    self.downloadingBooks[book.id] = progress
                }
                googleDriveBooks.removeAll { $0.id == book.id }
                googleDriveSyncFiles.removeValue(forKey: book.id)
                loadBooks()
            } catch {
                showError(message: String(localized: "Failed to import book from Google Drive: \(error.localizedDescription)"))
            }
        }
    }

    func deleteGoogleDriveBook(_ book: BookMetadata) {
        guard downloadingBooks[book.id] == nil else { return }
        Task {
            do {
                try await GoogleDriveHandler.shared.trashFile(fileId: book.folder)
                googleDriveBooks.removeAll { $0.id == book.id }
                googleDriveSyncFiles.removeValue(forKey: book.id)
                bookProgress.removeValue(forKey: book.id)
            } catch {
                showError(message: String(localized: "Failed to delete book from Google Drive: \(error.localizedDescription)"))
            }
        }
    }
    
    private func handleSyncResult(_ result: SyncResult) {
        switch result {
        case .synced(let title):
            showSuccess(message: String(localized: "\(title) is already synced"))
        case .imported(let title, let characterCount):
            loadBookProgress()
            showSuccess(message: String(localized: "Synced \(title) from ッツ\n\(characterCount) characters"))
        case .exported(let title, let characterCount):
            showSuccess(message: String(localized: "Synced \(title) to ッツ\n\(characterCount) characters"))
        case .skipped:
            break
        }
    }
    
    func markRead(book: BookMetadata) {
        let directory = try! BookStorage.getBooksDirectory()
        let url = directory.appendingPathComponent(book.folder)
        guard let bookInfo = BookStorage.loadBookInfo(root: url) else { return }
        
        let bookmark = Bookmark(
            chapterIndex: bookInfo.chapterInfo.values.compactMap(\.spineIndex).max() ?? 0,
            progress: 1,
            characterCount: bookInfo.characterCount,
            lastModified: Date()
        )
        
        try? BookStorage.save(bookmark, inside: url, as: FileNames.bookmark)
        loadBookProgress()
    }
    
    func clearInbox() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let inboxDirectory = documentsDirectory.appendingPathComponent("Inbox")
        guard FileManager.default.fileExists(atPath: inboxDirectory.path(percentEncoded: false)),
              let inboxContents = try? FileManager.default.contentsOfDirectory(
                at: inboxDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return
        }
        
        for item in inboxContents {
            try? FileManager.default.removeItem(at: item)
        }
    }
    
    private func importBook(
        from url: URL,
        externalSourceID: String? = nil,
        externalISBN: String? = nil
    ) throws -> BookImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try processImport(
            sourceURL: url,
            externalSourceID: externalSourceID,
            externalISBN: externalISBN
        )
    }
    
    private func processImport(
        sourceURL: URL,
        externalSourceID: String? = nil,
        externalISBN: String? = nil
    ) throws -> BookImportResult {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
        }
        
        let tempDocument = try BookStorage.loadEpub(tempURL)
        let title: String = {
            if let t = tempDocument.title, !t.isEmpty {
                return t
            }
            return sourceURL.deletingPathExtension().lastPathComponent
        }()
        
        let safeTitle = BookStorage.sanitizeFileName(title)
        
        let booksDir = try BookStorage.getBooksDirectory()
        let bookFolder = booksDir.appendingPathComponent(safeTitle)
        
        if FileManager.default.fileExists(atPath: bookFolder.path(percentEncoded: false)) {
            return .alreadyExists
        }
        
        try FileManager.default.createDirectory(at: bookFolder, withIntermediateDirectories: true)
        
        let localURL = bookFolder.appendingPathComponent(sourceURL.lastPathComponent)
        try BookStorage.copyFile(from: tempURL, to: "Books/\(safeTitle)/\(localURL.lastPathComponent)")
        
        let document = try BookStorage.loadEpub(localURL)
        try finalizeImport(
            localURL: localURL,
            bookFolder: bookFolder,
            document: document,
            title: title,
            externalSourceID: externalSourceID,
            externalISBN: externalISBN
        )
        return .imported
    }
    
    private func finalizeImport(
        localURL: URL,
        bookFolder: URL,
        document: EPUBDocument,
        title: String,
        externalSourceID: String?,
        externalISBN: String?
    ) throws {
        do {
            var coverURL: String?
            if let coverPath = findCoverInManifest(document: document) {
                let coverSourceURL = document.contentDirectory.appendingPathComponent(coverPath)
                let coverDestination = "Books/\(bookFolder.lastPathComponent)/\(URL(fileURLWithPath: coverPath).lastPathComponent)"
                try BookStorage.copyFile(from: coverSourceURL, to: coverDestination)
                coverURL = coverDestination
            }
            
            let metadata = BookMetadata(
                title: title,
                epub: localURL.lastPathComponent,
                cover: coverURL,
                folder: bookFolder.lastPathComponent,
                lastAccess: Date(),
                bookLanguage: document.metadata.language,
                externalSourceID: externalSourceID,
                externalISBN: externalISBN
            )
            
            let bookinfo = BookProcessor.process(document: document)
            
            try BookStorage.save(metadata, inside: bookFolder, as: FileNames.metadata)
            try BookStorage.save(bookinfo, inside: bookFolder, as: FileNames.bookinfo)
        } catch {
            try? BookStorage.delete(at: localURL)
            try? BookStorage.delete(at: bookFolder)
            throw error
        }
    }
    
    private func findCoverInManifest(document: EPUBDocument) -> String? {
        // EPUB3
        // <item href="Images/embed0028_HD.jpg" properties="cover-image" id="embed0028_HD" media-type="image/jpeg"/>
        if let coverItem = document.manifest.items.values.first(where: { $0.property?.contains("cover-image") == true }) {
            return coverItem.path
        }
        
        // EPUB2
        // <meta name="cover" content="cover"/>
        // <item id="cover" href="cover.jpeg" media-type="image/jpeg"/>
        if let coverId = document.metadata.coverId,
           let coverItem = document.manifest.items[coverId] {
            return coverItem.path
        }
        
        // fallbacks in case the epub doesn't conform to any standards
        let imageTypes: [EPUBMediaType] = [.jpeg, .png, .gif, .svg]
        if let coverItem = document.manifest.items.values.first(where: { $0.id.lowercased().contains("cover") }),
           imageTypes.contains(coverItem.mediaType) {
            return coverItem.path
        }
        if let firstImage = document.manifest.items.values.first(where: { imageTypes.contains($0.mediaType) }) {
            return firstImage.path
        }
        
        return nil
    }
    
    private func showError(message: String) {
        errorMessage = message
        shouldShowError = true
    }
    
    private func showSuccess(message: String) {
        successMessage = message
        shouldShowSuccess = true
    }

    private func loadManualBookOrder() {
        let bookIDs = books.map(\.id)
        manualBookOrder = BookStorage.loadBookOrder() ?? []
        let normalized = normalizedOrder(manualBookOrder, validIDs: Set(bookIDs), fallbackIDs: bookIDs)
        guard normalized != manualBookOrder else { return }
        manualBookOrder = normalized
        persistManualBookOrder()
    }

    private func normalizeShelves() {
        let validIDs = Set(books.map(\.id))
        var changed = false
        for index in shelves.indices {
            let normalized = normalizedOrder(shelves[index].bookIds, validIDs: validIDs, fallbackIDs: shelves[index].bookIds)
            if normalized != shelves[index].bookIds {
                shelves[index].bookIds = normalized
                changed = true
            }
        }
        if changed {
            saveShelves()
        }
    }

    private func normalizedOrder(_ order: [UUID], validIDs: Set<UUID>, fallbackIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in order where validIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        appendMissingIDs(fallbackIDs.filter { validIDs.contains($0) }, to: &result)
        return result
    }

    private func appendMissingIDs(_ ids: [UUID], to order: inout [UUID]) {
        var seen = Set(order)
        for id in ids where seen.insert(id).inserted {
            order.append(id)
        }
    }

    private func reorder(_ order: inout [UUID], sourceID: UUID, targetID: UUID, fallbackIDs: [UUID]) {
        appendMissingIDs(fallbackIDs, to: &order)
        guard let sourceIndex = order.firstIndex(of: sourceID),
              let targetIndex = order.firstIndex(of: targetID),
              let destination = BookReorder.destinationOffset(sourceIndex: sourceIndex, targetIndex: targetIndex) else {
            return
        }
        order.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }

    private func persistManualBookOrder() {
        do {
            try BookStorage.saveBookOrder(manualBookOrder)
        } catch {
            showError(message: error.localizedDescription)
        }
    }
}

struct ShelfSection: Identifiable {
    let shelf: BookShelf?
    var books: [BookMetadata]
    var isReading: Bool = false
    var isGoogleDrive: Bool = false
    
    var id: String {
        if isReading {
            return "__reading__"
        }
        if isGoogleDrive {
            return "__gdrive__"
        }
        return shelf.map { "shelf:\($0.name)" } ?? "unshelved"
    }
}
