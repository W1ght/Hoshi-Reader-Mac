import Foundation

public enum AidokuLimits {
    public static let maximumArchiveBytes = 64 * 1_024 * 1_024
    public static let maximumExpandedBytes = 256 * 1_024 * 1_024
    public static let maximumArchiveEntries = 512
    public static let maximumJSONBytes = 16 * 1_024 * 1_024
    public static let maximumImageBytes = 256 * 1_024 * 1_024
    public static let maximumCacheBytes: Int64 = 1_024 * 1_024 * 1_024
    public static let maximumCacheEntries = 1_024
    public static let maximumLinearMemoryBytes = 64 * 1_024 * 1_024
    public static let metadataTimeout: Duration = .seconds(30)
    public static let pageTimeout: Duration = .seconds(120)
}

public enum AidokuRuntimeError: LocalizedError, Sendable, Equatable {
    case invalidArchive
    case archiveTooLarge
    case expandedArchiveTooLarge
    case tooManyArchiveEntries
    case unsafeArchivePath(String)
    case symbolicLink(String)
    case missingPayload(String)
    case invalidManifest
    case altStoreAppCatalog
    case invalidSourceID
    case sourceIDMismatch(expected: String, actual: String)
    case invalidWasm
    case incompatibleSource(String)
    case unsupportedURL
    case insecureTransportRequiresConfirmation
    case responseTooLarge
    case timedOut
    case cancelled
    case sourceUnavailable
    case malformedPostcard
    case runtimeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "The file is not a valid Aidoku source package."
        case .archiveTooLarge: "The Aidoku source package exceeds 64 MiB."
        case .expandedArchiveTooLarge: "The expanded Aidoku source package exceeds 256 MiB."
        case .tooManyArchiveEntries: "The Aidoku source package contains too many files."
        case .unsafeArchivePath(let path): "The source package contains an unsafe path: \(path)"
        case .symbolicLink(let path): "The source package contains a symbolic link: \(path)"
        case .missingPayload(let name): "The source package is missing Payload/\(name)."
        case .invalidManifest: "The source package manifest is invalid."
        case .altStoreAppCatalog:
            "This URL is an AltStore app catalog for installing Aidoku, not an Aidoku source list containing .aix sources."
        case .invalidSourceID: "The source package has an unsafe source identifier."
        case .sourceIDMismatch(let expected, let actual):
            "The source identifier does not match (expected \(expected), found \(actual))."
        case .invalidWasm: "The source package does not contain a valid WebAssembly module."
        case .incompatibleSource(let reason): "The Aidoku source is incompatible: \(reason)"
        case .unsupportedURL: "Only HTTP and HTTPS source URLs are supported."
        case .insecureTransportRequiresConfirmation:
            "This source uses HTTP or a local-network address and requires confirmation."
        case .responseTooLarge: "The source response is too large."
        case .timedOut: "The Aidoku source timed out."
        case .cancelled: "The Aidoku source operation was cancelled."
        case .sourceUnavailable: "The Aidoku source is not installed."
        case .malformedPostcard: "The Aidoku source returned malformed Postcard data."
        case .runtimeFailure(let message): message
        }
    }
}

public enum AidokuSourceContentRating: Int, Codable, Sendable, CaseIterable {
    case safe = 0
    case containsAdultContent = 1
    case primarilyAdultContent = 2
}

/// The built-in language selector requested by an Aidoku source manifest.
///
/// Community manifests use `multi`, while some runner versions expose the
/// equivalent value as `multiple`. Decoding both keeps locally imported and
/// source-list packages interoperable without changing the canonical schema.
public enum AidokuLanguageSelectType: Sendable, Equatable, Codable {
    case single
    case multiple

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "single": self = .single
        case "multi", "multiple": self = .multiple
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Aidoku language selection type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self == .single ? "single" : "multi")
    }
}

