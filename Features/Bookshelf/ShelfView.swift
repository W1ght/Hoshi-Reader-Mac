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
    var viewModel: BookshelfViewModel
    var section: ShelfSection
    var showTitle: Bool = true
    var isSelecting: Bool = false
    @Binding var selectedBooks: Set<BookMetadata>
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?
    @Binding var selectedReaderBook: BookMetadata?
    var onMatch: (BookMetadata) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 190), spacing: 20)]
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
        self._isCollapsed = State(initialValue: false)
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

            LazyVGrid(columns: columns, spacing: 20) {
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
                        BookCell(
                            book: book,
                            viewModel: viewModel,
                            currentShelf: section.shelf?.name,
                            hideMove: section.isReading,
                            onSelect: {
                                selectedReaderBook = book
                            },
                            onMatch: { onMatch(book) },
                            isSelecting: isSelecting,
                            selectedBooks: $selectedBooks
                        )
                    }
                }
            }
            .padding(.horizontal)
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
