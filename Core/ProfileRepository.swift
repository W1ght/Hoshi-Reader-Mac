//
//  ProfileRepository.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Observation

enum ProfileRepositoryError: LocalizedError, Equatable {
    case unsafeProfileID
    case unknownProfile
    case blankName
    case cannotDeleteDefaultProfile
    case languageMismatch

    var errorDescription: String? {
        switch self {
        case .unsafeProfileID: String(localized: "Unsafe profile identifier.")
        case .unknownProfile: String(localized: "The selected profile no longer exists.")
        case .blankName: String(localized: "Profile name cannot be empty.")
        case .cannotDeleteDefaultProfile: String(localized: "The default profile cannot be deleted.")
        case .languageMismatch: String(localized: "The profile language does not match.")
        }
    }
}

@Observable
final class ProfileRepository {
    static let videoProfileDefaultsKey = "videoProfileID"
    static let profilesDirectoryName = "Profiles"
    static let indexFileName = "profiles.json"

    static let shared: ProfileRepository = {
        let appDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return try! ProfileRepository(appDirectory: appDirectory)
    }()

    private(set) var index: ProfileIndex
    private(set) var storedVideoProfileID: String?
    private let appDirectory: URL
    private let defaults: UserDefaults

    private var profilesDirectory: URL {
        appDirectory.appendingPathComponent(Self.profilesDirectoryName, isDirectory: true)
    }

    private var indexURL: URL {
        profilesDirectory.appendingPathComponent(Self.indexFileName)
    }

    var activeProfile: HoshiProfile { resolve(.global) }

    var videoProfileID: String? {
        storedVideoProfileID.flatMap(profile(id:)) == nil ? nil : storedVideoProfileID
    }

    init(appDirectory: URL, defaults: UserDefaults = .standard) throws {
        self.appDirectory = appDirectory
        self.defaults = defaults
        self.index = .initial
        self.storedVideoProfileID = defaults.string(forKey: Self.videoProfileDefaultsKey)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: indexURL),
           let stored = try? JSONDecoder().decode(ProfileIndex.self, from: data) {
            index = Self.normalized(stored)
        } else {
            index = .initial
        }

