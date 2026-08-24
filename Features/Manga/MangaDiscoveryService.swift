import Foundation

nonisolated enum MangaDiscoveryProviderID: String, CaseIterable, Codable, Sendable {
    case aniList
    case myAnimeList
}

nonisolated struct MangaDiscoveryIdentity: Codable, Hashable, Identifiable, Sendable {
    let provider: MangaDiscoveryProviderID
    let providerID: String
    let malID: Int?

    var id: String { "\(provider.rawValue):\(providerID)" }

    var canonicalWorkID: String {
        if let malID { return "mal:\(malID)" }
        switch provider {
        case .aniList: return "anilist:\(providerID)"
        case .myAnimeList: return "mal:\(providerID)"
        }
    }
}

nonisolated struct MangaDiscoveryWork: Codable, Hashable, Identifiable, Sendable {
    let identity: MangaDiscoveryIdentity
    var title: String
    var englishTitle: String?
    var romajiTitle: String?
    var nativeTitle: String?
    var synonyms: [String]
    var coverURL: URL?
    var bannerURL: URL?
    var summary: String?
    var authors: [String]
    var status: String?
    var format: String?
    var score: Double?
    var tags: [String]
    var chapterCount: Int?
    var volumeCount: Int?
    var siteURL: URL?
    var isAdult: Bool

    var id: MangaDiscoveryIdentity { identity }

    var mappingTitles: [String] {
        var seen = Set<String>()
        return [title, nativeTitle, romajiTitle, englishTitle]
            .compactMap { $0 }
            .appending(contentsOf: synonyms)
            .filter {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && seen.insert(value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )).inserted
            }
    }
}

nonisolated struct MangaDiscoveryPage: Sendable, Equatable {
    let entries: [MangaDiscoveryWork]
    let hasNextPage: Bool
}

nonisolated struct MangaDiscoverySection: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let entries: [MangaDiscoveryWork]
    let errorMessage: String?
}

nonisolated protocol MangaDiscoveryProvider: Sendable {
    var id: MangaDiscoveryProviderID { get }
    func homeSections(allowsAdult: Bool) async throws -> [MangaDiscoverySection]
    func search(query: String, page: Int, allowsAdult: Bool) async throws -> MangaDiscoveryPage
    func details(identity: MangaDiscoveryIdentity) async throws -> MangaDiscoveryWork
}

nonisolated enum MangaDiscoveryError: LocalizedError, Sendable, Equatable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case rateLimited(retryAfter: TimeInterval?)
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            String(localized: "The discovery request is invalid.")
        case .invalidResponse:
            String(localized: "The discovery provider returned an invalid response.")
        case .responseTooLarge:
            String(localized: "The discovery provider response is too large.")
        case .rateLimited(let retryAfter):
            if let retryAfter {
                String(localized: "The discovery provider is rate limiting requests. Try again in \(Int(ceil(retryAfter))) seconds.")
            } else {
                String(localized: "The discovery provider is rate limiting requests. Try again later.")
            }
        case .provider(let message):
            message
        }
    }
}

nonisolated struct MangaDiscoveryHTTPClient: Sendable {
    static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = timeout
    }

    func data(for input: URLRequest) async throws -> Data {
        guard input.url?.scheme?.lowercased() == "https" else {
            throw MangaDiscoveryError.invalidRequest
        }
        var request = input
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme?.lowercased() == "https" else {
            throw MangaDiscoveryError.invalidResponse
        }
        if response.statusCode == 429 {
            throw MangaDiscoveryError.rateLimited(
                retryAfter: Self.retryAfter(from: response)
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MangaDiscoveryError.provider(
                String(localized: "The discovery provider returned HTTP \(response.statusCode).")
            )
        }
        if let expectedLength = response.value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int.init),
           expectedLength > Self.maximumResponseBytes {
            throw MangaDiscoveryError.responseTooLarge
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw MangaDiscoveryError.responseTooLarge
        }
        return data
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}