/// Normalizes language choices and encodes the defaults ABI consumed by
/// Aidoku sources (`language: String` or `languages: [String]`).
public enum AidokuLanguageDefaults {
    public static func supportedLanguages(_ languages: [String]) -> [String] {
        var seen = Set<String>()
        return languages.compactMap { language in
            let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = canonicalIdentifier(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    public static func normalizedSelection(
        supportedLanguages: [String],
        selectedLanguages: [String]?,
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages,
        type: AidokuLanguageSelectType
    ) -> [String] {
        let supported = self.supportedLanguages(supportedLanguages)
        guard !supported.isEmpty else { return [] }

        let selectedKeys = Set((selectedLanguages ?? []).compactMap {
            bestMatch(for: $0, supportedLanguages: supported).map(canonicalIdentifier)
        })
        var result = supported.filter { selectedKeys.contains(canonicalIdentifier($0)) }

        if result.isEmpty {
            switch type {
            case .single:
                result = preferredLanguageIdentifiers.lazy.compactMap { preferred in
                    bestMatch(for: preferred, supportedLanguages: supported)
                }.first.map { [$0] } ?? []
            case .multiple:
                let preferredKeys = Set(preferredLanguageIdentifiers.compactMap {
                    bestMatch(for: $0, supportedLanguages: supported).map(canonicalIdentifier)
                })
                result = supported.filter { preferredKeys.contains(canonicalIdentifier($0)) }
            }
        }

        if result.isEmpty { result = [supported[0]] }
        if type == .single { return [result[0]] }
        return result
    }

    public static func encodedDefaults(
        type: AidokuLanguageSelectType,
        selectedLanguages: [String]
    ) -> [String: Data] {
        guard !selectedLanguages.isEmpty else { return [:] }
        var writer = AidokuPostcardWriter()
        switch type {
        case .single:
            writer.write(selectedLanguages[0])
            return ["language": writer.data]
        case .multiple:
            writer.write(selectedLanguages) { $0.write($1) }
            return ["languages": writer.data]
        }
    }

    /// Returns whether a manifest represents a true multi-language source.
    /// Some source lists use the literal `multi` sentinel instead of listing
    /// every language, while native multi-language sources enumerate them.
    public static func isMultilingual(_ languages: [String]) -> Bool {
        let supported = supportedLanguages(languages)
        return supported.count > 1 || supported.contains {
            canonicalIdentifier($0) == "multi"
        }
    }

    /// Matches the language categories shown by the source browser.
    /// A base category such as `zh` includes script/region variants such as
    /// `zh-Hans` and `zh-Hant`; selecting a specific variant remains exact.
    public static func matchesLanguageFilter(
        _ filter: String,
        supportedLanguages languages: [String]
    ) -> Bool {
        let filterKey = canonicalIdentifier(filter)
        guard !filterKey.isEmpty else { return false }
        guard filterKey != "all" else { return false }
        if filterKey == "multi" { return isMultilingual(languages) }

        let supported = supportedLanguages(languages).map(canonicalIdentifier)
        if supported.contains(filterKey) { return true }
        guard !filterKey.contains("-") else { return false }
        return supported.contains {
            $0.split(separator: "-").first.map(String.init) == filterKey
        }
    }

    private static func bestMatch(
        for preferredLanguage: String,
        supportedLanguages: [String]
    ) -> String? {
        let preferred = canonicalIdentifier(preferredLanguage)
        if let exact = supportedLanguages.first(where: { canonicalIdentifier($0) == preferred }) {
            return exact
        }
        let preferredParts = preferred.split(separator: "-").map(String.init)
        if preferredParts.first == "zh" {
            let traditional = preferredParts.contains("hant")
                || preferredParts.contains(where: { ["tw", "hk", "mo"].contains($0) })
            let simplified = preferredParts.contains("hans")
                || preferredParts.contains(where: { ["cn", "sg", "my"].contains($0) })
            let desiredScript = traditional ? "zh-hant" : simplified ? "zh-hans" : nil
            if let desiredScript,
               let match = supportedLanguages.first(where: {
                   canonicalIdentifier($0) == desiredScript
               }) {
                return match
            }
        }
        let prefixMatches = supportedLanguages.filter {
            let supported = canonicalIdentifier($0)
            return preferred.hasPrefix("\(supported)-") || supported.hasPrefix("\(preferred)-")
        }
        if let mostSpecific = prefixMatches.max(by: {
            canonicalIdentifier($0).count < canonicalIdentifier($1).count
        }) {
            return mostSpecific
        }
        let preferredBase = preferred.split(separator: "-").first
        return supportedLanguages.first {
            canonicalIdentifier($0).split(separator: "-").first == preferredBase
        }
    }

    private static func canonicalIdentifier(_ identifier: String) -> String {
        identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}

public struct AidokuSourceManifest: Codable, Sendable, Equatable {
    public struct Info: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let altNames: [String]?
        public let version: Int
        public let url: String?
        public let urls: [String]?
        public let contentRating: AidokuSourceContentRating?
        public let languages: [String]?
        public let minAppVersion: String?
        public let maxAppVersion: String?

        public init(
            id: String,
            name: String,
            altNames: [String]? = nil,
            version: Int,
            url: String? = nil,
            urls: [String]? = nil,
            contentRating: AidokuSourceContentRating? = nil,
            languages: [String]? = nil,
            minAppVersion: String? = nil,
            maxAppVersion: String? = nil
        ) {
            self.id = id
            self.name = name
            self.altNames = altNames
            self.version = version
            self.url = url
            self.urls = urls
            self.contentRating = contentRating
            self.languages = languages
            self.minAppVersion = minAppVersion
            self.maxAppVersion = maxAppVersion
        }
    }

    public struct Configuration: Codable, Sendable, Equatable {
        public let breakingChangeVersion: Int?
        public let maximumNetworkRequests: Int?
        public let maximumParallelRequests: Int?
        public let userAgent: String?
        public let languageSelectType: AidokuLanguageSelectType?
        public let allowsBaseUrlSelect: Bool?
        public let requiresAuth: Bool?

        public init(
            breakingChangeVersion: Int? = nil,
            maximumNetworkRequests: Int? = nil,
            maximumParallelRequests: Int? = nil,
            userAgent: String? = nil,
            languageSelectType: AidokuLanguageSelectType? = nil,
            allowsBaseUrlSelect: Bool? = nil,
            requiresAuth: Bool? = nil
        ) {
            self.breakingChangeVersion = breakingChangeVersion
            self.maximumNetworkRequests = maximumNetworkRequests
            self.maximumParallelRequests = maximumParallelRequests
            self.userAgent = userAgent
            self.languageSelectType = languageSelectType
            self.allowsBaseUrlSelect = allowsBaseUrlSelect
            self.requiresAuth = requiresAuth
        }

        public var resolvedMaximumParallelRequests: Int {
            maximumParallelRequests ?? maximumNetworkRequests ?? 5
        }
    }

    public let info: Info
    public let listings: [AidokuListing]?
    public let config: Configuration?
    /// Whether the source declares that browsing requires a user login.
    /// Older manifests omit this field, which retains the unauthenticated default.
    public let requiresAuth: Bool

    public init(
        info: Info,
        listings: [AidokuListing]? = nil,
        config: Configuration? = nil,
        requiresAuth: Bool = false
    ) {
        self.info = info
        self.listings = listings
        self.config = config
        self.requiresAuth = requiresAuth
    }

    private enum CodingKeys: String, CodingKey {
        case info
        case listings
        case config
        case requiresAuth
        case requiresAuthentication
        case requires_auth
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        info = try values.decode(Info.self, forKey: .info)
        listings = try values.decodeIfPresent([AidokuListing].self, forKey: .listings)
        config = try values.decodeIfPresent(Configuration.self, forKey: .config)
        let topLevelRequiresAuth = try values.decodeIfPresent(Bool.self, forKey: .requiresAuth)
            ?? values.decodeIfPresent(Bool.self, forKey: .requiresAuthentication)
            ?? values.decodeIfPresent(Bool.self, forKey: .requires_auth)
        requiresAuth = config?.requiresAuth
            ?? topLevelRequiresAuth
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(info, forKey: .info)
        try values.encodeIfPresent(listings, forKey: .listings)
        try values.encodeIfPresent(config, forKey: .config)
        if config?.requiresAuth == nil {
            try values.encode(requiresAuth, forKey: .requiresAuth)
        }
    }

    /// Current Aidoku runners treat a multi-language source without an
    /// explicit selection type as a multiple-selection source. This matters
    /// for sources such as MangaDex and MangaPlus, which read `languages`.
    public var resolvedLanguageSelectType: AidokuLanguageSelectType? {
        let languages = AidokuLanguageDefaults.supportedLanguages(info.languages ?? [])
        guard languages.count > 1 else { return nil }
        return config?.languageSelectType ?? .multiple
    }
}

public struct AidokuSourceList: Codable, Sendable, Equatable {
    public struct Entry: Codable, Identifiable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let version: Int
        public let iconURL: String?
        public let downloadURL: String?
        public let languages: [String]?
        public let contentRating: AidokuSourceContentRating?
        public let altNames: [String]?
        public let baseURL: String?
        public let minAppVersion: String?
        public let maxAppVersion: String?

        public init(
            id: String,
            name: String,
            version: Int,
            iconURL: String? = nil,
            downloadURL: String? = nil,
            languages: [String]? = nil,
            contentRating: AidokuSourceContentRating? = nil,
            altNames: [String]? = nil,
            baseURL: String? = nil,
            minAppVersion: String? = nil,
            maxAppVersion: String? = nil
        ) {
            self.id = id
            self.name = name
            self.version = version
            self.iconURL = iconURL
            self.downloadURL = downloadURL
            self.languages = languages
            self.contentRating = contentRating
            self.altNames = altNames
            self.baseURL = baseURL
            self.minAppVersion = minAppVersion
            self.maxAppVersion = maxAppVersion
        }
    }

    public let name: String
    public let feedbackURL: String?
    public let sources: [Entry]

    public init(name: String, feedbackURL: String? = nil, sources: [Entry]) {
        self.name = name
        self.feedbackURL = feedbackURL
        self.sources = sources
    }
}

public enum AidokuSourceSearch {
    public static func hasTerms(_ query: String) -> Bool {
        !normalizedTerms(query, locale: .current).isEmpty
    }

    public static func matches(
        query: String,
        fields: [String],
        locale: Locale = .current
    ) -> Bool {
        let terms = normalizedTerms(query, locale: locale)
        guard !terms.isEmpty else { return true }
        let searchable = folded(fields.joined(separator: "\u{1f}"), locale: locale)
        return terms.allSatisfy(searchable.contains)
    }

    private static func normalizedTerms(_ query: String, locale: Locale) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { folded(String($0), locale: locale) }
            .filter { !$0.isEmpty }
    }

    private static func folded(_ value: String, locale: Locale) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale
        )
    }
}

