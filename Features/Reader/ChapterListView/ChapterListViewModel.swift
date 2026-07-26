//
//  ChapterListViewModel.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct ChapterRow: Identifiable {
    let id = UUID()
    let label: String
    let spineIndex: Int
    let fragment: String?
    let characterCount: Int?
    var isCurrent: Bool
    let indentLevel: Int
}

@Observable
@MainActor
class ChapterListViewModel {
    var rows: [ChapterRow] = []
    
    private let document: EPUBDocument
    private let bookInfo: BookInfo
    private let currentCharacter: Int
    
    init(document: EPUBDocument, bookInfo: BookInfo, currentCharacter: Int) {
        self.document = document
        self.bookInfo = bookInfo
        self.currentCharacter = currentCharacter
        
        self.rows = generateRows()
    }
    
    private func generateRows() -> [ChapterRow] {
        var rows = flattenTOC(document.tableOfContents.subTable ?? [], indentLevel: 0)
        let currentStart = rows.compactMap(\.characterCount)
            .filter { $0 <= currentCharacter }
            .max()
        if let currentStart,
           let currentIndex = rows.indices.last(where: { rows[$0].characterCount == currentStart }) {
            rows[currentIndex].isCurrent = true
        }
        return rows
    }
    
    private func flattenTOC(_ items: [EPUBTableOfContents], indentLevel: Int) -> [ChapterRow] {
        items.flatMap { item -> [ChapterRow] in
            let row: [ChapterRow]
            if let index = findSpineIndex(for: item) {
                let parts = item.item?.split(separator: "#", maxSplits: 1)
                let fragment = (parts?.count ?? 0) > 1 ? String(parts![1]) : nil
                row = [ChapterRow(
                    label: item.label,
                    spineIndex: index,
                    fragment: fragment,
                    characterCount: getCharacterCount(for: item),
                    isCurrent: false,
                    indentLevel: indentLevel
                )]
            } else {
                row = []
            }
            return row + flattenTOC(item.subTable ?? [], indentLevel: indentLevel + 1)
        }
    }
    
    private func getCharacterCount(for item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        return ReaderChapterIndex.chapterStart(
            forTableOfContentsItem: tocPath,
            bookInfo: bookInfo
        )
    }
    
    private func findSpineIndex(for item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        let basePath = ReaderChapterIndex.normalizedChapterPath(
            tocPath.components(separatedBy: "#").first ?? tocPath
        )
        
        for (index, spineItem) in document.spine.items.enumerated() {
            if let manifestItem = document.manifest.items[spineItem.idref] {
                if ReaderChapterIndex.normalizedChapterPath(manifestItem.path) == basePath {
                    return index
                }
            }
        }
        return nil
    }
}
