import SwiftUI

struct NativeBookshelfHomeView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var books: [NativeBookRow] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                NativeMigrationStatusView(
                    title: "复用现有 BookStorage",
                    rows: [
                        "读取现有 Books/metadata.json",
                        "读取 bookmark/bookinfo 计算阅读进度",
                        "暂不接 Reader、导入、同步和删除"
                    ]
                )

                Spacer()

                Button {
                    loadBooks()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage {
                ContentUnavailableView {
                    Label("书架读取失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if books.isEmpty {
                ContentUnavailableView {
                    Label("No Books", systemImage: "books.vertical")
                } description: {
                    Text("当前没有读取到本地书籍。")
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(sortedBooks) { book in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(systemName: "book.closed")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(book.progressText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(book.title)
                                .font(.headline)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ProgressView(value: book.progress)
                                .progressViewStyle(.linear)

                            Text(book.lastAccess.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .onAppear(perform: loadBooks)
    }

    private var sortedBooks: [NativeBookRow] {
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
                let progress = Self.progress(root: root)
                return NativeBookRow(
                    id: metadata.id,
                    title: metadata.displayTitle,
                    lastAccess: metadata.lastAccess,
                    progress: progress
                )
            }
            errorMessage = nil
        } catch {
            books = []
            errorMessage = error.localizedDescription
        }
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

private struct NativeBookRow: Identifiable {
    let id: UUID
    let title: String
    let lastAccess: Date
    let progress: Double

    var progressText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}
