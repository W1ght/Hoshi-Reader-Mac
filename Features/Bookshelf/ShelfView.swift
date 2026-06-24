//
//  ShelfView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var isCollapsed: Bool
    @State private var compactRowCount = 4
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?
    @Binding var selectedReaderBook: BookMetadata?
    @State private var bookFrames: [UUID: CGRect] = [:]
    @State private var pendingExport: BookExportPresentation?
    @State private var activeDragSourceID: UUID?
    @State private var activeDragTargetID: UUID?
    var onMatch: (BookMetadata) -> Void

    private static let compactCoverWidth: CGFloat = 80
    private static let compactColumnSpacing: CGFloat = 12

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: BookshelfLayout.v050CoverWidth,
                maximum: BookshelfLayout.v050CoverWidth
            ),
            spacing: BookshelfLayout.columnSpacing
        )]
    }

    private var compactColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Self.compactCoverWidth),
            spacing: Self.compactColumnSpacing
        )]
    }

    private var coordinateSpaceName: String {
        "bookshelf-\(section.id)"
    }

    init(
        viewModel: BookshelfViewModel,
        section: ShelfSection,
        showTitle: Bool = true,
        isSelecting: Bool = false,
        selectedBooks: Binding<Set<BookMetadata>>,
        pendingLookup: Binding<String?>,
        pendingTab: Binding<Int?>,
        selectedReaderBook: Binding<BookMetadata?>,
        onMatch: @escaping (BookMetadata) -> Void
    ) {
        self.viewModel = viewModel
        self.section = section
        self.showTitle = showTitle
        self.isSelecting = isSelecting
        self._selectedBooks = selectedBooks
        self._pendingLookup = pendingLookup
        self._pendingTab = pendingTab
        self._selectedReaderBook = selectedReaderBook
        self.onMatch = onMatch
        self._isCollapsed = State(initialValue: !section.isReading)
    }

    var body: some View {
        VStack {
            if showTitle {
                if section.shelf != nil {
                    Button {
                        withAnimation(.default.speed(1.5)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        HStack {
                            Text(section.shelf!.name)
                                .font(.title3.bold())
                                .lineLimit(1)
                            Text("\(section.books.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("Unshelved")
                            .font(.title3.bold())
                        Text("\(section.books.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            }

            if isCollapsed && section.shelf != nil {
                compactCollapsedGrid
            } else {
                LazyVGrid(columns: columns, spacing: BookshelfLayout.rowSpacing) {
                ForEach(section.books) { book in
                    if section.isGoogleDrive {
                        DriveBookCell(
                            book: book,
                            progress: viewModel.progress(for: book),
                            isDownloading: viewModel.downloadingBooks[book.id] != nil,
                            downloadProgress: viewModel.downloadingBooks[book.id] ?? 0,
                            onImport: {
                                viewModel.importGoogleDriveBook(
                                    book,
                                    syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                                    syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
                                )
                            },
                            onDelete: {
                                viewModel.deleteGoogleDriveBook(book)
                            }
                        )
                    } else {
                        let cell = BookCell(
                            book: book,
                            viewModel: viewModel,
                            currentShelf: section.shelf?.name,
                            hideMove: section.isReading,
                            onSelect: {
                                selectedReaderBook = book
                            },
                            onMatch: { onMatch(book) },
                            onExport: { url in
                                pendingExport = BookExportPresentation(bookID: book.id, fileURL: url)
                            },
                            isSelecting: isSelecting,
                            selectedBooks: $selectedBooks,
                            presentedExportURL: exportBinding(for: book.id),
                            dragCoordinateSpaceName: section.isReading ? nil : coordinateSpaceName,
                            onDragChanged: section.isReading ? nil : { location in
                                reorderBook(book.id, draggedTo: location)
                            },
                            onDragEnded: section.isReading ? nil : { location in
                                reorderBook(book.id, draggedTo: location)
                                activeDragSourceID = nil
                                activeDragTargetID = nil
                            }
                        )
                        if section.isReading {
                            cell
                        } else {
                            cell
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: BookshelfBookFramePreferenceKey.self,
                                            value: [book.id: proxy.frame(in: .named(coordinateSpaceName))]
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(.horizontal)
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(BookshelfBookFramePreferenceKey.self) { frames in
                bookFrames = frames
            }
            }
        }
        .opacity(section.isGoogleDrive && isSelecting ? 0.4 : 1)
        .allowsHitTesting(!section.isGoogleDrive || !isSelecting)
        .onChange(of: isSelecting) {
            if isSelecting && section.isGoogleDrive {
                withAnimation(.default.speed(1.5)) {
                    isCollapsed = true
                }
            }
        }
    }

    private var compactCollapsedGrid: some View {
        LazyVGrid(columns: compactColumns, spacing: Self.compactColumnSpacing) {
            ForEach(section.books.prefix(compactRowCount)) { book in
                Button {
                    withAnimation(.default.speed(1.5)) {
                        isCollapsed = false
                    }
                } label: {
                    BookCover(book: book, width: Self.compactCoverWidth)
                }
                .buttonStyle(.plain)
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            let coverWidth: CGFloat = 80
            let columnSpacing: CGFloat = 12
            return max(1, Int((proxy.size.width + columnSpacing) / (coverWidth + columnSpacing)))
        } action: { count in
            compactRowCount = count
        }
        .padding(.horizontal)
    }

    private func exportBinding(for bookID: UUID) -> Binding<URL?> {
        Binding(
            get: {
                pendingExport?.bookID == bookID ? pendingExport?.fileURL : nil
            },
            set: { value in
                if value == nil, pendingExport?.bookID == bookID {
                    pendingExport = nil
                }
            }
        )
    }

    private func reorderBook(_ sourceID: UUID, draggedTo location: CGPoint) {
        guard !section.isReading, !section.isGoogleDrive else { return }
        guard let targetID = bookFrames.first(where: { id, frame in
            id != sourceID && frame.insetBy(dx: -8, dy: -8).contains(location)
        })?.key else {
            return
        }
        if activeDragSourceID != sourceID {
            activeDragSourceID = sourceID
            activeDragTargetID = nil
        }
        guard activeDragTargetID != targetID else { return }

        userConfig.bookshelfSortOption = .manual
        viewModel.moveBook(sourceID, in: section, before: targetID)
        activeDragTargetID = targetID
    }
}

private struct BookExportPresentation: Identifiable {
    let id = UUID()
    let bookID: UUID
    let fileURL: URL
}

private struct BookshelfBookFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct DriveBookCell: View {
    @State private var showDeleteConfirmation = false
    let book: BookMetadata
    let progress: Double
    let isDownloading: Bool
    let downloadProgress: Double
    let onImport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            onImport()
        } label: {
            VStack(spacing: 6) {
                BookCover(book: book, progress: progress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.displayTitle)
                        .font(.system(size: 16))
                        .lineLimit(isDownloading ? 1 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isDownloading {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(.caption, weight: .semibold))
                            ProgressView(value: downloadProgress)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 40, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: BookshelfLayout.v050CoverWidth)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete from Google Drive", systemImage: "trash")
            }
            .disabled(isDownloading)
        }
        .confirmationDialog(
            "Delete \"\(book.displayTitle)\" from Google Drive?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
