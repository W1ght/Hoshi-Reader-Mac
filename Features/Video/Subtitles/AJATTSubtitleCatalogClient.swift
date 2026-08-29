import Foundation

nonisolated enum AJATTCatalogKind: String, CaseIterable, Identifiable, Sendable {
    case anime
    case liveAction

    var id: String { rawValue }
}

nonisolated enum AJATTEntryKind: String, Sendable {
    case animeTV = "anime_tv"
    case animeMovie = "anime_movie"
    case dramaTV = "drama_tv"
    case dramaMovie = "drama_movie"
    case unsorted

    var isMovie: Bool {
        self == .animeMovie || self == .dramaMovie
    }
}

nonisolated struct AJATTEntry: Equatable, Identifiable, Sendable {
    let name: String
    let englishName: String?
    let japaneseName: String?
    let kind: AJATTEntryKind
    let lastModified: Int64
    let pageURL: URL

    var id: String { pageURL.absoluteString }

    var secondaryName: String? {
        for candidate in [japaneseName, englishName] {
            guard let candidate,
                  !candidate.isEmpty,
                  candidate.localizedCaseInsensitiveCompare(name) != .orderedSame else {
                continue
            }
            return candidate
        }
        return nil
    }
}

nonisolated struct AJATTSubtitleFile: Equatable, Identifiable, Sendable {
    let name: String
    let size: Int64
    let lastModified: Int64
    let downloadURL: URL
    let format: SubtitleFormat

    var id: String { downloadURL.absoluteString }

    var remoteSubtitleOption: RemoteVideoSubtitleOption {
        RemoteVideoSubtitleOption(
            id: "ajatt:\(id)",
            language: "ja",
            name: name,
            url: downloadURL,
            format: format,
            isAutomatic: false,
            httpHeaders: [:]
        )
    }
}

nonisolated enum AJATTSubtitleCatalogError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            String(localized: "The AJATT subtitle request is invalid.")
        case .invalidResponse:
            String(localized: "AJATT returned an invalid subtitle catalog.")
        case .responseTooLarge:
            String(localized: "The AJATT subtitle catalog is too large to load safely.")
        case .httpStatus(let statusCode):
            String.localizedStringWithFormat(
                String(localized: "AJATT returned HTTP %lld."),
                Int64(statusCode)
            )
        }
    }
}