public enum AidokuMangaStatus: UInt8, Codable, Sendable {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case cancelled = 3
    case hiatus = 4
}

public enum AidokuMangaContentRating: UInt8, Codable, Sendable {
    case unknown = 0
    case safe = 1
    case suggestive = 2
    case adult = 3
}

public enum AidokuViewer: UInt8, Codable, Sendable {
    case defaultViewer = 0
    case leftToRight = 1
    case rightToLeft = 2
    case vertical = 3
    case webtoon = 4
}

public struct AidokuManga: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String { key }
    public let key: String
    public var title: String
    public var coverURL: String?
    public var artists: [String]?
    public var authors: [String]?
    public var summary: String?
    public var url: String?
    public var tags: [String]?
    public var status: AidokuMangaStatus
    public var contentRating: AidokuMangaContentRating
    public var viewer: AidokuViewer
    public var chapters: [AidokuChapter]?

    public init(
        key: String,
        title: String,
        coverURL: String? = nil,
        artists: [String]? = nil,
        authors: [String]? = nil,
        summary: String? = nil,
        url: String? = nil,
        tags: [String]? = nil,
        status: AidokuMangaStatus = .unknown,
        contentRating: AidokuMangaContentRating = .unknown,
        viewer: AidokuViewer = .defaultViewer,
        chapters: [AidokuChapter]? = nil
    ) {
        self.key = key
        self.title = title
        self.coverURL = coverURL
        self.artists = artists
        self.authors = authors
        self.summary = summary
        self.url = url
        self.tags = tags
        self.status = status
        self.contentRating = contentRating
        self.viewer = viewer
        self.chapters = chapters
    }
}

