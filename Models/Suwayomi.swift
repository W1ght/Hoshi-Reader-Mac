import CryptoKit
import Foundation

nonisolated enum SuwayomiConstants {
    static let defaultServerURL = "http://127.0.0.1:4567"
    static let maximumJSONBytes = 16 * 1_024 * 1_024
    static let maximumImageBytes = 256 * 1_024 * 1_024
}

nonisolated enum SuwayomiAuthMode: String, Codable, CaseIterable, Sendable {
    case none
    case basic
    case uiLogin
    case bearer
}

nonisolated struct SuwayomiServerConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var serverURL: String
    var authMode: SuwayomiAuthMode
    var username: String
    var credentialID: String? = nil

    static let defaultValue = SuwayomiServerConfiguration(
        serverURL: SuwayomiConstants.defaultServerURL,
        authMode: .none,
        username: ""
    )
}

nonisolated struct SuwayomiCredentials: Equatable, Sendable {
    let secret: String
}

nonisolated enum SuwayomiIdentity {
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func serverID(_ baseURL: URL) -> String {
        sha256(baseURL.absoluteString)
    }

    static func mangaID(serverID: String, remoteID: Int) -> String {
        sha256("\(serverID)\u{1f}\(remoteID)")
    }

    static func chapterID(serverID: String, remoteID: Int) -> String {
        sha256("\(serverID)\u{1f}\(remoteID)")
    }
}

nonisolated struct SuwayomiSource:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let lang: String
    let iconUrl: String
    let supportsLatest: Bool
    let isConfigurable: Bool
    let isNsfw: Bool
    let displayName: String
    let baseUrl: String?
}

nonisolated struct SuwayomiManga:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: Int
    let sourceId: String
    let url: String
    var title: String
    var thumbnailUrl: String?
    var thumbnailUrlLastFetched: Int64?
    var initialized: Bool
    var artist: String?
    var author: String?
    var mangaDescription: String?
    var genre: [String]
    var status: String
    var inLibrary: Bool
    var inLibraryAt: Int64?
    var realUrl: String?
    var lastReadAt: Int64?
    var chapterCount: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceId
        case url
        case title
        case thumbnailUrl
        case thumbnailUrlLastFetched
        case initialized
        case artist
        case author
        case mangaDescription = "description"
        case genre
        case status
        case inLibrary
        case inLibraryAt
        case realUrl
        case lastReadAt
        case chapterCount
    }
}

nonisolated struct SuwayomiPagedManga:
    Codable,
    Equatable,
    Sendable
{
    let mangaList: [SuwayomiManga]
    let hasNextPage: Bool
}

nonisolated struct SuwayomiChapter:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: Int
    let url: String
    let name: String
    let uploadDate: Int64
    let chapterNumber: Double
    let scanlator: String?
    let mangaId: Int
    var read: Bool
    var bookmarked: Bool
    var lastPageRead: Int
    var lastReadAt: Int64
    let index: Int
    let fetchedAt: Int64
    let realUrl: String?
    let downloaded: Bool
    var pageCount: Int
}

nonisolated struct SuwayomiCategory:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let isDefault: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault = "default"
    }
}

nonisolated struct SuwayomiGraphQLResponse<Payload: Decodable>:
    Decodable
{
    struct GraphQLError: Decodable {
        let message: String
    }

    let data: Payload?
    let errors: [GraphQLError]?
}

nonisolated enum SuwayomiConnectorError:
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidServerURL
    case unsupportedServerScheme
    case missingCredentials
    case authenticationFailed
    case serverUnavailable
    case unexpectedResponse
    case serverError(Int)
    case responseTooLarge
    case sourceUnavailable
    case mangaUnavailable
    case chapterUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "The Suwayomi Server address is invalid.")
        case .unsupportedServerScheme:
            String(localized: "Suwayomi Server must use HTTP or HTTPS.")
        case .missingCredentials:
            String(localized: "Suwayomi credentials are required.")
        case .authenticationFailed:
            String(localized: "Suwayomi authentication failed.")
        case .serverUnavailable:
            String(localized: "Suwayomi Server is unavailable.")
        case .unexpectedResponse:
            String(localized: "Suwayomi Server returned an unexpected response.")
        case .serverError(let status):
            String(
                localized:
                    "Suwayomi Server returned HTTP \(status)."
            )
        case .responseTooLarge:
            String(localized: "The Suwayomi response is too large.")
        case .sourceUnavailable:
            String(localized: "The Suwayomi source is unavailable.")
        case .mangaUnavailable:
            String(localized: "The Suwayomi manga is unavailable.")
        case .chapterUnavailable:
            String(localized: "The Suwayomi chapter is unavailable.")
        }
    }
}
