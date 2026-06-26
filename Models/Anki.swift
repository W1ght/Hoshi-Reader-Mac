//
//  Anki.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CryptoKit
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

struct AnkiProfileConfig: Codable, Equatable {
    let selectedDeck: String?
    let selectedNoteType: String?
    let allowDupes: Bool
    let compactGlossaries: Bool
    let embedMedia: Bool
    let fieldMappings: [String: String]
    let tags: String
    let duplicateScope: DuplicateScope
    let checkAllModels: Bool
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
    var apiKey: String?
}

struct MiningContext {
    let sentence: String
    let documentTitle: String?
    let coverURL: URL?
    var profileID: String? = nil
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
    var screenshotFilename: String? = nil
    var audioClipFilename: String? = nil
    var screenshotURL: URL? = nil
    var audioClipURL: URL? = nil
    var audioClipErrorMessage: String? = nil

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
            screenshotFilename ?? screenshotURL?.path ?? ""
        case .videoAudioClip:
            audioClipFilename ?? audioClipURL?.path ?? ""
        default:
            ""
        }
    }

    static func deterministicMediaFilenames(
        videoURL: URL,
        cueStart: TimeInterval,
        cueEnd: TimeInterval,
        audioStart: TimeInterval,
        audioEnd: TimeInterval
    ) -> VideoMiningMediaFilenames {
        let sourceHash = sha1Hex(videoURL.standardizedFileURL.path(percentEncoded: false))
        let cueRange = millisecondRange(start: cueStart, end: cueEnd)
        let audioRange = millisecondRange(start: audioStart, end: audioEnd)
        return VideoMiningMediaFilenames(
            screenshot: "hoshi_video_frame_\(sourceHash)_\(cueRange).png",
            audioClip: "hoshi_video_audio_\(sourceHash)_\(audioRange).m4a"
        )
    }

    private static func formatTimestamp(_ time: TimeInterval) -> String {
        let milliseconds = max(0, Int((time * 1000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1000) % 60
        let remainder = milliseconds % 1000
        return String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, remainder)
    }

    private static func millisecondRange(start: TimeInterval, end: TimeInterval) -> String {
        "\(milliseconds(start))-\(milliseconds(end))"
    }

    private static func milliseconds(_ time: TimeInterval) -> Int {
        max(0, Int((time * 1000).rounded()))
    }

    private static func sha1Hex(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct VideoMiningMediaFilenames: Equatable {
    let screenshot: String
    let audioClip: String
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
    case phoneticTranscriptions = "{phonetic-transcriptions}"
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

enum AnkiFieldMappingPreset: String, CaseIterable, Identifiable, Sendable {
    case novel
    case anime

    var id: String { rawValue }
}

struct AnkiFieldTemplate {
    let noteType: String
    let mappings: [String: String]

    static let templates: [AnkiFieldTemplate] = [
        AnkiFieldTemplate(noteType: "Lapis", mappings: [
            "Expression": Handlebars.expression.rawValue,
            "ExpressionFurigana": Handlebars.furiganaPlain.rawValue,
            "ExpressionReading": Handlebars.reading.rawValue,
            "ExpressionAudio": Handlebars.audio.rawValue,
            "SelectionText": Handlebars.popupSelectionText.rawValue,
            "MainDefinition": Handlebars.glossaryFirst.rawValue,
            "Sentence": Handlebars.sentence.rawValue,
            "SentenceAudio": Handlebars.sasayakiAudio.rawValue,
            "Picture": Handlebars.bookCover.rawValue,
            "Glossary": Handlebars.glossary.rawValue,
            "PitchPosition": Handlebars.pitchPositions.rawValue,
            "PitchCategories": Handlebars.pitchCategories.rawValue,
            "Frequency": Handlebars.frequencies.rawValue,
            "FreqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "MiscInfo": Handlebars.documentTitle.rawValue,
        ]),
        AnkiFieldTemplate(noteType: "Kiku", mappings: [
            "Expression": Handlebars.expression.rawValue,
            "ExpressionFurigana": Handlebars.furiganaPlain.rawValue,
            "ExpressionReading": Handlebars.reading.rawValue,
            "ExpressionAudio": Handlebars.audio.rawValue,
            "SelectionText": Handlebars.popupSelectionText.rawValue,
            "MainDefinition": Handlebars.glossaryFirst.rawValue,
            "Sentence": Handlebars.sentence.rawValue,
            "Picture": Handlebars.bookCover.rawValue,
            "Glossary": Handlebars.glossary.rawValue,
            "PitchPosition": Handlebars.pitchPositions.rawValue,
            "PitchCategories": Handlebars.pitchCategories.rawValue,
            "Frequency": Handlebars.frequencies.rawValue,
            "FreqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "MiscInfo": Handlebars.documentTitle.rawValue,
        ]),
        AnkiFieldTemplate(noteType: "Senren", mappings: [
            "word": Handlebars.expression.rawValue,
            "reading": Handlebars.reading.rawValue,
            "sentence": Handlebars.sentence.rawValue,
            "selectionText": Handlebars.popupSelectionText.rawValue,
            "definition": Handlebars.glossaryFirst.rawValue,
            "wordAudio": Handlebars.audio.rawValue,
            "picture": Handlebars.bookCover.rawValue,
            "glossary": Handlebars.glossary.rawValue,
            "pitchPositions": Handlebars.pitchPositions.rawValue,
            "pitchCategories": Handlebars.pitchCategories.rawValue,
            "frequencies": Handlebars.frequencies.rawValue,
            "freqSort": Handlebars.frequencyHarmonicRank.rawValue,
            "miscInfo": Handlebars.documentTitle.rawValue,
        ]),
    ]

    static func autofilledMappings(
        noteType: String,
        availableFields: [String],
        existing: [String: String],
        preset: AnkiFieldMappingPreset = .novel
    ) -> [String: String] {
        guard let template = templates.first(where: { $0.noteType == noteType }) else {
            return existing
        }

        let available = Set(availableFields)
        var result = existing.filter { available.contains($0.key) }
        for field in availableFields {
            guard let defaultValue = defaultMapping(
                field: field,
                template: template,
                preset: preset
            ) else { continue }
            if result[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                result[field] = defaultValue
            }
        }
        return result
    }

    static func appliedDefaultMappings(
        noteType: String,
        availableFields: [String],
        existing: [String: String],
        preset: AnkiFieldMappingPreset = .novel
    ) -> [String: String] {
        guard let template = templates.first(where: { $0.noteType == noteType }) else {
            return existing
        }

        let available = Set(availableFields)
        var result = existing.filter { available.contains($0.key) }
        for field in availableFields {
            guard let defaultValue = defaultMapping(
                field: field,
                template: template,
                preset: preset
            ) else { continue }
            result[field] = defaultValue
        }
        for field in availableFields where clearsMapping(noteType: noteType, field: field) {
            result.removeValue(forKey: field)
        }
        return result
    }

    static func hasDefaults(noteType: String) -> Bool {
        templates.contains { $0.noteType == noteType }
    }

    static func clearsMapping(noteType: String, field: String) -> Bool {
        noteType == "Lapis" && field == "DefinitionPicture"
    }

    private static func defaultMapping(
        field: String,
        template: AnkiFieldTemplate,
        preset: AnkiFieldMappingPreset
    ) -> String? {
        switch field.lowercased() {
        case "sentenceaudio":
            preset == .anime
                ? Handlebars.videoAudioClip.rawValue
                : Handlebars.sasayakiAudio.rawValue
        case "picture":
            preset == .anime
                ? Handlebars.videoScreenshot.rawValue
                : Handlebars.bookCover.rawValue
        case "miscinfo":
            preset == .anime
                ? "\(Handlebars.videoFileName.rawValue) (\(Handlebars.videoTimestamp.rawValue))"
                : template.mappings[field]
        default:
            template.mappings[field]
        }
    }
}