public struct AidokuChapter: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String { key }
    public let key: String
    public var title: String?
    public var chapterNumber: Float?
    public var volumeNumber: Float?
    public var dateUploaded: Int64?
    public var scanlators: [String]?
    public var url: String?
    public var language: String?
    public var thumbnailURL: String?
    public var locked: Bool

    public init(
        key: String,
        title: String? = nil,
        chapterNumber: Float? = nil,
        volumeNumber: Float? = nil,
        dateUploaded: Int64? = nil,
        scanlators: [String]? = nil,
        url: String? = nil,
        language: String? = nil,
        thumbnailURL: String? = nil,
        locked: Bool = false
    ) {
        self.key = key
        self.title = title
        self.chapterNumber = chapterNumber
        self.volumeNumber = volumeNumber
        self.dateUploaded = dateUploaded
        self.scanlators = scanlators
        self.url = url
        self.language = language
        self.thumbnailURL = thumbnailURL
        self.locked = locked
    }
}

public struct AidokuMangaPage: Codable, Sendable, Equatable {
    public let entries: [AidokuManga]
    public let hasNextPage: Bool

    public init(entries: [AidokuManga], hasNextPage: Bool) {
        self.entries = entries
        self.hasNextPage = hasNextPage
    }
}

public enum AidokuPageContent: Codable, Sendable, Equatable, Hashable {
    case url(String, context: [String: String])
    case text(String)
    case image(Data)
    case zip(url: String, path: String)
}

