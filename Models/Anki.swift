//
//  Anki.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct AnkiResponse: Decodable {
    let profiles: [NameItem]
    let decks: [NameItem]
    let notetypes: [NoteTypeItem]
    
    struct NameItem: Decodable { let name: String }
    struct NoteTypeItem: Decodable {
        let name: String
        let fields: [NameItem]
    }
}

struct AnkiNoteType: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let fields: [String]
}

struct AnkiConfig: Codable {
    let selectedDeck: String?
    let selectedNoteType: String?
    let allowDupes: Bool
    let compactGlossaries: Bool?
    let embedMedia: Bool?
    let fieldMappings: [String: String]
    var tags: String?
    let availableDecks: [String]
    let availableNoteTypes: [AnkiNoteType]
    let useAnkiConnect: Bool?
    let ankiConnectConfig: AnkiConnectConfig?
}

enum DuplicateScope: String, Codable, CaseIterable {
    case collection
    case deck
    case deckroot
}

struct AnkiConnectConfig: Codable {
    var url: String?
    var timeout: Int
    var duplicateScope: DuplicateScope
    var checkAllModels: Bool? = false
    var forceSync: Bool
}

struct MiningContext {
    let sentence: String
    let documentTitle: String?
    let coverURL: URL?
    var sasayakiAudioData: Data? = nil
    var video: VideoMiningContext? = nil
}

struct VideoMiningContext: Equatable {
    let fileName: String
    let cueText: String
    let cueStart: TimeInterval
    let cueEnd: TimeInterval
    let previousCueText: String?
    let nextCueText: String?
    var screenshotURL: URL? = nil
    var audioClipURL: URL? = nil

    var timestamp: String {
        Self.formatTimestamp(cueStart)
    }

    func value(for handlebar: Handlebars) -> String {
        switch handlebar {
        case .videoFileName:
            fileName
        case .videoTimestamp:
            timestamp
        case .videoCueStart:
            Self.formatTimestamp(cueStart)
        case .videoCueEnd:
            Self.formatTimestamp(cueEnd)
        case .videoSubtitle:
            cueText
        case .videoPreviousSubtitle:
            previousCueText ?? ""
        case .videoNextSubtitle:
            nextCueText ?? ""
        case .videoScreenshot:
            screenshotURL?.path ?? ""
        case .videoAudioClip:
            audioClipURL?.path ?? ""
        default:
            ""
        }
    }

    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let milliseconds = max(0, Int((time * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1000) % 60
        let remainder = milliseconds % 1000
        return String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, remainder)
    }
}

struct DictionaryMedia: Decodable {
    let dictionary: String
    let path: String
    let filename: String
}

enum Handlebars: String, CaseIterable {
    case expression = "{expression}"
    case reading = "{reading}"
    case furiganaPlain = "{furigana-plain}"
    case audio = "{audio}"
    case glossary = "{glossary}"
    case glossaryBrief = "{glossary-brief}"
    case glossaryNoDictionary = "{glossary-no-dictionary}"
    case glossaryFirst = "{glossary-first}"
    case glossaryFirstBrief = "{glossary-first-brief}"
    case glossaryFirstNoDictionary = "{glossary-first-no-dictionary}"
    case selectedGlossary = "{selected-glossary}"
    case selectedGlossaryFallback = "{selected-glossary-fallback}"
    case selectedGlossaryBrief = "{selected-glossary-brief}"
    case selectedGlossaryBriefFallback = "{selected-glossary-brief-fallback}"
    case selectedGlossaryNoDictionary = "{selected-glossary-no-dictionary}"
    case selectedGlossaryNoDictionaryFallback = "{selected-glossary-no-dictionary-fallback}"
    case popupSelectionText = "{popup-selection-text}"
    case sentence = "{sentence}"
    case frequencies = "{frequencies}"
    case frequencyHarmonicRank = "{frequency-harmonic-rank}"
    case pitchPositions = "{pitch-accent-positions}"
    case pitchCategories = "{pitch-accent-categories}"
    case documentTitle = "{document-title}"
    case bookCover = "{book-cover}"
    case sasayakiAudio = "{sasayaki-audio}"
    case videoFileName = "{video-file-name}"
    case videoTimestamp = "{video-timestamp}"
    case videoCueStart = "{video-cue-start}"
    case videoCueEnd = "{video-cue-end}"
    case videoSubtitle = "{video-subtitle}"
    case videoPreviousSubtitle = "{video-previous-subtitle}"
    case videoNextSubtitle = "{video-next-subtitle}"
    case videoScreenshot = "{video-screenshot}"
    case videoAudioClip = "{video-audio-clip}"
    
    static let singleGlossaryPrefix = "{single-glossary-"

    var isVideoSpecific: Bool {
        switch self {
        case .videoFileName, .videoTimestamp, .videoCueStart, .videoCueEnd,
             .videoSubtitle, .videoPreviousSubtitle, .videoNextSubtitle,
             .videoScreenshot, .videoAudioClip:
            true
        default:
            false
        }
    }
}
