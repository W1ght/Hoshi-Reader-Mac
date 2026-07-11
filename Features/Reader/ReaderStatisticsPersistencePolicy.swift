//
//  ReaderStatisticsPersistencePolicy.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

struct ReaderStatisticsBookmarkSnapshot: Equatable {
    let chapterIndex: Int
    let characterCount: Int
}

enum ReaderStatisticsPersistencePolicy {
    static func shouldPersist(
        modelChapterIndex: Int,
        modelCharacter: Int,
        persistedBookmark: ReaderStatisticsBookmarkSnapshot?
    ) -> Bool {
        guard let persistedBookmark else { return true }
        return persistedBookmark.chapterIndex == modelChapterIndex
            && persistedBookmark.characterCount == modelCharacter
    }
}
