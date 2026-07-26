//
//  ChapterListView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct ChapterListView: View {
    let displayTitle: String
    let document: EPUBDocument
    let bookInfo: BookInfo
    let currentCharacter: Int
    let contentLanguage: ContentLanguageProfile
    let coverURL: URL?
    let onJumpToChapter: (Int, String?) -> Void
    let onJumpToCharacter: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var viewModel: ChapterListViewModel?
    @State private var showJumpToAlert = false
    @State private var showInvalidInputAlert = false
    @State private var jumpToInput = ""
    @State private var detent: PresentationDetent = .medium

    private var chapterIndexRevision: Int {
        bookInfo.fragmentOffsetsRevision
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
                        detent = .large
                        jumpToInput = ""
                        showJumpToAlert = true
                    }
                )
                
                List {
                    if let vm = viewModel {
                        ForEach(vm.rows) { row in
                            ChapterView(row: row, contentLanguage: contentLanguage) {
                                onJumpToChapter(row.spineIndex, row.fragment)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshChapterRows()
            }
            .onChange(of: chapterIndexRevision) { _, _ in
                refreshChapterRows()
            }
            .navigationTitle("Chapters")
            .readerNavigationChrome()
            .alert("Jump to", isPresented: $showJumpToAlert) {
                jumpToTextField
                Button("Cancel", role: .cancel) {}
                Button("Go") {
                    if let count = Int(jumpToInput), count >= 0 {
                        onJumpToCharacter(contentLanguage.rawCharacters(forDisplayCount: count))
                        dismiss()
                    } else {
                        showInvalidInputAlert = true
                    }
                }
            } message: {
                Text("Current: \(contentLanguage.displayCount(forRawCharacters: currentCharacter)) / \(contentLanguage.displayCount(forRawCharacters: bookInfo.characterCount))")
            }
            .alert("Invalid input", isPresented: $showInvalidInputAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(contentLanguage == .english ? "Please enter a valid word count" : "Please enter a valid character count")
            }
            .readerChapterPresentationDetents(selection: $detent)
        }
    }

    @ViewBuilder
    private var jumpToTextField: some View {
        TextField(contentLanguage == .english ? "Word count" : "Character count", text: $jumpToInput)
    }

    private func refreshChapterRows() {
        viewModel = ChapterListViewModel(
            document: document,
            bookInfo: bookInfo,
            currentCharacter: currentCharacter
        )
    }
}

struct HeaderView: View {
    let title: String
    let currentCharacterCount: Int
    let totalCharacterCount: Int
    let coverURL: URL?
    let onJumpTo: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(url: coverURL, maxPixelSize: 256) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.secondary.opacity(0.2))
            }
            .frame(width: 50, height: 75)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                
                let percent = totalCharacterCount > 0 ? (Double(currentCharacterCount) / Double(totalCharacterCount) * 100) : 0
                HStack {
                    Text("\(currentCharacterCount) / \(totalCharacterCount) (\(String(format: "%.1f%%", percent)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        onJumpTo()
                    } label: {
                        Image(systemName: "arrow.right.to.line")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }
}

struct ChapterView: View {
    let row: ChapterRow
    let contentLanguage: ContentLanguageProfile
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Text(row.label)
                    .font(row.indentLevel > 0 ? .subheadline : .body)
                Spacer()
                if let count = row.characterCount {
                    Text("\(contentLanguage.displayCount(forRawCharacters: count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(row.indentLevel) * 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(row.isCurrent ? currentRowBackground : nil)
    }

    private var currentRowBackground: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
    }
}

private struct ReaderNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func readerNavigationChrome() -> some View {
        modifier(ReaderNavigationChromeModifier())
    }

    func readerChapterPresentationDetents(selection: Binding<PresentationDetent>) -> some View {
        modifier(ReaderChapterPresentationDetentsModifier(detent: selection))
    }
}

private struct ReaderChapterPresentationDetentsModifier: ViewModifier {
    @Binding var detent: PresentationDetent

    init(detent: Binding<PresentationDetent>) {
        _detent = detent
    }

    func body(content: Content) -> some View {
        content
    }
}
