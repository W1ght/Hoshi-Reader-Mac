import EPUBKit
import SwiftUI

private enum ReaderGoToTab: String, CaseIterable, Identifiable {
    case search
    case chapters
    case highlights

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .search: "Search"
        case .chapters: "Chapters"
        case .highlights: "Highlights"
        }
    }
}

struct ReaderGoToView: View {
    let displayTitle: String
    let document: EPUBDocument
    let bookInfo: BookInfo
    let currentIndex: Int
    let currentCharacter: Int
    let contentLanguage: ContentLanguageProfile
    let coverURL: URL?
    let highlights: [Highlight]
    let onChapterJump: (Int, String?) -> Void
    let onCharacterJump: (Int) -> Void
    let onSearchResultJump: (ReaderSearchResult) -> Void
    let onHighlightJump: (Highlight) -> Void
    let onHighlightDelete: (Highlight) -> Void
    let onDismiss: () -> Void

    @State private var selectedTab: ReaderGoToTab = .search
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var searchResults: [ReaderSearchResult] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var searchTask: Task<Void, Never>?
    @State private var chapterRows: [ChapterRow] = []
    @State private var showJumpAlert = false
    @State private var showInvalidJumpAlert = false
    @State private var jumpInput = ""

    private var searchDocument: ReaderSearchDocument {
        ReaderSearchDocument(epubDocument: document, bookInfo: bookInfo)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderView(
                    title: displayTitle,
                    currentCharacterCount: contentLanguage.displayCount(forRawCharacters: currentCharacter),
                    totalCharacterCount: contentLanguage.displayCount(forRawCharacters: bookInfo.characterCount),
                    coverURL: coverURL,
                    onJumpTo: {
                        jumpInput = ""
                        showJumpAlert = true
                    }
                )

                ReaderLiquidGlassSegmentedControl(selection: $selectedTab)
                .padding(.bottom, 10)

                selectedContent
            }
            .navigationTitle("Go to")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
                        onDismiss()
                    }
                }
            }
            .onAppear {
                if chapterRows.isEmpty {
                    chapterRows = ChapterListViewModel(
                        document: document,
                        bookInfo: bookInfo,
                        currentIndex: currentIndex
                    ).rows
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .alert("Jump to", isPresented: $showJumpAlert) {
                TextField(contentLanguage == .english ? "Word count" : "Character count", text: $jumpInput)
                Button("Cancel", role: .cancel) {}
                Button("Go") {
                    if let count = Int(jumpInput), count >= 0 {
                        onCharacterJump(contentLanguage.rawCharacters(forDisplayCount: count))
                    } else {
                        showInvalidJumpAlert = true
                    }
                }
            } message: {
                Text(progressText(rawCharacter: currentCharacter))
            }
            .alert("Invalid input", isPresented: $showInvalidJumpAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(contentLanguage == .english ? "Please enter a valid word count" : "Please enter a valid character count")
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .search:
            searchTab
        case .chapters:
            chaptersTab
        case .highlights:
            highlightsTab
        }
    }

    private var searchTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search in this book", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)
                    .onChange(of: query) { _, value in
                        if !ReaderSearchTextFilter.hasMatchableText(value) {
                            clearSearch()
                        }
                    }
                Button {
                    runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .disabled(!ReaderSearchTextFilter.hasMatchableText(query) || isSearching)
                .help("Search")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.quaternary.opacity(0.35), in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, 8)

            searchResultsContent
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if !ReaderSearchTextFilter.hasMatchableText(submittedQuery) {
            ContentUnavailableView("Enter text to search this book", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearching {
            VStack(spacing: 10) {
                ProgressView()
                Text("Searching...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchFailed {
            ContentUnavailableView("Could not search this book", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groupedSearchResults) { section in
                    Section {
                        ForEach(section.results) { result in
                            Button {
                                onSearchResultJump(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlightedSnippet(for: result))
                                        .font(.body)
                                        .lineLimit(4)
                                    Text(progressText(rawCharacter: result.character))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.headline)
                            Text(resultCountText(section.results.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var chaptersTab: some View {
        List {
            ForEach(chapterRows) { row in
                ChapterView(row: row, contentLanguage: contentLanguage) {
                    onChapterJump(row.spineIndex, row.fragment)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if chapterRows.isEmpty {
                ContentUnavailableView("No Chapters", systemImage: "list.bullet")
            }
        }
    }

    private var highlightsTab: some View {
        List {
            ForEach(highlightSections) { section in
                Section(section.label) {
                    ForEach(section.highlights) { highlight in
                        Button {
                            onHighlightJump(highlight)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlight.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.body)
                                    .lineLimit(5)
                                Text("\(highlight.createdAt.formatted(date: .abbreviated, time: .shortened)) (\(contentLanguage.displayCount(forRawCharacters: highlight.character)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 4)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(highlight.color.swatch)
                                    .frame(width: 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onHighlightDelete(highlight)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { onHighlightDelete(section.highlights[$0]) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if highlights.isEmpty {
                ContentUnavailableView("No Highlights", systemImage: "highlighter")
            }
        }
    }

    private var groupedSearchResults: [SearchResultSection] {
        let grouped = Dictionary(grouping: searchResults, by: \.chapterIndex)
        return grouped.keys.sorted().compactMap { chapterIndex in
            guard let results = grouped[chapterIndex] else { return nil }
            return SearchResultSection(
                id: chapterIndex,
                title: results.first?.chapterLabel.isEmpty == false ? results[0].chapterLabel : String(localized: "Untitled Chapter"),
                results: results
            )
        }
    }

    private var highlightSections: [HighlightSection] {
        let labels = chapterLabelBySpineIndex
        let grouped = Dictionary(grouping: highlights) { highlight in
            var spine = bookInfo.resolveCharacterPosition(highlight.character)?.spineIndex ?? -1
            while spine > 0, labels[spine] == nil {
                spine -= 1
            }
            return spine
        }
        return grouped.map { spineIndex, list in
            HighlightSection(
                id: spineIndex,
                label: labels[spineIndex] ?? "",
                highlights: list.sorted { $0.character < $1.character }
            )
        }
        .sorted { $0.id < $1.id }
    }

    private var chapterLabelBySpineIndex: [Int: String] {
        var labels: [Int: String] = [:]
        for row in chapterRows where !row.label.isEmpty {
            if labels[row.spineIndex] == nil {
                labels[row.spineIndex] = row.label
            }
        }
        return labels
    }

    private func runSearch() {
        guard ReaderSearchTextFilter.hasMatchableText(query) else {
            clearSearch()
            return
        }

        searchTask?.cancel()
        submittedQuery = query
        isSearching = true
        searchFailed = false
        let capturedQuery = query
        let document = searchDocument

        searchTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                ReaderSearchEngine(document: document).search(capturedQuery)
            }.result

            guard !Task.isCancelled else { return }
            switch result {
            case .success(let results):
                searchResults = results
                searchFailed = false
            case .failure:
                searchResults = []
                searchFailed = true
            }
            isSearching = false
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        submittedQuery = ""
        searchResults = []
        isSearching = false
        searchFailed = false
    }

    private func progressText(rawCharacter: Int) -> String {
        let current = contentLanguage.displayCount(forRawCharacters: rawCharacter)
        let total = contentLanguage.displayCount(forRawCharacters: bookInfo.characterCount)
        let percent = bookInfo.characterCount > 0 ? Double(rawCharacter) / Double(bookInfo.characterCount) * 100 : 0
        return "\(current) / \(total) (\(String(format: "%.1f%%", percent)))"
    }

    private func resultCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 result")
            : String.localizedStringWithFormat(String(localized: "%d results"), count)
    }

    private func highlightedSnippet(for result: ReaderSearchResult) -> AttributedString {
        let characters = Array(result.snippet)
        let lower = max(0, min(result.snippetMatchStart, characters.count))
        let upper = max(lower, min(result.snippetMatchEnd, characters.count))
        var attributed = AttributedString(String(characters[..<lower]))
        var match = AttributedString(String(characters[lower..<upper]))
        match.backgroundColor = .accentColor.opacity(0.22)
        attributed += match
        attributed += AttributedString(String(characters[upper...]))
        return attributed
    }
}

private struct SearchResultSection: Identifiable {
    let id: Int
    let title: String
    let results: [ReaderSearchResult]
}

private struct ReaderLiquidGlassSegmentedControl: View {
    @Binding var selection: ReaderGoToTab

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            controlBody
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var controlBody: some View {
        GlassEffectContainer(spacing: 0) {
            segments
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(Array(ReaderGoToTab.allCases.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    divider(before: tab)
                }
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selection == tab ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.78))
                        .frame(minWidth: 58, minHeight: 28)
                        .padding(.horizontal, 2)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.92))
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.55)
                            }
                    }
                }
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func divider(before tab: ReaderGoToTab) -> some View {
        let previousIndex = max((ReaderGoToTab.allCases.firstIndex(of: tab) ?? 1) - 1, 0)
        let previous = ReaderGoToTab.allCases[previousIndex]
        if selection != tab && selection != previous {
            Rectangle()
                .fill(.separator.opacity(0.42))
                .frame(width: 1, height: 18)
        } else {
            Color.clear
                .frame(width: 1, height: 18)
        }
    }
}
