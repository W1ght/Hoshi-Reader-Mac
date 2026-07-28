import Foundation

nonisolated private struct SuwayomiLoginPayload: Decodable {
    struct Login: Decodable {
        let accessToken: String
        let refreshToken: String
    }

    let login: Login
}

actor SuwayomiClient {
    nonisolated let configuration: SuwayomiServerConfiguration
    nonisolated let baseURL: URL
    nonisolated let serverID: String

    private let credentials: SuwayomiCredentials?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var accessToken: String?

    init(
        configuration: SuwayomiServerConfiguration,
        credentials: SuwayomiCredentials?,
        session: URLSession = .shared
    ) throws {
        let baseURL = try Self.normalizedServerURL(
            configuration.serverURL
        )
        self.configuration = configuration
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
        serverID = SuwayomiIdentity.serverID(baseURL)
    }

    func connect() async throws -> [SuwayomiSource] {
        try await sources()
    }

    func sources() async throws -> [SuwayomiSource] {
        let sources: [SuwayomiSource] = try await getJSON(
            path: "source/list"
        )
        return sources.sorted {
            if $0.lang != $1.lang { return $0.lang < $1.lang }
            return $0.displayName.localizedStandardCompare(
                $1.displayName
            ) == .orderedAscending
        }
    }

    func popular(
        sourceID: String,
        page: Int
    ) async throws -> SuwayomiPagedManga {
        try await getJSON(
            path: "source/\(sourceID)/popular/\(max(1, page))"
        )
    }

    func latest(
        sourceID: String,
        page: Int
    ) async throws -> SuwayomiPagedManga {
        try await getJSON(
            path: "source/\(sourceID)/latest/\(max(1, page))"
        )
    }

    func search(
        sourceID: String,
        query: String,
        page: Int
    ) async throws -> SuwayomiPagedManga {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "searchTerm", value: query),
            URLQueryItem(name: "pageNum", value: String(max(1, page))),
        ]
        return try await getJSON(
            path: "source/\(sourceID)/search",
            query: components.percentEncodedQuery
        )
    }

    func manga(
        id: Int,
        onlineFetch: Bool = false
    ) async throws -> SuwayomiManga {
        try await getJSON(
            path: "manga/\(id)/full",
            query: onlineFetch ? "onlineFetch=true" : nil
        )
    }

    func chapters(
        mangaID: Int,
        onlineFetch: Bool = false
    ) async throws -> [SuwayomiChapter] {
        let chapters: [SuwayomiChapter] = try await getJSON(
            path: "manga/\(mangaID)/chapters",
            query: onlineFetch ? "onlineFetch=true" : nil
        )
        return chapters.sorted {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.id < $1.id
        }
    }

    func prepareChapter(
        mangaID: Int,
        sourceOrder: Int
    ) async throws -> SuwayomiChapter {
        try await getJSON(
            path: "manga/\(mangaID)/chapter/\(sourceOrder)"
        )
    }

    func library() async throws -> [SuwayomiManga] {
        let categories: [SuwayomiCategory] = try await getJSON(
            path: "category"
        )
        var mangaByID: [Int: SuwayomiManga] = [:]
        for category in categories {
            let items: [SuwayomiManga] = try await getJSON(
                path: "category/\(category.id)"
            )
            for manga in items {
                mangaByID[manga.id] = manga
            }
        }
        return mangaByID.values.sorted {
            $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
    }

    func setLibrary(
        mangaID: Int,
        isInLibrary: Bool
    ) async throws {
        var request = try await request(
            path: "manga/\(mangaID)/library",
            method: isInLibrary ? "GET" : "DELETE"
        )
        request.httpBody = nil
        _ = try await perform(request, maximumBytes: 1_024)
    }

    func updateProgress(
        chapter: SuwayomiChapter,
        pageIndex: Int,
        completed: Bool
    ) async throws {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(
                name: "lastPageRead",
                value: String(max(0, pageIndex))
            ),
        ]
        if completed {
            components.queryItems?.append(URLQueryItem(
                name: "read",
                value: "true"
            ))
        }
        var request = try await request(
            path:
                "manga/\(chapter.mangaId)/chapter/\(chapter.index)",
            method: "PATCH"
        )
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = components.percentEncodedQuery?.data(
            using: .utf8
        )
        _ = try await perform(request, maximumBytes: 1_024)
    }

    func thumbnailData(mangaID: Int) async throws -> Data {
        let request = try await request(
            path: "manga/\(mangaID)/thumbnail",
            method: "GET"
        )
        return try await perform(
            request,
            maximumBytes: SuwayomiConstants.maximumImageBytes
        ).data
    }

    func pageData(
        mangaID: Int,
        sourceOrder: Int,
        pageIndex: Int
    ) async throws -> Data {
        var request = try await request(
            path:
                "manga/\(mangaID)/chapter/\(sourceOrder)/page/\(pageIndex)",
            method: "GET"
        )
        request.timeoutInterval = 120
        return try await perform(
            request,
            maximumBytes: SuwayomiConstants.maximumImageBytes
        ).data
    }

    nonisolated func pageURL(
        mangaID: Int,
        sourceOrder: Int,
        pageIndex: Int
    ) -> URL {
        apiURL(
            path:
                "manga/\(mangaID)/chapter/\(sourceOrder)/page/\(pageIndex)"
        )
    }

    private func getJSON<Value: Decodable>(
        path: String,
        query: String? = nil
    ) async throws -> Value {
        let request = try await request(
            path: path,
            method: "GET",
            query: query
        )
        let response = try await perform(
            request,
            maximumBytes: SuwayomiConstants.maximumJSONBytes
        )
        do {
            return try decoder.decode(Value.self, from: response.data)
        } catch {
            throw SuwayomiConnectorError.unexpectedResponse
        }
    }

    private func request(
        path: String,
        method: String,
        query: String? = nil,
        forceLogin: Bool = false
    ) async throws -> URLRequest {
        if configuration.authMode == .uiLogin,
           accessToken == nil || forceLogin {
            try await login()
        }
        var url = apiURL(path: path)
        if let query, !query.isEmpty,
           var components = URLComponents(
               url: url,
               resolvingAgainstBaseURL: false
           ) {
            components.percentEncodedQuery = query
            if let resolved = components.url {
                url = resolved
            }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        switch configuration.authMode {
        case .none:
            break
        case .basic:
            guard let credentials,
                  !configuration.username.isEmpty,
                  !credentials.secret.isEmpty else {
                throw SuwayomiConnectorError.missingCredentials
            }
            let value = Data(
                "\(configuration.username):\(credentials.secret)".utf8
            ).base64EncodedString()
            request.setValue(
                "Basic \(value)",
                forHTTPHeaderField: "Authorization"
            )
        case .uiLogin:
            guard let accessToken else {
                throw SuwayomiConnectorError.authenticationFailed
            }
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        case .bearer:
            guard let credentials, !credentials.secret.isEmpty else {
                throw SuwayomiConnectorError.missingCredentials
            }
            request.setValue(
                "Bearer \(credentials.secret)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    private func login() async throws {
        guard let credentials,
              !configuration.username.isEmpty,
              !credentials.secret.isEmpty else {
            throw SuwayomiConnectorError.missingCredentials
        }
        let body: [String: Any] = [
            "query":
                "mutation Login($username: String!, $password: String!) " +
                "{ login(input: { username: $username, password: $password }) " +
                "{ accessToken refreshToken } }",
            "variables": [
                "username": configuration.username,
                "password": credentials.secret,
            ],
        ]
        var request = URLRequest(
            url: baseURL.appendingPathComponent("api/graphql")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )
        let response = try await perform(
            request,
            maximumBytes: SuwayomiConstants.maximumJSONBytes,
            retriesAuthentication: false
        )
        let payload: SuwayomiGraphQLResponse<SuwayomiLoginPayload>
        do {
            payload = try decoder.decode(
                SuwayomiGraphQLResponse<SuwayomiLoginPayload>.self,
                from: response.data
            )
        } catch {
            throw SuwayomiConnectorError.authenticationFailed
        }
        guard payload.errors?.isEmpty != false,
              let token = payload.data?.login.accessToken,
              !token.isEmpty else {
            throw SuwayomiConnectorError.authenticationFailed
        }
        accessToken = token
    }

    private struct HTTPResult {
        let data: Data
        let statusCode: Int
    }

    private func perform(
        _ request: URLRequest,
        maximumBytes: Int,
        retriesAuthentication: Bool = true
    ) async throws -> HTTPResult {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SuwayomiConnectorError.unexpectedResponse
            }
            guard data.count <= maximumBytes else {
                throw SuwayomiConnectorError.responseTooLarge
            }
            if http.statusCode == 401 {
                if configuration.authMode == .uiLogin,
                   retriesAuthentication {
                    accessToken = nil
                    let rawPath = request.url?.path ?? ""
                    let marker = "/api/v1/"
                    let retryPath: String
                    if let range = rawPath.range(of: marker) {
                        retryPath = String(rawPath[range.upperBound...])
                    } else {
                        retryPath = rawPath.trimmingCharacters(
                            in: CharacterSet(charactersIn: "/")
                        )
                    }
                    var retried = try await self.request(
                        path: retryPath,
                        method: request.httpMethod ?? "GET",
                        query: request.url?.query,
                        forceLogin: true
                    )
                    retried.timeoutInterval = request.timeoutInterval
                    retried.httpBody = request.httpBody
                    if let contentType = request.value(
                        forHTTPHeaderField: "Content-Type"
                    ) {
                        retried.setValue(
                            contentType,
                            forHTTPHeaderField: "Content-Type"
                        )
                    }
                    return try await perform(
                        retried,
                        maximumBytes: maximumBytes,
                        retriesAuthentication: false
                    )
                }
                throw SuwayomiConnectorError.authenticationFailed
            }
            guard (200..<300).contains(http.statusCode) else {
                throw SuwayomiConnectorError.serverError(
                    http.statusCode
                )
            }
            return HTTPResult(
                data: data,
                statusCode: http.statusCode
            )
        } catch let error as SuwayomiConnectorError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SuwayomiConnectorError.serverUnavailable
        }
    }

    nonisolated private func apiURL(path: String) -> URL {
        baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(path)
    }

    nonisolated static func normalizedServerURL(
        _ value: String
    ) throws -> URL {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            throw SuwayomiConnectorError.invalidServerURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw SuwayomiConnectorError.unsupportedServerScheme
        }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        for suffix in ["/api/v1", "/api/graphql"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        components.path = path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        if !components.path.isEmpty {
            components.path = "/" + components.path
        }
        guard let url = components.url else {
            throw SuwayomiConnectorError.invalidServerURL
        }
        return url
    }

    nonisolated static func credentialIdentity(
        for configuration: SuwayomiServerConfiguration
    ) throws -> String {
        let serverURL = try normalizedServerURL(
            configuration.serverURL
        )
        let username: String
        switch configuration.authMode {
        case .basic, .uiLogin:
            username = configuration.username.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        case .none, .bearer:
            username = ""
        }
        return SuwayomiIdentity.sha256(
            [
                serverURL.absoluteString,
                configuration.authMode.rawValue,
                username,
            ].joined(separator: "\u{1f}")
        )
    }
}
