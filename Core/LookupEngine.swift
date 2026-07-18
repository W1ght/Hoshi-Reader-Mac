//
//  LookupEngine.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CHoshiDicts

class LookupEngine {
    static let shared = LookupEngine()

    private struct QueryConfiguration: Equatable {
        let termPaths: [URL]
        let freqPaths: [URL]
        let pitchPaths: [URL]
        let languageID: String
        let contentGeneration: UInt64
    }
    
    private var dictQuery: DictionaryQuery?
    private var lookupEngine: Lookup?
    private var activeConfiguration: QueryConfiguration?
    private(set) var languageID = ContentLanguageProfile.japanese.rawValue
    
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
        guard configuration != activeConfiguration else { return }

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
        lookupEngine = Lookup(&dictQuery!, processor.pointee)
        self.languageID = configuration.languageID
        activeConfiguration = configuration
    }
    
    func lookup(_ str: String, maxResults: Int = 16, scanLength: Int = 16) -> [LookupResult] {
        return Array(lookupEngine?.lookup(std.string(str), Int32(maxResults), scanLength) ?? [])
    }
    
    func getStyles() -> [DictionaryStyle] {
        return Array(dictQuery?.get_styles() ?? [])
    }
    
    func withMediaFile<T>(dictName: String, mediaPath: String, _ body: (Data) -> T) -> T {
        guard dictQuery != nil else {
            return body(Data())
        }
        let view = dictQuery!.get_media_file_view(std.string(dictName), std.string(mediaPath))
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