public struct AidokuImageRequest: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public struct AidokuStoredCookie: Codable, Sendable, Equatable, Hashable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let secure: Bool
    public let expiresAt: Date?

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        secure: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.expiresAt = expiresAt
    }
}

public struct AidokuPage: Codable, Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let index: Int
    public let content: AidokuPageContent
    public let thumbnailURL: String?
    public let hasDescription: Bool
    public let description: String?

    public init(
        id: String,
        index: Int,
        content: AidokuPageContent,
        thumbnailURL: String? = nil,
        hasDescription: Bool = false,
        description: String? = nil
    ) {
        self.id = id
        self.index = index
        self.content = content
        self.thumbnailURL = thumbnailURL
        self.hasDescription = hasDescription
        self.description = description
    }
}

public enum AidokuFilterValue: Codable, Sendable, Equatable, Hashable {
    case text(String)
    case check(Int)
    case select(String)
    case multiSelect(include: Set<String>, exclude: Set<String>)
    case sort(index: Int, ascending: Bool)
    case range(lower: Float?, upper: Float?)
}

public enum AidokuFilter: Codable, Identifiable, Sendable, Equatable, Hashable {
    case header(id: String, title: String)
    case text(id: String, title: String, placeholder: String?)
    case check(id: String, title: String, canExclude: Bool, defaultValue: Int)
    case select(id: String, title: String, options: [String], values: [String], defaultValue: String?)
    case multiSelect(id: String, title: String, options: [String], values: [String])
    case sort(id: String, title: String, options: [String], canAscend: Bool)
    case range(id: String, title: String, minimum: Float?, maximum: Float?, decimal: Bool)

    public var id: String {
        switch self {
        case .header(let id, _), .text(let id, _, _), .check(let id, _, _, _),
             .select(let id, _, _, _, _), .multiSelect(let id, _, _, _),
             .sort(let id, _, _, _), .range(let id, _, _, _, _): id
        }
    }
}

public enum AidokuLoginMethod: String, Codable, Sendable, Equatable, Hashable {
    case basic
    case web
    case oauth
}

public struct AidokuLoginConfiguration: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let method: AidokuLoginMethod
    public let url: String?
    public let urlKey: String?
    public let localStorageKeys: [String]

    public init(
        key: String,
        title: String,
        method: AidokuLoginMethod,
        url: String? = nil,
        urlKey: String? = nil,
        localStorageKeys: [String] = []
    ) {
        self.key = key
        self.title = title
        self.method = method
        self.url = url
        self.urlKey = urlKey
        self.localStorageKeys = localStorageKeys
    }
}

public enum AidokuSetting: Codable, Identifiable, Sendable, Equatable, Hashable {
    case header(id: String, title: String)
    case switchValue(id: String, title: String, defaultValue: Bool, secure: Bool)
    case select(id: String, title: String, values: [String], labels: [String], defaultValue: String?)
    case multiSelect(id: String, title: String, values: [String], labels: [String], defaultValues: [String]?)
    case segment(id: String, title: String, options: [String], defaultIndex: Int32?)
    case text(id: String, title: String, defaultValue: String?, secure: Bool)
    case stepper(id: String, title: String, defaultValue: Double?, min: Double, max: Double, step: Double)
    case editableList(id: String, title: String, placeholder: String?, defaultValues: [String]?)
    case login(AidokuLoginConfiguration)

    public var id: String {
        switch self {
        case .header(let id, _), .switchValue(let id, _, _, _),
             .select(let id, _, _, _, _), .multiSelect(let id, _, _, _, _),
             .segment(let id, _, _, _), .text(let id, _, _, _), .stepper(let id, _, _, _, _, _),
             .editableList(let id, _, _, _): id
        case .login(let configuration): configuration.key
        }
    }
}

public enum AidokuListingKind: UInt8, Codable, Sendable {
    case defaultListing = 0
    case popular = 1
    case latest = 2

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(UInt8.self)) ?? .defaultListing
    }
}

public struct AidokuListing: Codable, Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let kind: AidokuListingKind

    public init(id: String, name: String, kind: AidokuListingKind = .defaultListing) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        kind = try container.decodeIfPresent(AidokuListingKind.self, forKey: .kind)
            ?? .defaultListing
    }
}

public struct AidokuInstalledSource: Codable, Identifiable, Sendable, Equatable {
    public var id: String { manifest.info.id }
    public let manifest: AidokuSourceManifest
    public let directory: URL
    public let installedAt: Date

    public init(manifest: AidokuSourceManifest, directory: URL, installedAt: Date) {
        self.manifest = manifest
        self.directory = directory
        self.installedAt = installedAt
    }
}
