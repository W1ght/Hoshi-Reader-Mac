//
//  HighlightListView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct HighlightSection: Identifiable {
    let id: Int
    let label: String
    let highlights: [Highlight]
}

struct HighlightListView: View {
    let document: EPUBDocument
    let bookInfo: BookInfo
    let highlights: [Highlight]
    let onJump: (Highlight) -> Void
    let onDelete: (Highlight) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var sections: [HighlightSection] {
        let labels = chapterLabels()
        let grouped = Dictionary(grouping: highlights) {
            var spine = bookInfo.resolveCharacterPosition($0.character)?.spineIndex ?? -1
            while spine > 0 && labels[spine] == nil { spine -= 1 }
            return spine
        }
        return grouped.map { spineIndex, list in
            let label = labels[spineIndex] ?? ""
            let sorted = list.sorted { $0.character < $1.character }
            return HighlightSection(id: spineIndex, label: label, highlights: sorted)
        }.sorted { $0.id < $1.id }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.label) {
                        ForEach(section.highlights) { highlight in
                            Button {
                                onJump(highlight)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(highlight.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.body)
                                        .lineLimit(5)
                                    Text("\(highlight.createdAt.formatted(date: .abbreviated, time: .shortened)) (\(highlight.character))")
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
                                    onDelete(highlight)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { onDelete(section.highlights[$0]) }
                        }
                    }
                }
            }
            .readerHighlightsListStyle()
            .scrollContentBackground(.hidden)
            .overlay {
                if highlights.isEmpty {
                    ContentUnavailableView("No Highlights", systemImage: "highlighter")
                }
            }
            .navigationTitle("Highlights")
            .readerNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func chapterLabels() -> [Int: String] {
        var pathToSpine: [String: Int] = [:]
        for (i, item) in document.spine.items.enumerated() {
            if let manifest = document.manifest.items[item.idref] {
                pathToSpine[manifest.path] = i
            }
        }
        
        var labels: [Int: String] = [:]
        func walk(_ items: [EPUBTableOfContents], topLabel: String?) {
            for item in items {
                let label = topLabel ?? item.label
                if let raw = item.item {
                    let path = raw.components(separatedBy: "#").first ?? raw
                    if let index = pathToSpine[path], labels[index] == nil {
                        labels[index] = label
                    }
                }
                walk(item.subTable ?? [], topLabel: label)
            }
        }
        walk(document.tableOfContents.subTable ?? [], topLabel: nil)
        return labels
    }
}

private struct ReaderHighlightsListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.inset)
    }
}

private extension View {
    func readerHighlightsListStyle() -> some View {
        modifier(ReaderHighlightsListStyleModifier())
    }
}