actor AJATTSubtitleCatalogClient {
    static let shared = AJATTSubtitleCatalogClient(session: makeLiveSession())

    private static let maximumCatalogResponseSize = 8 * 1_024 * 1_024
    private static let maximumEntryResponseSize = 10 * 1_024 * 1_024
    private static let maximumSubtitleFileSize: Int64 = 10 * 1_024 * 1_024
    private static let maximumSearchResults = 250
    private static let catalogLifetime: TimeInterval = 30 * 60
    private static let allowedEntryDirectories: Set<String> = [
        "anime_tv",
        "anime_movie",
        "drama_tv",
        "drama_movie",
        "unsorted",
    ]
    private static let allowedDownloadPathPrefix =
        "/Ajatt-Tools/kitsunekko-mirror/refs/heads/main/subtitles/"
    private static let episodePatterns: [NSRegularExpression] = [
        #"(?i)(?:^|[\s._-])S\d{1,2}[\s._-]*E(\d{1,4})(?:v\d+)?(?=[\s._\-\[(]|$)"#,
        #"(?i)(?:^|[\s._-])EP(?:ISODE)?[\s._-]*(\d{1,4})(?:v\d+)?(?=[\s._\-\[(]|$)"#,
        #"(?i)\s-\s*(\d{1,4})(?:v\d+)?(?=\s|[\[(_.-]|$)"#,
        #"(?i)(?:^|[\s._-])(\d{1,3})(?:v\d+)?(?=\.(?:srt|ass|ssa|vtt)$)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private struct CachedCatalog: Sendable {
        let entries: [AJATTEntry]
        let loadedAt: Date
    }

    private let session: URLSession
    private let baseURL: URL
    private var cachedCatalogs: [AJATTCatalogKind: CachedCatalog] = [:]

    init(
        session: URLSession,
        baseURL: URL = URL(string: "https://subtitles.ajatt.top/")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func searchEntries(
        query: String,
        kind: AJATTCatalogKind
    ) async throws -> [AJATTEntry] {
        let normalizedQuery = Self.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty, query.count <= 300 else {
            throw AJATTSubtitleCatalogError.invalidRequest
        }

        let entries = try await catalog(for: kind)
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        return entries.compactMap { entry -> (score: Int, entry: AJATTEntry)? in
            let scores = [entry.name, entry.englishName, entry.japaneseName]
                .compactMap { $0 }
                .compactMap { Self.matchScore(query: normalizedQuery, tokens: queryTokens, candidate: $0) }
            guard let score = scores.min() else { return nil }
            return (score, entry)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.entry.lastModified != rhs.entry.lastModified {
                return lhs.entry.lastModified > rhs.entry.lastModified
            }
            return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
        }
        .prefix(Self.maximumSearchResults)
        .map(\.entry)
    }

    func files(
        for entry: AJATTEntry,
        episode: Int?
    ) async throws -> [AJATTSubtitleFile] {
        guard Self.validEntryURL(entry.pageURL, relativeTo: baseURL),
              episode.map({ (0...9_999).contains($0) }) ?? true else {
            throw AJATTSubtitleCatalogError.invalidRequest
        }

        let data = try await responseData(
            url: entry.pageURL,
            maximumSize: Self.maximumEntryResponseSize
        )
        let files = try Self.parseFiles(data: data)
        return files.filter { file in
            guard let episode else { return true }
            return Self.episodeNumbers(in: file.name).contains(episode)
        }
        .sorted { lhs, rhs in
            if lhs.lastModified != rhs.lastModified {
                return lhs.lastModified > rhs.lastModified
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func catalog(for kind: AJATTCatalogKind) async throws -> [AJATTEntry] {
        if let cached = cachedCatalogs[kind],
           Date().timeIntervalSince(cached.loadedAt) < Self.catalogLifetime {
            return cached.entries
        }

        let catalogURL = baseURL.appendingPathComponent(
            kind == .anime ? "index.html" : "drama.html"
        )
        let data = try await responseData(
            url: catalogURL,
            maximumSize: Self.maximumCatalogResponseSize
        )
        let entries = try Self.parseEntries(
            data: data,
            catalogURL: catalogURL,
            baseURL: baseURL
        )
        cachedCatalogs[kind] = CachedCatalog(entries: entries, loadedAt: Date())
        return entries
    }

    private func responseData(url: URL, maximumSize: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let payload = try await BoundedURLSessionData.load(
                session: session,
                request: request,
                maximumSize: maximumSize
            ) { response in
                guard let response = response as? HTTPURLResponse else {
                    throw AJATTSubtitleCatalogError.invalidResponse
                }
                guard response.url?.scheme?.lowercased() == "https",
                      response.url?.user == nil,
                      response.url?.password == nil,
                      response.url?.host?.lowercased() == url.host?.lowercased() else {
                    throw AJATTSubtitleCatalogError.invalidResponse
                }
                guard (200...299).contains(response.statusCode) else {
                    throw AJATTSubtitleCatalogError.httpStatus(response.statusCode)
                }
                guard response.mimeType?.lowercased() == "text/html" else {
                    throw AJATTSubtitleCatalogError.invalidResponse
                }
            }
            return payload.0
        } catch BoundedURLSessionDataError.responseTooLarge {
            throw AJATTSubtitleCatalogError.responseTooLarge
        }
    }

    private static func parseEntries(
        data: Data,
        catalogURL: URL,
        baseURL: URL
    ) throws -> [AJATTEntry] {
        let document = try htmlDocument(data: data)
        let rows = try document.nodes(
            forXPath: "//table[contains(concat(' ', normalize-space(@class), ' '), ' index_table ')]//tr[@data-entry-type]"
        )
        let entries = rows.compactMap { node -> AJATTEntry? in
            guard let row = node as? XMLElement,
                  let kindValue = attribute("data-entry-type", in: row),
                  let kind = AJATTEntryKind(rawValue: kindValue),
                  let link = firstElement(
                    in: row,
                    xpath: ".//td[contains(concat(' ', normalize-space(@class), ' '), ' entry_name ')]/a"
                  ),
                  let href = attribute("href", in: link),
                  let pageURL = URL(string: href, relativeTo: catalogURL)?.absoluteURL,
                  validEntryURL(pageURL, relativeTo: baseURL),
                  let name = normalizedText(link.stringValue),
                  !name.isEmpty else {
                return nil
            }

            return AJATTEntry(
                name: name,
                englishName: optionalMetadataText(
                    firstElement(in: row, xpath: ".//td[contains(concat(' ', normalize-space(@class), ' '), ' english_name ')]")?.stringValue
                ),
                japaneseName: optionalMetadataText(
                    firstElement(in: row, xpath: ".//td[contains(concat(' ', normalize-space(@class), ' '), ' japanese_name ')]")?.stringValue
                ),
                kind: kind,
                lastModified: Int64(attribute("data-timestamp", in: row) ?? "") ?? 0,
                pageURL: pageURL
            )
        }
        guard !entries.isEmpty else {
            throw AJATTSubtitleCatalogError.invalidResponse
        }
        return entries
    }

    private static func parseFiles(data: Data) throws -> [AJATTSubtitleFile] {
        let document = try htmlDocument(data: data)
        let rows = try document.nodes(forXPath: "//tr[@data-file-size]")
        let parsed = rows.compactMap { node -> AJATTSubtitleFile? in
            guard let row = node as? XMLElement,
                  let size = Int64(attribute("data-file-size", in: row) ?? ""),
                  (0...maximumSubtitleFileSize).contains(size),
                  let checkbox = firstElement(
                    in: row,
                    xpath: ".//input[contains(concat(' ', normalize-space(@class), ' '), ' file-checkbox ')]"
                  ),
                  let name = normalizedText(attribute("data-filename", in: checkbox)),
                  let urlValue = attribute("data-download-url", in: checkbox),
                  let downloadURL = URL(string: urlValue),
                  validDownloadURL(downloadURL),
                  let format = subtitleFormat(for: name) else {
                return nil
            }
            return AJATTSubtitleFile(
                name: name,
                size: size,
                lastModified: Int64(attribute("data-timestamp", in: row) ?? "") ?? 0,
                downloadURL: downloadURL,
                format: format
            )
        }
        return Array(
            Dictionary(parsed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        )
    }

    private static func htmlDocument(data: Data) throws -> XMLDocument {
        guard let html = String(data: data, encoding: .utf8) else {
            throw AJATTSubtitleCatalogError.invalidResponse
        }
        do {
            return try XMLDocument(
                xmlString: html,
                options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw AJATTSubtitleCatalogError.invalidResponse
        }
    }

    private static func firstElement(in node: XMLNode, xpath: String) -> XMLElement? {
        (try? node.nodes(forXPath: xpath).first) as? XMLElement
    }

    private static func attribute(_ name: String, in element: XMLElement) -> String? {
        element.attribute(forName: name)?.stringValue
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optionalMetadataText(_ value: String?) -> String? {
        guard let value = normalizedText(value),
              !value.isEmpty,
              value.localizedCaseInsensitiveCompare("None") != .orderedSame else {
            return nil
        }
        return value
    }

    private static func validEntryURL(_ url: URL, relativeTo baseURL: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == baseURL.host?.lowercased(),
              url.pathExtension.lowercased() == "html" else {
            return false
        }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.count == 2 && allowedEntryDirectories.contains(components[0])
    }

    private static func validDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == "raw.githubusercontent.com",
              url.path.hasPrefix(allowedDownloadPathPrefix) else {
            return false
        }
        return subtitleFormat(for: url.lastPathComponent) != nil
    }

    private static func subtitleFormat(for fileName: String) -> SubtitleFormat? {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "srt": .srt
        case "vtt": .webVTT
        case "ass": .ass
        case "ssa": .ssa
        default: nil
        }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        var result = ""
        var needsSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !result.isEmpty {
                    result.append(" ")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchScore(
        query: String,
        tokens: [String],
        candidate: String
    ) -> Int? {
        let candidate = normalizedSearchText(candidate)
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 1 }
        if candidate.contains(query) { return 2 }
        if tokens.allSatisfy(candidate.contains) { return 3 }
        return nil
    }

    private static func episodeNumbers(in fileName: String) -> Set<Int> {
        var result: Set<Int> = []
        let range = NSRange(fileName.startIndex..., in: fileName)
        for expression in episodePatterns {
            for match in expression.matches(in: fileName, range: range) where match.numberOfRanges > 1 {
                guard let numberRange = Range(match.range(at: 1), in: fileName),
                      let number = Int(fileName[numberRange]) else {
                    continue
                }
                result.insert(number)
            }
        }
        return result
    }

    private static func makeLiveSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }
}
