//
//  LookupEngine.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CHoshiDicts

@Observable
class LookupEngine {
    static let shared = LookupEngine()

    private nonisolated struct QueryConfiguration: Equatable, Sendable {
        let termPaths: [URL]
        let freqPaths: [URL]
        let pitchPaths: [URL]
        let languageID: String
        let contentGeneration: UInt64
    }

    private nonisolated final class QueryBundle: @unchecked Sendable {
        let configuration: QueryConfiguration
        var dictQuery: DictionaryQuery
        var lookup: Lookup!

        init(configuration: QueryConfiguration) {
            self.configuration = configuration

            var query = DictionaryQuery()
            for path in configuration.termPaths {
                query.add_term_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in configuration.freqPaths {
                query.add_freq_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in configuration.pitchPaths {
                query.add_pitch_dict(std.string(path.path(percentEncoded: false)))
            }

            let processor = configuration.languageID.withCString {
                language.get(std.string_view($0))
            }
            dictQuery = consume query
            lookup = Lookup(&dictQuery, processor.pointee)
        }
    }

    private var bundle: QueryBundle?
    private var activeConfiguration: QueryConfiguration?
    private var requestedConfiguration: QueryConfiguration?
    private var buildGeneration: UInt64 = 0
    private(set) var languageID = ContentLanguageProfile.japanese.rawValue
    private(set) var isReadyForLookup = false
    
    private init() {}
    
    func buildQuery(
        termPaths: [URL],
        freqPaths: [URL],
        pitchPaths: [URL],
        languageID: String = ContentLanguageProfile.japanese.rawValue,
        contentGeneration: UInt64
    ) {
        let normalizedLanguageID = ContentLanguageProfile(rawValue: languageID)?.rawValue
            ?? ContentLanguageProfile.japanese.rawValue
        let configuration = QueryConfiguration(
            termPaths: termPaths,
            freqPaths: freqPaths,
            pitchPaths: pitchPaths,
            languageID: normalizedLanguageID,
            contentGeneration: contentGeneration
        )
        if configuration == activeConfiguration {
            if requestedConfiguration != activeConfiguration {
                buildGeneration &+= 1
                requestedConfiguration = activeConfiguration
            }
            isReadyForLookup = true
            return
        }
        guard configuration != requestedConfiguration else { return }

        buildGeneration &+= 1
        let generation = buildGeneration
        requestedConfiguration = configuration
        isReadyForLookup = false
        Task.detached(priority: .userInitiated) {
            let newBundle = QueryBundle(configuration: configuration)
            await MainActor.run {
                guard generation == self.buildGeneration,
                      configuration == self.requestedConfiguration else {
                    return
                }
                self.bundle = newBundle
                self.activeConfiguration = configuration
                self.languageID = configuration.languageID
                self.isReadyForLookup = true
            }
        }
    }
    
    func lookup(_ str: String, maxResults: Int = 16, scanLength: Int = 16) -> [LookupResult] {
        guard isReadyForLookup, let bundle, activeConfiguration == requestedConfiguration else { return [] }
        return Array(bundle.lookup.lookup(std.string(str), Int32(maxResults), scanLength))
    }
    
    func getStyles() -> [DictionaryStyle] {
        guard isReadyForLookup, let bundle, activeConfiguration == requestedConfiguration else { return [] }
        return Array(bundle.dictQuery.get_styles())
    }
    
    func withMediaFile<T>(dictName: String, mediaPath: String, _ body: (Data) -> T) -> T {
        guard isReadyForLookup, let bundle, activeConfiguration == requestedConfiguration else {
            return body(Data())
        }
        let view = bundle.dictQuery.get_media_file_view(std.string(dictName), std.string(mediaPath))
        let size = Int(view.size)
        guard size > 0, let ptr = UnsafeMutableRawPointer(mutating: view.data) else {
            return body(Data())
        }
        let data = Data(bytesNoCopy: ptr, count: size, deallocator: .none)
        return body(data)
    }
    
    func getMediaFile(dictName: String, mediaPath: String) -> Data {
        return withMediaFile(dictName: dictName, mediaPath: mediaPath) { Data($0) }
    }
}
