import SwiftUI

struct NativeBookshelfReuseView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel = BookshelfViewModel()
    @State private var selectedBooks = Set<BookMetadata>()
    @State private var pendingLookup: String?
    @State private var pendingTab: Int?
    @State private var selectedReaderBook: BookMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                if viewModel.importBooksProgress != nil || viewModel.isSyncing || viewModel.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    viewModel.loadBooks()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            let sections = viewModel.shelfSections(
                sortedBy: userConfig.bookshelfSortOption,
                showReading: userConfig.bookshelfShowReading
            )

            if viewModel.books.isEmpty && viewModel.googleDriveBooks.isEmpty {
                ContentUnavailableView {
                    Label("No Books", systemImage: "books.vertical")
                } description: {
                    Text("Import books in the Catalyst app for now; native import will reuse the same storage path next.")
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ScrollView {
                    VStack(spacing: 26) {
                        ForEach(sections) { section in
                            if !section.books.isEmpty {
                                ShelfView(
                                    viewModel: viewModel,
                                    section: section,
                                    showTitle: sections.count > 1,
                                    selectedBooks: $selectedBooks,
                                    pendingLookup: $pendingLookup,
                                    pendingTab: $pendingTab,
                                    selectedReaderBook: $selectedReaderBook,
                                    onMatch: { _ in }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            viewModel.loadBooks()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("阅读器暂缓迁移", isPresented: .init(
            get: { selectedReaderBook != nil },
            set: { if !$0 { selectedReaderBook = nil } }
        )) {
            Button("OK", role: .cancel) {
                selectedReaderBook = nil
            }
        } message: {
            Text("Reader / WKWebView 是最高风险区域，native 书架先复用列表、封面和右键菜单。")
        }
    }
}

struct NativeDictionaryReuseView: View {
    var body: some View {
        DictionarySearchView(
            initialQuery: "",
            initialAutofocus: false,
            shouldFocus: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NativeSettingsReuseView: View {
    var body: some View {
        NavigationStack {
            SettingsHomeView()
        }
    }
}
