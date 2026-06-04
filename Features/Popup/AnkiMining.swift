//
//  AnkiMining.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum AnkiMiningStatus: String {
    case added
    case duplicate
    case failed
    case pending
}

struct AnkiMiningResult {
    let status: AnkiMiningStatus
    let message: String

    var webPayload: [String: String] {
        [
            "status": status.rawValue,
            "message": message
        ]
    }

    static func added(_ message: String = "Added to Anki.") -> AnkiMiningResult {
        AnkiMiningResult(status: .added, message: message)
    }

    static func duplicate(_ message: String = "Already exists in Anki.") -> AnkiMiningResult {
        AnkiMiningResult(status: .duplicate, message: message)
    }

    static func failed(_ message: String) -> AnkiMiningResult {
        AnkiMiningResult(status: .failed, message: message)
    }

    static func pending(_ message: String) -> AnkiMiningResult {
        AnkiMiningResult(status: .pending, message: message)
    }
}

@MainActor
func mineAnkiEntry(content: [String: String], context: MiningContext) async -> AnkiMiningResult {
    let expression = content["expression"] ?? "Entry"

    guard AnkiManager.shared.selectedDeck != nil,
          AnkiManager.shared.selectedNoteType != nil else {
        return .failed("Configure Anki deck and model first.")
    }

    if !AnkiManager.shared.allowDupes,
       await AnkiManager.shared.checkDuplicate(word: expression) {
        return .duplicate("Already exists in Anki.")
    }

    let added = await AnkiManager.shared.addNote(content: content, context: context)
    if added {
        return .added("Added to Anki.")
    }

    return .failed(AnkiManager.shared.errorMessage ?? "Failed to add card.")
}