nonisolated struct AniListMangaDiscoveryProvider: MangaDiscoveryProvider {
    let id = MangaDiscoveryProviderID.aniList
    private let client: MangaDiscoveryHTTPClient
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    init(session: URLSession = .shared) {
        client = MangaDiscoveryHTTPClient(session: session)
    }

    func homeSections(allowsAdult: Bool) async throws -> [MangaDiscoverySection] {
        let descriptors = [
            ("trending", "Trending", "TRENDING_DESC"),
            ("popular", "Popular", "POPULARITY_DESC"),
            ("top-rated", "Top Rated", "SCORE_DESC"),
        ]
        return await withTaskGroup(
            of: (Int, Result<MangaDiscoveryPage, Error>).self,
            returning: [MangaDiscoverySection].self
        ) { group in
            for (index, descriptor) in descriptors.enumerated() {
                group.addTask {
                    do {
                        return (
                            index,
                            .success(try await loadPage(
                                search: nil,
                                page: 1,
                                sort: [descriptor.2],
                                allowsAdult: allowsAdult
                            ))
                        )
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results = Array<MangaDiscoverySection?>(repeating: nil, count: descriptors.count)
            for await (index, result) in group {
                let descriptor = descriptors[index]
                switch result {
                case .success(let page):
                    results[index] = MangaDiscoverySection(
                        id: descriptor.0,
                        title: descriptor.1,
                        entries: page.entries,
                        errorMessage: nil
                    )
                case .failure(let error):
                    results[index] = MangaDiscoverySection(
                        id: descriptor.0,
                        title: descriptor.1,
                        entries: [],
                        errorMessage: error.localizedDescription
                    )
                }
            }
            return results.compactMap { $0 }
        }
    }

    func search(query: String, page: Int, allowsAdult: Bool) async throws -> MangaDiscoveryPage {
        try await loadPage(
            search: query,
            page: page,
            sort: ["SEARCH_MATCH", "POPULARITY_DESC"],
            allowsAdult: allowsAdult
        )
    }

    func details(identity: MangaDiscoveryIdentity) async throws -> MangaDiscoveryWork {
        guard identity.provider == .aniList, let mediaID = Int(identity.providerID) else {
            throw MangaDiscoveryError.invalidRequest
        }
        let payload = try await request(
            query: Self.detailQuery,
            variables: AniListVariables(
                page: nil,
                perPage: nil,
                search: nil,
                sort: nil,
                isAdult: nil,
                id: mediaID
            )
        )
        guard let media = payload.data?.media else {
            throw Self.graphQLError(payload.errors)
        }
        return media.work
    }

    private func loadPage(
        search: String?,
        page: Int,
        sort: [String],
        allowsAdult: Bool
    ) async throws -> MangaDiscoveryPage {
        let payload = try await request(
            query: Self.pageQuery,
            variables: AniListVariables(
                page: max(1, page),
                perPage: 20,
                search: search,
                sort: sort,
                isAdult: allowsAdult ? nil : false,
                id: nil
            )
        )
        guard let page = payload.data?.page else {
            throw Self.graphQLError(payload.errors)
        }
        return MangaDiscoveryPage(
            entries: page.media.map(\.work).filter { allowsAdult || !$0.isAdult },
            hasNextPage: page.pageInfo.hasNextPage
        )
    }

    private func request(
        query: String,
        variables: AniListVariables
    ) async throws -> AniListResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            AniListRequest(query: query, variables: variables)
        )
        let data = try await client.data(for: request)
        do {
            return try JSONDecoder().decode(AniListResponse.self, from: data)
        } catch {
            throw MangaDiscoveryError.invalidResponse
        }
    }

    private static func graphQLError(_ errors: [AniListGraphQLError]?) -> MangaDiscoveryError {
        let message = errors?.map(\.message).filter { !$0.isEmpty }.joined(separator: "\n")
        return .provider(message?.isEmpty == false ? message! : String(localized: "AniList returned an invalid response."))
    }

    private static let fields = """
        id
        idMal
        title { userPreferred romaji english native }
        synonyms
        coverImage { extraLarge large }
        bannerImage
        description(asHtml: false)
        status
        format
        averageScore
        chapters
        volumes
        genres
        tags { name rank isAdult }
        siteUrl
        isAdult
        staff(perPage: 8) { edges { role node { name { full } } } }
        """

    private static let pageQuery = """
        query ($page: Int!, $perPage: Int!, $search: String, $sort: [MediaSort!], $isAdult: Boolean) {
          Page(page: $page, perPage: $perPage) {
            pageInfo { hasNextPage }
            media(type: MANGA, format_in: [MANGA, ONE_SHOT], search: $search, sort: $sort, isAdult: $isAdult) {
              \(fields)
            }
          }
        }
        """

    private static let detailQuery = """
        query ($id: Int!) {
          Media(id: $id, type: MANGA) {
            \(fields)
          }
        }
        """
}

private nonisolated struct AniListRequest: Encodable {
    let query: String
    let variables: AniListVariables
}

private nonisolated struct AniListVariables: Encodable {
    let page: Int?
    let perPage: Int?
    let search: String?
    let sort: [String]?
    let isAdult: Bool?
    let id: Int?
}

private nonisolated struct AniListResponse: Decodable {
    let data: AniListData?
    let errors: [AniListGraphQLError]?
}

private nonisolated struct AniListGraphQLError: Decodable {
    let message: String
}

private nonisolated struct AniListData: Decodable {
    let page: AniListPage?
    let media: AniListMedia?

    private enum CodingKeys: String, CodingKey {
        case page = "Page"
        case media = "Media"
    }
}

private nonisolated struct AniListPage: Decodable {
    let pageInfo: AniListPageInfo
    let media: [AniListMedia]
}

private nonisolated struct AniListPageInfo: Decodable {
    let hasNextPage: Bool
}

private nonisolated struct AniListMedia: Decodable {
    struct Titles: Decodable {
        let userPreferred: String?
        let romaji: String?
        let english: String?
        let native: String?
    }

    struct Cover: Decodable {
        let extraLarge: String?
        let large: String?
    }

    struct Tag: Decodable {
        let name: String
        let rank: Int?
        let isAdult: Bool?
    }

    struct StaffConnection: Decodable {
        let edges: [StaffEdge]
    }

    struct StaffEdge: Decodable {
        struct Node: Decodable {
            struct Name: Decodable { let full: String? }
            let name: Name
        }

        let role: String?
        let node: Node
    }

    let id: Int
    let idMal: Int?
    let title: Titles
    let synonyms: [String]?
    let coverImage: Cover?
    let bannerImage: String?
    let description: String?
    let status: String?
    let format: String?
    let averageScore: Double?
    let chapters: Int?
    let volumes: Int?
    let genres: [String]?
    let tags: [Tag]?
    let siteUrl: String?
    let isAdult: Bool?
    let staff: StaffConnection?

    var work: MangaDiscoveryWork {
        let authors = staff?.edges.compactMap { edge -> String? in
            guard edge.role?.localizedCaseInsensitiveContains("story") == true
                    || edge.role?.localizedCaseInsensitiveContains("art") == true else {
                return nil
            }
            return edge.node.name.full
        } ?? []
        return MangaDiscoveryWork(
            identity: MangaDiscoveryIdentity(
                provider: .aniList,
                providerID: String(id),
                malID: idMal
            ),
            title: title.userPreferred ?? title.romaji ?? title.english ?? title.native ?? String(id),
            englishTitle: title.english,
            romajiTitle: title.romaji,
            nativeTitle: title.native,
            synonyms: synonyms ?? [],
            coverURL: Self.httpsURL(coverImage?.extraLarge ?? coverImage?.large),
            bannerURL: Self.httpsURL(bannerImage),
            summary: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: Array(Set(authors)).sorted(),
            status: status,
            format: format,
            score: averageScore,
            tags: (genres ?? []) + (tags ?? [])
                .filter { ($0.rank ?? 0) >= 60 && $0.isAdult != true }
                .map(\.name),
            chapterCount: chapters,
            volumeCount: volumes,
            siteURL: Self.httpsURL(siteUrl),
            isAdult: isAdult == true
        )
    }

    private static func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }
}