        try migrateLegacyFilesIfNeeded()
        try bootstrapBuiltInVideoProfileIfNeeded()
        if storedVideoProfileID.flatMap(profile(id:)) == nil {
            defaults.set(HoshiProfile.defaultJapaneseVideo.id, forKey: Self.videoProfileDefaultsKey)
            storedVideoProfileID = HoshiProfile.defaultJapaneseVideo.id
        }
        try persistIndex()
    }

    func profile(id: String) -> HoshiProfile? {
        index.profiles.first { $0.id == id }
    }

    func profiles(for language: ContentLanguageProfile) -> [HoshiProfile] {
        index.profiles.filter { $0.language == language }
    }

    func resolve(_ context: ProfileContext) -> HoshiProfile {
        ProfileResolver.resolve(context, in: index)
    }

    @discardableResult
    func createProfile(
        name: String,
        language: ContentLanguageProfile,
        copyFromProfileID: String?
    ) throws -> HoshiProfile {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileRepositoryError.blankName }
        if let copyFromProfileID, profile(id: copyFromProfileID) == nil {
            throw ProfileRepositoryError.unknownProfile
        }

        let created = HoshiProfile(
            id: "profile-\(UUID().uuidString.lowercased())",
            name: name,
            dictionaryLanguageId: language.rawValue
        )
        try FileManager.default.createDirectory(at: profileDirectory(for: created.id), withIntermediateDirectories: true)
        if let sourceID = copyFromProfileID {
            try copyProfileOwnedFiles(from: sourceID, to: created.id)
        }
        index.profiles.append(created)
        if index.primaryProfileIdsByLanguage[language.rawValue] == nil {
            index.primaryProfileIdsByLanguage[language.rawValue] = created.id
        }
        try persistIndex()
        return created
    }

    func renameProfile(_ profileID: String, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileRepositoryError.blankName }
        guard let index = index.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw ProfileRepositoryError.unknownProfile
        }
        self.index.profiles[index].name = name
        try persistIndex()
    }

    func deleteProfile(_ profileID: String) throws {
        guard let removing = profile(id: profileID) else { throw ProfileRepositoryError.unknownProfile }
        guard !removing.isDefault, profileID != index.defaultProfileId else {
            throw ProfileRepositoryError.cannotDeleteDefaultProfile
        }

        index.profiles.removeAll { $0.id == profileID }
        if index.globalActiveProfileId == profileID {
            index.globalActiveProfileId = index.defaultProfileId
        }
        index.primaryProfileIdsByLanguage = index.primaryProfileIdsByLanguage.filter { $0.value != profileID }
        if defaults.string(forKey: Self.videoProfileDefaultsKey) == profileID {
            defaults.set(HoshiProfile.defaultJapaneseVideo.id, forKey: Self.videoProfileDefaultsKey)
            storedVideoProfileID = HoshiProfile.defaultJapaneseVideo.id
        }
        try? FileManager.default.removeItem(at: profileDirectory(for: profileID))
        self.index = Self.normalized(index)
        try persistIndex()
    }

    func setGlobalActiveProfile(_ profileID: String) throws {
        guard profile(id: profileID) != nil else { throw ProfileRepositoryError.unknownProfile }
        index.globalActiveProfileId = profileID
        try persistIndex()
    }

    func setPrimaryProfile(_ profileID: String, for language: ContentLanguageProfile) throws {
        guard let profile = profile(id: profileID) else { throw ProfileRepositoryError.unknownProfile }
        guard profile.language == language else { throw ProfileRepositoryError.languageMismatch }
        index.primaryProfileIdsByLanguage[language.rawValue] = profileID
        try persistIndex()
    }

    func setVideoProfile(_ profileID: String?) throws {
        if let profileID {
            guard profile(id: profileID) != nil else { throw ProfileRepositoryError.unknownProfile }
            defaults.set(profileID, forKey: Self.videoProfileDefaultsKey)
            storedVideoProfileID = profileID
        } else {
            defaults.set(HoshiProfile.defaultJapaneseVideo.id, forKey: Self.videoProfileDefaultsKey)
            storedVideoProfileID = HoshiProfile.defaultJapaneseVideo.id
        }
    }

    func mergeDictionaryBackup(
        index importedIndex: ProfileIndex,
        profilesSourceDirectory: URL
    ) throws {
        let imported = Self.normalized(importedIndex)
        var profilesByID = Dictionary(uniqueKeysWithValues: index.profiles.map { ($0.id, $0) })
        for profile in imported.profiles where Self.isSafeProfileID(profile.id) {
            profilesByID[profile.id] = profile.id == HoshiProfile.defaultJapanese.id
                ? .defaultJapanese
                : profile
            let sourceDirectory = profilesSourceDirectory.appendingPathComponent(profile.id, isDirectory: true)
            let destinationDirectory = try profileDirectory(for: profile.id)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            for fileName in ["dictionary_config.json", "dictionary_settings.json", "collapsed.json"] {
                let source = sourceDirectory.appendingPathComponent(fileName)
                let destination = destinationDirectory.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }

        index.profiles = profilesByID.values.sorted { lhs, rhs in
            if lhs.id == index.defaultProfileId { return true }
            if rhs.id == index.defaultProfileId { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for (language, profileID) in imported.primaryProfileIdsByLanguage
            where profile(id: profileID) != nil || profilesByID[profileID] != nil {
            index.primaryProfileIdsByLanguage[language] = profileID
        }
        try persistIndex()
    }

    func removeDictionaryReferences(fileName: String, title: String) {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for profile in index.profiles {
            let configURL = dictionaryConfigURL(for: profile.id)
            if let data = try? Data(contentsOf: configURL),
               var config = try? decoder.decode(DictionaryConfig.self, from: data) {
                config.termDictionaries.removeAll { $0.fileName == fileName }
                config.frequencyDictionaries.removeAll { $0.fileName == fileName }
                config.pitchDictionaries.removeAll { $0.fileName == fileName }
                for index in config.termDictionaries.indices { config.termDictionaries[index].order = index }
                for index in config.frequencyDictionaries.indices { config.frequencyDictionaries[index].order = index }
                for index in config.pitchDictionaries.indices { config.pitchDictionaries[index].order = index }
                if let updated = try? encoder.encode(config) {
                    try? updated.write(to: configURL, options: .atomic)
                    if profile.id == self.index.defaultProfileId {
                        let dictionariesRoot = appDirectory.appendingPathComponent("Dictionaries")
                        try? updated.write(to: dictionariesRoot.appendingPathComponent("config.json"), options: .atomic)
                    }
                }
            }

            let collapsedURL = collapsedDictionariesURL(for: profile.id)
            if let data = try? Data(contentsOf: collapsedURL),
               var collapsed = try? decoder.decode(Set<String>.self, from: data),
               collapsed.remove(title) != nil,
               let updated = try? encoder.encode(collapsed) {
                try? updated.write(to: collapsedURL, options: .atomic)
                if profile.id == self.index.defaultProfileId {
                    let legacy = appDirectory.appendingPathComponent("Dictionaries/collapsed.json")
                    try? updated.write(to: legacy, options: .atomic)
                }
            }
        }
    }

    func profileDirectory(for profileID: String) throws -> URL {
        guard Self.isSafeProfileID(profileID) else { throw ProfileRepositoryError.unsafeProfileID }
        return profilesDirectory.appendingPathComponent(profileID, isDirectory: true)
    }

    func dictionaryConfigURL(for profileID: String) -> URL {
        try! profileDirectory(for: profileID).appendingPathComponent("dictionary_config.json")
    }

    func collapsedDictionariesURL(for profileID: String) -> URL {
        try! profileDirectory(for: profileID).appendingPathComponent("collapsed.json")
    }

    func dictionarySettingsURL(for profileID: String) -> URL {
        try! profileDirectory(for: profileID).appendingPathComponent("dictionary_settings.json")
    }

    func ankiConfigURL(for profileID: String) -> URL {
        try! profileDirectory(for: profileID).appendingPathComponent("anki_config.json")
    }

    func readerSettingsURL(for profileID: String) -> URL {
        try! profileDirectory(for: profileID).appendingPathComponent("reader_settings.json")
    }

    private func migrateLegacyFilesIfNeeded() throws {
        let defaultID = index.defaultProfileId
        try FileManager.default.createDirectory(at: profileDirectory(for: defaultID), withIntermediateDirectories: true)
        let dictionaryRoot = appDirectory.appendingPathComponent("Dictionaries", isDirectory: true)
        let copies = [
            (dictionaryRoot.appendingPathComponent("config.json"), dictionaryConfigURL(for: defaultID)),
            (dictionaryRoot.appendingPathComponent("collapsed.json"), collapsedDictionariesURL(for: defaultID)),
            (appDirectory.appendingPathComponent("anki_config.json"), ankiConfigURL(for: defaultID))
        ]
        for (source, destination) in copies where
            FileManager.default.fileExists(atPath: source.path)
                && !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func bootstrapBuiltInVideoProfileIfNeeded() throws {
        let sourceID = HoshiProfile.defaultJapanese.id
        let destinationID = HoshiProfile.defaultJapaneseVideo.id
        let destinationDirectory = try profileDirectory(for: destinationID)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        for fileName in [
            "dictionary_config.json", "collapsed.json", "dictionary_settings.json",
            "reader_settings.json"
        ] {
            let source = try profileDirectory(for: sourceID).appendingPathComponent(fileName)
            let destination = destinationDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let sourceAnki = ankiConfigURL(for: sourceID)
        let destinationAnki = ankiConfigURL(for: destinationID)
        guard FileManager.default.fileExists(atPath: sourceAnki.path),
              !FileManager.default.fileExists(atPath: destinationAnki.path) else { return }
        let sourceData = try Data(contentsOf: sourceAnki)
        let migratedData = animeAnkiProfileData(from: sourceData) ?? sourceData
        try migratedData.write(to: destinationAnki, options: .atomic)
    }

    private func animeAnkiProfileData(from data: Data) -> Data? {
        let decoder = JSONDecoder()
        let source: AnkiProfileConfig
        let availableFields: [String]

        if let profile = try? decoder.decode(AnkiProfileConfig.self, from: data) {
            source = profile
            availableFields = Array(profile.fieldMappings.keys)
        } else if let legacy = try? decoder.decode(AnkiConfig.self, from: data) {
            source = AnkiProfileConfig(
                selectedDeck: legacy.selectedDeck,
                selectedNoteType: legacy.selectedNoteType,
                allowDupes: legacy.allowDupes,
                compactGlossaries: legacy.compactGlossaries ?? false,
                embedMedia: legacy.embedMedia ?? false,
                fieldMappings: legacy.fieldMappings,
                tags: legacy.tags ?? "",
                duplicateScope: legacy.ankiConnectConfig?.duplicateScope ?? .collection,
                checkAllModels: legacy.ankiConnectConfig?.checkAllModels ?? false
            )
            availableFields = legacy.availableNoteTypes
                .first(where: { $0.name == legacy.selectedNoteType })?
                .fields ?? Array(legacy.fieldMappings.keys)
        } else {
            return nil
        }

        guard let noteType = source.selectedNoteType else { return nil }
        let mappings = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: noteType,
            availableFields: availableFields,
            existing: source.fieldMappings,
            preset: .anime
        )
        let migrated = AnkiProfileConfig(
            selectedDeck: source.selectedDeck,
            selectedNoteType: source.selectedNoteType,
            allowDupes: source.allowDupes,
            compactGlossaries: source.compactGlossaries,
            embedMedia: source.embedMedia,
            fieldMappings: mappings,
            tags: source.tags,
            duplicateScope: source.duplicateScope,
            checkAllModels: source.checkAllModels
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(migrated)
    }

    private func copyProfileOwnedFiles(from sourceID: String, to destinationID: String) throws {
        let source = try profileDirectory(for: sourceID)
        let destination = try profileDirectory(for: destinationID)
        for fileName in [
            "dictionary_config.json", "collapsed.json", "dictionary_settings.json",
            "anki_config.json", "reader_settings.json"
        ] {
            let sourceFile = source.appendingPathComponent(fileName)
            let destinationFile = destination.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try FileManager.default.copyItem(at: sourceFile, to: destinationFile)
            }
        }
    }

    private func persistIndex() throws {
        index = Self.normalized(index)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private static func normalized(_ stored: ProfileIndex) -> ProfileIndex {
        var profiles = stored.profiles.filter { isSafeProfileID($0.id) }
        if profiles.isEmpty { profiles = [.defaultJapanese] }
        if let defaultIndex = profiles.firstIndex(where: { $0.id == HoshiProfile.defaultJapanese.id }) {
            if profiles[defaultIndex].name == "Japanese" {
                profiles[defaultIndex].name = HoshiProfile.defaultJapanese.name
            }
            profiles[defaultIndex].isDefault = true
        } else {
            profiles.insert(.defaultJapanese, at: 0)
        }
        if let videoIndex = profiles.firstIndex(where: { $0.id == HoshiProfile.defaultJapaneseVideo.id }) {
            profiles[videoIndex].isDefault = true
        } else {
            let defaultIndex = profiles.firstIndex(where: { $0.id == HoshiProfile.defaultJapanese.id }) ?? 0
            profiles.insert(.defaultJapaneseVideo, at: min(defaultIndex + 1, profiles.count))
        }
        let ids = Set(profiles.map(\.id))
        let defaultID = ids.contains(stored.defaultProfileId)
            ? stored.defaultProfileId
            : HoshiProfile.defaultJapanese.id
        let activeID = ids.contains(stored.globalActiveProfileId)
            ? stored.globalActiveProfileId
            : defaultID
        var primary = stored.primaryProfileIdsByLanguage.filter { language, profileID in
            ContentLanguageProfile(rawValue: language) != nil && ids.contains(profileID)
        }
        if primary[ContentLanguageProfile.japanese.rawValue] == nil {
            primary[ContentLanguageProfile.japanese.rawValue] = defaultID
        }
        return ProfileIndex(
            profiles: profiles,
            defaultProfileId: defaultID,
            globalActiveProfileId: activeID,
            primaryProfileIdsByLanguage: primary
        )
    }

    static func isSafeProfileID(_ profileID: String) -> Bool {
        !profileID.isEmpty
            && profileID != "."
            && profileID != ".."
            && !profileID.contains("/")
            && !profileID.contains("\\")
    }
}
