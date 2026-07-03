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
    let isCurrent: Bool
    let indentLevel: Int
}

@Observable
@MainActor
class ChapterListViewModel {
    var rows: [ChapterRow] = []
    
    private let document: EPUBDocument
    private let bookInfo: BookInfo
    private let currentIndex: Int
    
    init(document: EPUBDocument, bookInfo: BookInfo, currentIndex: Int) {
        self.document = document
        self.bookInfo = bookInfo
        self.currentIndex = currentIndex
        
        self.rows = generateRows()
    }
    
    private func generateRows() -> [ChapterRow] {
        return flattenTOC(document.tableOfContents.subTable ?? [], indentLevel: 0)
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
                    isCurrent: index == currentIndex,
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
        let basePath = tocPath.components(separatedBy: "#").first ?? tocPath
        return bookInfo.chapterInfo[basePath]?.currentTotal
    }
    
    private func findSpineIndex(for item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        let basePath = tocPath.components(separatedBy: "#").first ?? tocPath
        
        for (index, spineItem) in document.spine.items.enumerated() {
            if let manifestItem = document.manifest.items[spineItem.idref] {
                if manifestItem.path == basePath ||
                    manifestItem.path.hasSuffix(basePath) ||
                    basePath.hasSuffix(manifestItem.path) {
                    return index
                }
            }
        }
        return nil
    }
}