actor MangaDiscoveryRequestThrottle {
    private let clock = ContinuousClock()
    private var nextAllowed: ContinuousClock.Instant?
    private let spacing: Duration

    init(spacing: Duration = .milliseconds(350)) {
        self.spacing = spacing
    }

    func wait() async throws {
        if let nextAllowed, nextAllowed > clock.now {
            try await clock.sleep(until: nextAllowed)
        }
        nextAllowed = clock.now.advanced(by: spacing)
    }
}

nonisolated struct JikanMangaDiscoveryProvider: MangaDiscoveryProvider {
    let id = MangaDiscoveryProviderID.myAnimeList
    private let client: MangaDiscoveryHTTPClient
    private let throttle: MangaDiscoveryRequestThrottle
    private let baseURL = URL(string: "https://api.jikan.moe/v4")!

    init(
        session: URLSession = .shared,
        throttle: MangaDiscoveryRequestThrottle = MangaDiscoveryRequestThrottle()
    ) {
        client = MangaDiscoveryHTTPClient(session: session)
        self.throttle = throttle
    }

    func homeSections(allowsAdult: Bool) async throws -> [MangaDiscoverySection] {
        let descriptors: [(String, String, String?)] = [
            ("most-popular", "Most Popular", "bypopularity"),
            ("top-rated", "Top Rated", nil),
            ("publishing-now", "Publishing Now", "publishing"),
        ]
        var sections: [MangaDiscoverySection] = []
        for descriptor in descriptors {
            do {
                let page = try await loadTopPage(
                    page: 1,
                    filter: descriptor.2,
                    allowsAdult: allowsAdult
                )
                sections.append(MangaDiscoverySection(
                    id: descriptor.0,
                    title: descriptor.1,
                    entries: page.entries,
                    errorMessage: nil
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                sections.append(MangaDiscoverySection(
                    id: descriptor.0,
                    title: descriptor.1,
                    entries: [],
                    errorMessage: error.localizedDescription
                ))
            }
        }
        return sections
    }

    func search(query: String, page: Int, allowsAdult: Bool) async throws -> MangaDiscoveryPage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("manga"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "order_by", value: "members"),
            URLQueryItem(name: "sort", value: "desc"),
        ] + (allowsAdult ? [] : [URLQueryItem(name: "sfw", value: "true")])
        guard let url = components?.url else { throw MangaDiscoveryError.invalidRequest }
        let envelope: JikanEnvelope<[JikanManga]> = try await load(url)
        return MangaDiscoveryPage(
            entries: envelope.data
                .filter { $0.isVisualManga && (allowsAdult || !$0.isAdult) }
                .map(\.work),
            hasNextPage: envelope.pagination?.hasNextPage == true
        )
    }

    func details(identity: MangaDiscoveryIdentity) async throws -> MangaDiscoveryWork {
        guard identity.provider == .myAnimeList || identity.malID != nil,
              let id = identity.malID ?? Int(identity.providerID) else {
            throw MangaDiscoveryError.invalidRequest
        }
        let url = baseURL
            .appendingPathComponent("manga")
            .appendingPathComponent(String(id))
            .appendingPathComponent("full")
        let envelope: JikanEnvelope<JikanManga> = try await load(url)
        guard envelope.data.isVisualManga else { throw MangaDiscoveryError.invalidResponse }
        return envelope.data.work
    }

    private func loadTopPage(
        page: Int,
        filter: String?,
        allowsAdult: Bool
    ) async throws -> MangaDiscoveryPage {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("top")
                .appendingPathComponent("manga"),
            resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: "20"),
        ]
        if let filter { items.append(URLQueryItem(name: "filter", value: filter)) }
        if !allowsAdult { items.append(URLQueryItem(name: "sfw", value: "true")) }
        components?.queryItems = items
        guard let url = components?.url else { throw MangaDiscoveryError.invalidRequest }
        let envelope: JikanEnvelope<[JikanManga]> = try await load(url)
        return MangaDiscoveryPage(
            entries: envelope.data
                .filter { $0.isVisualManga && (allowsAdult || !$0.isAdult) }
                .map(\.work),
            hasNextPage: envelope.pagination?.hasNextPage == true
        )
    }

    private func load<Value: Decodable & Sendable>(_ url: URL) async throws -> JikanEnvelope<Value> {
        try await throttle.wait()
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await client.data(for: request)
        do {
            return try JSONDecoder().decode(JikanEnvelope<Value>.self, from: data)
        } catch {
            throw MangaDiscoveryError.invalidResponse
        }
    }
}

