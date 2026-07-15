//
//  AnkiMining.swift
//  Niratan
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
    let noteID: Int64?

    var webPayload: [String: String] {
        var payload = [
            "status": status.rawValue,
            "message": message
        ]
        if let noteID {
            payload["noteID"] = String(noteID)
        }
        return payload
    }

    static func added(noteID: Int64, _ message: String = "Added to Anki.") -> AnkiMiningResult {
        AnkiMiningResult(status: .added, message: message, noteID: noteID)
    }

    static func duplicate(_ message: String = "Already exists in Anki.") -> AnkiMiningResult {
        AnkiMiningResult(status: .duplicate, message: message, noteID: nil)
    }

    static func failed(_ message: String) -> AnkiMiningResult {
        AnkiMiningResult(status: .failed, message: message, noteID: nil)
    }

    static func pending(_ message: String) -> AnkiMiningResult {
        AnkiMiningResult(status: .pending, message: message, noteID: nil)
    }
}

@MainActor
func preflightAnkiMining(
    content: [String: String],
    profileID: String?
) async -> AnkiMiningResult? {
    if let profileID {
        AnkiManager.shared.activateProfile(profileID)
    }

    guard AnkiManager.shared.selectedDeck != nil,
          AnkiManager.shared.selectedNoteType != nil else {
        return .failed("Configure Anki deck and model first.")
    }

    let expression = content["expression"] ?? "Entry"
    if !AnkiManager.shared.allowDupes,
       await AnkiManager.shared.checkDuplicate(word: expression) {
        return .duplicate("Already exists in Anki.")
    }

    return nil
}

@MainActor
func mineAnkiEntry(
    content: [String: String],
    context: MiningContext,
    preflightAlreadyPassed: Bool = false
) async -> AnkiMiningResult {
    if !preflightAlreadyPassed {
        if let preflightResult = await preflightAnkiMining(
            content: content,
            profileID: context.profileID
        ) {
            return preflightResult
        }
    }

    if AnkiManager.shared.needsVideoAudioClip,
       let video = context.video,
       video.audioClipURL == nil,
       video.audioClipFilename == nil {
        return .failed(
            video.audioClipErrorMessage
                ?? String(localized: "Unable to capture the subtitle audio clip.")
        )
    }

    if let noteID = await AnkiManager.shared.addNote(content: content, context: context) {
        return .added(noteID: noteID, "Added to Anki.")
    }

    return .failed(AnkiManager.shared.errorMessage ?? "Failed to add card.")
}
