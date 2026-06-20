//
//  Dictionary.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum DictionaryType: String, Codable, Sendable {
    case term = "Term"
    case frequency = "Frequency"
    case pitch = "Pitch"
}

struct DictionaryRecommendation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: DictionaryType
    let indexURL: String?
    let downloadURL: String?
    let language: ContentLanguageProfile

    static func forLanguage(_ language: ContentLanguageProfile) -> [DictionaryRecommendation] {
        all.filter { $0.language == language }
    }

    static let all: [DictionaryRecommendation] = [
        .init(id: "jmdict", name: "JMdict", type: .term, indexURL: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english_without_proper_names.json", downloadURL: nil, language: .japanese),
        .init(id: "jmnedict", name: "JMnedict", type: .term, indexURL: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMnedict.json", downloadURL: nil, language: .japanese),
        .init(id: "jiten", name: "Jiten", type: .frequency, indexURL: "https://api.jiten.moe/api/frequency-list/index", downloadURL: nil, language: .japanese),
        .init(id: "jitendex", name: "Jitendex", type: .term, indexURL: "https://jitendex.org/static/yomitan.json", downloadURL: nil, language: .japanese),
        .init(id: "wty-en-en", name: "Wiktionary English-English", type: .term, indexURL: "https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest/index/wty-en-en-index.json?download=true", downloadURL: nil, language: .english),
        .init(id: "wty-en-en-ipa", name: "Wiktionary English-English IPA", type: .pitch, indexURL: "https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest/index/wty-en-en-ipa-index.json?download=true", downloadURL: nil, language: .english),
        .init(id: "wty-simple-simple", name: "Wiktionary Simple English-Simple English", type: .term, indexURL: "https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest/index/wty-simple-simple-index.json?download=true", downloadURL: nil, language: .english),
        .init(id: "wty-en-ja", name: "Wiktionary English-Japanese", type: .term, indexURL: "https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest/index/wty-en-ja-index.json?download=true", downloadURL: nil, language: .english),
        .init(id: "wty-en-ja-gloss", name: "Wiktionary English-Japanese Glossary", type: .term, indexURL: "https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest/index/wty-en-ja-gloss-index.json?download=true", downloadURL: nil, language: .english),
        .init(id: "leipzig-english-web-rank", name: "Leipzig English Web", type: .frequency, indexURL: nil, downloadURL: "https://github.com/StefanVukovic99/leipzig-to-yomitan/releases/latest/download/Leipzig.English.Web.Rank.zip", language: .english),
        .init(id: "leipzig-english-wikipedia-rank", name: "Leipzig English Wikipedia", type: .frequency, indexURL: nil, downloadURL: "https://github.com/StefanVukovic99/leipzig-to-yomitan/releases/latest/download/Leipzig.English.Wikipedia.Rank.zip", language: .english),
    ]
}

struct DictionaryInfo: Identifiable, Codable {
    let id: UUID
    let index: DictionaryIndex
    let path: URL
    var isEnabled: Bool
    var order: Int
    
    init(id: UUID = UUID(), index: DictionaryIndex, path: URL, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.index = index
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
    }
}

struct DictionaryConfig: Codable {
    var termDictionaries: [DictionaryEntry]
    var frequencyDictionaries: [DictionaryEntry]
    var pitchDictionaries: [DictionaryEntry]
    
    struct DictionaryEntry: Codable {
        let fileName: String
        var isEnabled: Bool
        var order: Int
    }
}

nonisolated struct DictionaryIndex: Codable {
    let title: String
    let format: Int
    let revision: String
    let isUpdatable: Bool
    let indexUrl: String
    let downloadUrl: String
}

struct AudioSource: Codable, Identifiable {
    var id: String { url }
    var name: String
    let url: String
    var isEnabled: Bool
    let isDefault: Bool
    
    init(name: String = "", url: String, isEnabled: Bool = true, isDefault: Bool = false) {
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}