private nonisolated struct JikanEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
    let pagination: JikanPagination?
}

private nonisolated struct JikanPagination: Decodable, Sendable {
    let hasNextPage: Bool?

    private enum CodingKeys: String, CodingKey {
        case hasNextPage = "has_next_page"
    }
}

private nonisolated struct JikanManga: Decodable, Sendable {
    struct Images: Decodable, Sendable {
        struct ImageSet: Decodable, Sendable {
            let imageURL: String?
            let largeImageURL: String?

            private enum CodingKeys: String, CodingKey {
                case imageURL = "image_url"
                case largeImageURL = "large_image_url"
            }
        }

        let jpg: ImageSet?
        let webp: ImageSet?
    }

    struct NamedResource: Decodable, Sendable {
        let name: String?
    }

    struct TitleValue: Decodable, Sendable {
        let type: String?
        let title: String?
    }

    let malID: Int
    let url: String?
    let images: Images?
    let title: String
    let titleEnglish: String?
    let titleJapanese: String?
    let titleSynonyms: [String]?
    let titles: [TitleValue]?
    let type: String?
    let chapters: Int?
    let volumes: Int?
    let status: String?
    let score: Double?
    let synopsis: String?
    let background: String?
    let authors: [NamedResource]?
    let genres: [NamedResource]?
    let explicitGenres: [NamedResource]?
    let themes: [NamedResource]?
    let demographics: [NamedResource]?

    private enum CodingKeys: String, CodingKey {
        case malID = "mal_id"
        case url, images, title, titles, type, chapters, volumes, status, score, synopsis, background, authors, genres, themes, demographics
        case titleEnglish = "title_english"
        case titleJapanese = "title_japanese"
        case titleSynonyms = "title_synonyms"
        case explicitGenres = "explicit_genres"
    }

    var isVisualManga: Bool {
        let value = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["manga", "one-shot", "oneshot", "manhwa", "manhua", "doujinshi"].contains(value)
    }

    var isAdult: Bool {
        explicitGenres?.isEmpty == false
            || [genres, themes, demographics]
                .compactMap { $0 }
                .flatMap { $0 }
                .compactMap(\.name)
                .contains { $0.localizedCaseInsensitiveContains("hentai") }
    }

    var work: MangaDiscoveryWork {
        let alternateTitles = (titles ?? []).compactMap(\.title)
            + (titleSynonyms ?? [])
        let allTags = [genres, themes, demographics]
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.name)
        let imageValue = images?.jpg?.largeImageURL
            ?? images?.webp?.largeImageURL
            ?? images?.jpg?.imageURL
            ?? images?.webp?.imageURL
        return MangaDiscoveryWork(
            identity: MangaDiscoveryIdentity(
                provider: .myAnimeList,
                providerID: String(malID),
                malID: malID
            ),
            title: titleEnglish ?? title,
            englishTitle: titleEnglish,
            romajiTitle: title,
            nativeTitle: titleJapanese,
            synonyms: alternateTitles,
            coverURL: Self.httpsURL(imageValue),
            bannerURL: nil,
            summary: [synopsis, background]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                .nilIfEmpty,
            authors: authors?.compactMap(\.name) ?? [],
            status: status,
            format: type,
            score: score.map { $0 * 10 },
            tags: Array(Set(allTags)).sorted(),
            chapterCount: chapters,
            volumeCount: volumes,
            siteURL: Self.httpsURL(url),
            isAdult: isAdult
        )
    }

    private static func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

