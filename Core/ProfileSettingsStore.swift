//
//  ProfileSettingsStore.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@MainActor
final class ProfileSettingsStore {
    static let shared = ProfileSettingsStore()

    private(set) var appliedProfileID: String
    private let repository: ProfileRepository

    init(repository: ProfileRepository = .shared) {
        self.repository = repository
        self.appliedProfileID = repository.activeProfile.id
    }

    func bootstrap(userConfig: UserConfig) {
        let readerURL = repository.readerSettingsURL(for: appliedProfileID)
        let dictionaryURL = repository.dictionarySettingsURL(for: appliedProfileID)
        if let reader = load(ReaderProfileSettings.self, from: readerURL) {
            userConfig.apply(readerProfileSettings: reader)
        } else {
            save(userConfig.readerProfileSettings(), to: readerURL)
        }
        if let dictionary = load(DictionaryProfileSettings.self, from: dictionaryURL) {
            userConfig.apply(dictionaryProfileSettings: dictionary)
        } else {
            save(userConfig.dictionaryProfileSettings(), to: dictionaryURL)
        }
    }

    func activate(profileID: String, userConfig: UserConfig) {
        guard repository.profile(id: profileID) != nil else { return }
        guard profileID != appliedProfileID else { return }
        if repository.profile(id: appliedProfileID) != nil {
            persistCurrent(userConfig: userConfig)
        }
        appliedProfileID = profileID

        let reader = load(
            ReaderProfileSettings.self,
            from: repository.readerSettingsURL(for: profileID)
        ) ?? .defaults
        let dictionary = load(
            DictionaryProfileSettings.self,
            from: repository.dictionarySettingsURL(for: profileID)
        ) ?? .defaults
        userConfig.apply(readerProfileSettings: reader)
        userConfig.apply(dictionaryProfileSettings: dictionary)
    }

    func persistCurrent(userConfig: UserConfig) {
        persistReaderSettings(userConfig.readerProfileSettings())
        persistDictionarySettings(userConfig.dictionaryProfileSettings())
    }

    func persistReaderSettings(_ settings: ReaderProfileSettings) {
        save(
            settings,
            to: repository.readerSettingsURL(for: appliedProfileID)
        )
    }

    func persistDictionarySettings(_ settings: DictionaryProfileSettings) {
        save(
            settings,
            to: repository.dictionarySettingsURL(for: appliedProfileID)
        )
    }

    func copyReaderSettings(from sourceProfileID: String, to destinationProfileID: String) {
        let source = repository.readerSettingsURL(for: sourceProfileID)
        let destination = repository.readerSettingsURL(for: destinationProfileID)
        guard FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
