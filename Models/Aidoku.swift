import AidokuRuntime
import Foundation

nonisolated enum AidokuCatalogDefaults {
    static let communitySourceListName = "Aidoku Community Sources"
    static let communitySourceListURL = URL(
        string: "https://aidoku-community.github.io/sources/index.min.json"
    )!

    static func isBuiltInSourceListURL(_ url: URL) -> Bool {
        url == communitySourceListURL
    }
}

nonisolated struct AidokuSourceListRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var url: URL
    var insecureTransportApproved: Bool
    var lastCheckedAt: Date?
    var cachedSources: [AidokuSourceList.Entry]?
    var isBuiltIn: Bool { AidokuCatalogDefaults.isBuiltInSourceListURL(url) }

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        insecureTransportApproved: Bool,
        lastCheckedAt: Date? = nil,
        cachedSources: [AidokuSourceList.Entry]? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.insecureTransportApproved = insecureTransportApproved
        self.lastCheckedAt = lastCheckedAt
        self.cachedSources = cachedSources
    }
}

nonisolated struct AidokuAvailableSource: Identifiable, Sendable, Equatable {
    var id: String { "\(listID.uuidString)\u{1f}\(entry.id)" }
    let listID: UUID
    let listName: String
    let entry: AidokuSourceList.Entry
}

nonisolated struct AidokuInstalledSourceRecord: Codable, Identifiable, Sendable, Equatable {
    var id: String { sourceID }
    let sourceID: String
    var name: String
    var version: Int
    var contentRating: AidokuSourceContentRating
    var languages: [String]
    var listID: UUID?
    var downloadURL: URL?
    var pendingUpdateVersion: Int?
    var pendingUpdateURL: URL?
    var installedAt: Date
    var lastFailure: String?
}

nonisolated struct AidokuLibraryEntry: Codable, Identifiable, Sendable, Equatable {
    var id: String { "\(sourceID)\u{1f}\(manga.key)" }
    let sourceID: String
    var sourceName: String
    var manga: AidokuManga
    var addedAt: Date
    var updatedAt: Date
    var discoveryWorkID: String? = nil
}

nonisolated struct AidokuDiscoverySourceMapping: Codable, Sendable, Equatable {
    var sourceID: String
    var manga: AidokuManga
    var updatedAt: Date
}

nonisolated struct AidokuChapterProgress: Codable, Identifiable, Sendable, Equatable {
    var id: String { "\(sourceID)\u{1f}\(mangaKey)\u{1f}\(chapterKey)" }
    let sourceID: String
    let mangaKey: String
    let chapterKey: String
    var pageIndex: Int
    var pageCount: Int
    var completed: Bool
    var updatedAt: Date
}

nonisolated struct AidokuSourceLanguageSelection: Sendable, Equatable {
    let type: AidokuLanguageSelectType
    let supportedLanguages: [String]
    let selectedLanguages: [String]
}

nonisolated struct AidokuGlobalCatalog: Codable, Sendable, Equatable {
    var sourceLists: [AidokuSourceListRecord] = []
    var installedSources: [AidokuInstalledSourceRecord] = []
    var library: [AidokuLibraryEntry] = []
    var progress: [AidokuChapterProgress] = []
    var sourceDefaults: [String: [String: Data]] = [:]
    var sourceDirectMediaConnections: [String: Bool]?
    var sourceLanguageSelections: [String: [String]]?
    var discoverySourceMappings: [String: AidokuDiscoverySourceMapping]?
    var allowsAdultContent = false
    var didAcknowledgeThirdPartyDisclosure = false

    @discardableResult
    mutating func seedBuiltInSourceLists() -> Bool {
        guard !sourceLists.contains(where: { $0.isBuiltIn }) else { return false }
        sourceLists.insert(AidokuSourceListRecord(
            name: AidokuCatalogDefaults.communitySourceListName,
            url: AidokuCatalogDefaults.communitySourceListURL,
            insecureTransportApproved: false
        ), at: 0)
        return true
    }
}