nonisolated struct MangaDiscoveryMatchCandidate: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
}

nonisolated struct MangaDiscoveryTitleMatch: Sendable, Equatable {
    let candidateID: String
    let score: Double
}

nonisolated enum MangaDiscoveryTitleMatcher {
    static func ranked(
        titles: [String],
        candidates: [MangaDiscoveryMatchCandidate]
    ) -> [MangaDiscoveryTitleMatch] {
        let normalizedTitles = titles.map(normalized).filter { !$0.compact.isEmpty }
        return candidates.map { candidate in
            let candidateValue = normalized(candidate.title)
            let matchScore = normalizedTitles.map { similarity($0, candidateValue) }.max() ?? 0
            return MangaDiscoveryTitleMatch(candidateID: candidate.id, score: matchScore)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.candidateID.localizedStandardCompare($1.candidateID) == .orderedAscending
        }
    }

    static func automaticMatch(
        titles: [String],
        candidates: [MangaDiscoveryMatchCandidate]
    ) -> String? {
        let ranked = ranked(titles: titles, candidates: candidates)
        guard let first = ranked.first else { return nil }
        if first.score == 1 {
            return ranked.dropFirst().first?.score == 1 ? nil : first.candidateID
        }
        guard let candidate = candidates.first(where: { $0.id == first.candidateID }) else {
            return nil
        }
        let candidateValue = normalized(candidate.title)
        let bestTitle = titles
            .map(normalized)
            .filter { !$0.compact.isEmpty }
            .max { similarity($0, candidateValue) < similarity($1, candidateValue) }
        guard let bestTitle,
              bestTitle.compact.count >= 4,
              candidateValue.compact.count >= 4,
              first.score >= 0.90,
              first.score - (ranked.dropFirst().first?.score ?? 0) >= 0.10 else {
            return nil
        }
        return first.candidateID
    }

    private struct NormalizedValue {
        let words: [String]
        let compact: String
    }

    private static func normalized(_ value: String) -> NormalizedValue {
        let folded = value
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let words = String(folded.map { character in
            character.isLetter || character.isNumber ? character : " "
        })
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
        return NormalizedValue(words: words, compact: words.joined())
    }

    private static func similarity(_ lhs: NormalizedValue, _ rhs: NormalizedValue) -> Double {
        guard !lhs.compact.isEmpty, !rhs.compact.isEmpty else { return 0 }
        if lhs.compact == rhs.compact { return 1 }
        let tokenScore = dice(Set(lhs.words), Set(rhs.words))
        let characterScore = dice(bigrams(lhs.compact), bigrams(rhs.compact))
        return max(tokenScore, characterScore)
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count > 1 else { return Set([value]) }
        return Set((0..<(characters.count - 1)).map {
            String(characters[$0...($0 + 1)])
        })
    }

    private static func dice<Value: Hashable>(_ lhs: Set<Value>, _ rhs: Set<Value>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(2 * lhs.intersection(rhs).count) / Double(lhs.count + rhs.count)
    }
}

private nonisolated extension Array {
    func appending(contentsOf values: [Element]) -> [Element] {
        self + values
    }
}
