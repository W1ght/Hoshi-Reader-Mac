import EPUBKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeBookshelfHomeView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var books: [NativeBookRow] = []
    @State private var isImporting = false
    @State private var isBusy = false
    @State private var alert: NativeBookshelfAlert?
    @State private var renameItem: NativeRenameBookItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            toolbar

            if let error = alert?.inlineError {
                ContentUnavailableView {
                    Label("书架读取失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if books.isEmpty {
                ContentUnavailableView {
                    Label("没有书籍", systemImage: "books.vertical")
                } description: {
                    Text("导入 EPUB 后会在这里显示本地书架。")
                } actions: {
                    Button {
                        isImporting = true
                    } label: {
                        Label("导入 EPUB", systemImage: "plus")
                    }
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(section.title)
                                    .font(.headline)
                                Text("\(section.books.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 14)], spacing: 14) {
                                ForEach(section.books) { book in
                                    NativeBookCard(
                                        book: book,
                                        onOpen: { alert = .readerDeferred(book.title) },
                                        onMarkRead: { markRead(book) },
                                        onRename: { renameItem = NativeRenameBookItem(book: book, title: book.title) },
                                        onDelete: { alert = .delete(book) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isBusy {
                ProgressView("处理中...")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear(perform: loadBooks)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: true,
            onCompletion: importBooks
        )
        .alert(item: $alert) { alert in
            switch alert {
            case .error(let message):
                return Alert(
                    title: Text("操作失败"),
                    message: Text(message),
                    dismissButton: .default(Text("好"))
                )
            case .readerDeferred(let title):
                return Alert(
                    title: Text("阅读器尚未迁移"),
                    message: Text("“\(title)” 的打开阅读会在 Reader native 迁移阶段接入；当前不会改动 Reader/WKWebView。"),
                    dismissButton: .default(Text("好"))
                )
            case .delete(let book):
                return Alert(
                    title: Text("删除“\(book.title)”？"),
                    message: Text("会删除本地书籍文件夹和阅读进度。"),
                    primaryButton: .destructive(Text("删除")) { delete(book) },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
        .sheet(item: $renameItem) { item in
            NativeRenameBookSheet(
                title: item.title,
                onCancel: { renameItem = nil },
                onSave: { newTitle in
                    rename(item.book, title: newTitle)
                    renameItem = nil
                }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("排序", selection: Bindable(userConfig).bookshelfSortOption) {
                Label("最近阅读", systemImage: SortOption.recent.icon).tag(SortOption.recent)
                Label("标题", systemImage: SortOption.title.icon).tag(SortOption.title)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Toggle("阅读中", isOn: Bindable(userConfig).bookshelfShowReading)
                .toggleStyle(.switch)

            Spacer()

            Button {
                loadBooks()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button {
                isImporting = true
            } label: {
                Label("导入 EPUB", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sections: [NativeBookSection] {
        let sorted = sortedBooks(books)
        guard userConfig.bookshelfShowReading else {
            return [NativeBookSection(title: "全部书籍", books: sorted)]
        }

        let reading = sorted.filter { $0.progress > 0 && $0.progress < 0.999 }
        let finishedOrUnread = sorted.filter { !(($0.progress > 0) && ($0.progress < 0.999)) }
        var result: [NativeBookSection] = []
        if !reading.isEmpty {
            result.append(NativeBookSection(title: "阅读中", books: reading))
        }
        if !finishedOrUnread.isEmpty {
            result.append(NativeBookSection(title: "全部书籍", books: finishedOrUnread))
        }
        return result
    }

    private func sortedBooks(_ books: [NativeBookRow]) -> [NativeBookRow] {
        switch userConfig.bookshelfSortOption {
        case .recent:
            books.sorted { $0.lastAccess > $1.lastAccess }
        case .title:
            books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private func loadBooks() {
        do {
            let loadedBooks = try BookStorage.loadAllBooks()
            let booksDirectory = try BookStorage.getBooksDirectory()
            books = loadedBooks.map { metadata in
                let root = booksDirectory.appendingPathComponent(metadata.folder)
                return NativeBookRow(metadata: metadata, root: root)
            }
            if case .error = alert {
                alert = nil
            }
        } catch {
            books = []
            alert = .error(error.localizedDescription)
        }
    }

    private func importBooks(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            isBusy = true
            Task { @MainActor in
                defer {
                    isBusy = false
                    loadBooks()
                }
                var failures: [String] = []
                for url in urls {
                    do {
                        try Self.importBook(from: url)
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !failures.isEmpty {
                    alert = .error(failures.joined(separator: "\n"))
                }
            }
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func markRead(_ book: NativeBookRow) {
        do {
            guard let info = BookStorage.loadBookInfo(root: book.root), info.characterCount > 0 else {
                throw NativeBookshelfError.missingBookInfo
            }
            let bookmark = Bookmark(
                chapterIndex: Self.lastChapterIndex(in: info),
                progress: 1,
                characterCount: info.characterCount,
                lastModified: Date()
            )
            try BookStorage.save(bookmark, inside: book.root, as: FileNames.bookmark)
            loadBooks()
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func rename(_ book: NativeBookRow, title: String) {
        do {
            var metadata = book.metadata
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata.renamedTitle = trimmed.isEmpty || trimmed == metadata.title ? nil : trimmed
            try BookStorage.save(metadata, inside: book.root, as: FileNames.metadata)
            loadBooks()
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private func delete(_ book: NativeBookRow) {
        do {
            try BookStorage.delete(at: book.root)
            loadBooks()
        } catch {
            alert = .error(error.localizedDescription)
        }
    }

    private static func importBook(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try FileManager.default.copyItem(at: url, to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
        }

        let tempDocument = try BookStorage.loadEpub(tempURL)
        let title = tempDocument.title?.isEmpty == false
            ? (tempDocument.title ?? url.deletingPathExtension().lastPathComponent)
            : url.deletingPathExtension().lastPathComponent
        let safeTitle = BookStorage.sanitizeFileName(title)
        let booksDirectory = try BookStorage.getBooksDirectory()
        let bookRoot = booksDirectory.appendingPathComponent(safeTitle)

        if FileManager.default.fileExists(atPath: bookRoot.path(percentEncoded: false)) {
            throw NativeBookshelfError.bookAlreadyExists(title)
        }

        try FileManager.default.createDirectory(at: bookRoot, withIntermediateDirectories: true)
        do {
            let localURL = bookRoot.appendingPathComponent(url.lastPathComponent)
            try BookStorage.copyFile(from: tempURL, to: "Books/\(safeTitle)/\(localURL.lastPathComponent)")
            let document = try BookStorage.loadEpub(localURL)
            let coverPath = try copyCoverIfAvailable(from: document, into: safeTitle)
            let metadata = BookMetadata(
                title: title,
                epub: localURL.lastPathComponent,
                cover: coverPath,
                folder: bookRoot.lastPathComponent,
                lastAccess: Date()
            )
            try BookStorage.save(metadata, inside: bookRoot, as: FileNames.metadata)
            try BookStorage.save(NativeBookProcessor.process(document: document), inside: bookRoot, as: FileNames.bookinfo)
        } catch {
            try? BookStorage.delete(at: bookRoot)
            throw error
        }
    }

    private static func copyCoverIfAvailable(from document: EPUBDocument, into folder: String) throws -> String? {
        guard let coverPath = findCoverPath(in: document) else { return nil }
        let source = document.contentDirectory.appendingPathComponent(coverPath)
        let destination = "Books/\(folder)/\(URL(fileURLWithPath: coverPath).lastPathComponent)"
        try BookStorage.copyFile(from: source, to: destination)
        return destination
    }

    private static func findCoverPath(in document: EPUBDocument) -> String? {
        if let coverItem = document.manifest.items.values.first(where: { $0.property?.contains("cover-image") == true }) {
            return coverItem.path
        }
        if let coverId = document.metadata.coverId,
           let coverItem = document.manifest.items[coverId] {
            return coverItem.path
        }
        let imageTypes: [EPUBMediaType] = [.jpeg, .png, .gif, .svg]
        if let coverItem = document.manifest.items.values.first(where: { $0.id.lowercased().contains("cover") }),
           imageTypes.contains(coverItem.mediaType) {
            return coverItem.path
        }
        return document.manifest.items.values.first(where: { imageTypes.contains($0.mediaType) })?.path
    }

    private static func lastChapterIndex(in info: BookInfo) -> Int {
        info.chapterInfo.values.compactMap(\.spineIndex).max() ?? 0
    }
}

private struct NativeBookCard: View {
    let book: NativeBookRow
    let onOpen: () -> Void
    let onMarkRead: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                NativeBookCoverView(book: book)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(book.progressText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }

            Text(book.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView(value: book.progress)
                .progressViewStyle(.linear)

            Text(book.lastAccess.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label("打开", systemImage: "book.pages")
                }
                .help("打开阅读器")

                Spacer()

                if let epubURL = book.epubURL {
                    ShareLink(item: epubURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("导出 EPUB")
                }

                Button(action: onRename) {
                    Image(systemName: "character.cursor.ibeam.ja")
                }
                .help("重命名")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("删除")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) {
                Label("打开", systemImage: "book.pages")
            }
            Button(action: onMarkRead) {
                Label("标记已读", systemImage: "checkmark")
            }
            Button(action: onRename) {
                Label("重命名", systemImage: "character.cursor.ibeam.ja")
            }
            if let epubURL = book.epubURL {
                ShareLink(item: epubURL) {
                    Label("导出 EPUB", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private struct NativeBookCoverView: View {
    let book: NativeBookRow

    var body: some View {
        Group {
            if let image = book.coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.secondary.opacity(0.12), .secondary.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "book.closed")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.3))
    }
}

private struct NativeRenameBookSheet: View {
    @State private var draftTitle: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(title: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        _draftTitle = State(initialValue: title)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名")
                .font(.title2.bold())
            TextField("标题", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(draftTitle)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct NativeBookRow: Identifiable, Hashable {
    let metadata: BookMetadata
    let root: URL
    let progress: Double

    init(metadata: BookMetadata, root: URL) {
        self.metadata = metadata
        self.root = root
        progress = Self.progress(root: root)
    }

    var id: UUID { metadata.id }
    var title: String { metadata.displayTitle }
    var lastAccess: Date { metadata.lastAccess }

    var progressText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    var epubURL: URL? {
        metadata.epub.map { root.appendingPathComponent($0) }
    }

    var coverImage: NSImage? {
        guard let cover = metadata.cover else { return nil }
        let url = cover.hasPrefix("/")
            ? URL(fileURLWithPath: cover)
            : (try? BookStorage.getAppDirectory().appendingPathComponent(cover))
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func progress(root: URL) -> Double {
        guard let total = BookStorage.loadBookInfo(root: root)?.characterCount,
              total > 0,
              let current = BookStorage.loadBookmark(root: root)?.characterCount else {
            return 0
        }
        return min(max(Double(current) / Double(total), 0), 1)
    }
}

private struct NativeBookSection: Identifiable {
    let title: String
    let books: [NativeBookRow]
    var id: String { title }
}

private struct NativeRenameBookItem: Identifiable, Equatable {
    let book: NativeBookRow
    let title: String
    var id: UUID { book.id }
}

private enum NativeBookshelfAlert: Identifiable {
    case error(String)
    case readerDeferred(String)
    case delete(NativeBookRow)

    var id: String {
        switch self {
        case .error(let message):
            "error-\(message)"
        case .readerDeferred(let title):
            "reader-\(title)"
        case .delete(let book):
            "delete-\(book.id)"
        }
    }

    var inlineError: String? {
        guard case .error(let message) = self else { return nil }
        return message
    }
}

private enum NativeBookshelfError: LocalizedError {
    case bookAlreadyExists(String)
    case missingBookInfo

    var errorDescription: String? {
        switch self {
        case .bookAlreadyExists(let title):
            "“\(title)” 已存在。"
        case .missingBookInfo:
            "缺少书籍进度信息。"
        }
    }
}

private enum NativeBookProcessor {
    static func process(document: EPUBDocument) -> BookInfo {
        var chapterInfo: [String: BookInfo.ChapterInfo] = [:]
        var total = 0
        for (index, item) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[item.idref] else {
                continue
            }
            let path = document.contentDirectory.appendingPathComponent(manifestItem.path)
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                let count = filteredCharacterCount(content)
                chapterInfo[manifestItem.path] = BookInfo.ChapterInfo(
                    spineIndex: index,
                    currentTotal: total,
                    chapterCount: count
                )
                total += count
            }
        }
        return BookInfo(characterCount: total, chapterInfo: chapterInfo)
    }

    private static func filteredCharacterCount(_ content: String) -> Int {
        var text = content
        if let bodyRange = text.range(of: "(?s)<body.*?</body>", options: .regularExpression) {
            text = String(text[bodyRange])
        }
        text = text.replacingOccurrences(of: "(?s)<rt[^>]*>.*?</rt>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(
            of: "[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\\p{Radical}\\p{Unified_Ideograph}]",
            with: "",
            options: .regularExpression
        )
        return text.count
    }
}
