import Foundation

public enum AidokuSourceListParser {
    private struct LegacyEntry: Decodable {
        let id: String
        let name: String?
        let version: Int
        let icon: String?
        let file: String?
        let lang: String?
        let nsfw: Int?
        let languages: [String]?
        let contentRating: AidokuSourceContentRating?
    }

    private struct CurrentDocument: Decodable {
        let name: String?
        let feedbackURL: String?
        let sources: [AidokuSourceList.Entry]
    }

    private struct DocumentShape: Decodable {
        let apps: [App]?

        struct App: Decodable {
            let bundleIdentifier: String?
            let versions: [Version]?

            struct Version: Decodable {
                let downloadURL: String?
            }
        }
    }

    public static func parse(data: Data, baseURL: URL) throws -> AidokuSourceList {
        guard data.count <= AidokuLimits.maximumJSONBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(CurrentDocument.self, from: data) {
            let sources = try current.sources.map { try resolving($0, against: baseURL) }
            return AidokuSourceList(
                name: current.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? baseURL.host
                    ?? "Aidoku Sources",
                feedbackURL: resolve(current.feedbackURL, against: baseURL),
                sources: sources
            )
        }
        if let shape = try? decoder.decode(DocumentShape.self, from: data),
           let apps = shape.apps,
           !apps.isEmpty,
           apps.contains(where: { app in
               app.bundleIdentifier != nil
                   || app.versions?.contains(where: { $0.downloadURL != nil }) == true
           }) {
            throw AidokuRuntimeError.altStoreAppCatalog
        }
        let legacy: [LegacyEntry]
        if let array = try? decoder.decode([LegacyEntry].self, from: data) {
            legacy = array
        } else if let dictionary = try? decoder.decode([String: LegacyEntry].self, from: data) {
            legacy = dictionary.sorted(by: { $0.key < $1.key }).map(\.value)
        } else {
            throw AidokuRuntimeError.invalidManifest
        }
        let sources = try legacy.map { entry in
            let rating = entry.contentRating
                ?? AidokuSourceContentRating(rawValue: entry.nsfw ?? 0)
                ?? .safe
            return try resolving(
                AidokuSourceList.Entry(
                    id: entry.id,
                    name: entry.name ?? entry.id,
                    version: entry.version,
                    iconURL: entry.icon,
                    downloadURL: entry.file,
                    languages: entry.languages ?? entry.lang.map { [$0] },
                    contentRating: rating
                ),
                against: baseURL
            )
        }
        return AidokuSourceList(name: baseURL.host ?? "Aidoku Sources", sources: sources)
    }

    public static func validateRemoteURL(_ url: URL, insecureTransportConfirmed: Bool) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw AidokuRuntimeError.unsupportedURL
        }
        if scheme == "http" || isLocalNetworkHost(url.host) {
            guard insecureTransportConfirmed else {
                throw AidokuRuntimeError.insecureTransportRequiresConfirmation
            }
        }
    }

    public static func isLocalNetworkHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10
            || parts[0] == 127
            || (parts[0] == 169 && parts[1] == 254)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }

    private static func resolving(
        _ entry: AidokuSourceList.Entry,
        against baseURL: URL
    ) throws -> AidokuSourceList.Entry {
        guard AidokuPackageValidator.isSafeSourceID(entry.id), entry.version >= 0 else {
            throw AidokuRuntimeError.invalidSourceID
        }
        return AidokuSourceList.Entry(
            id: entry.id,
            name: entry.name,
            version: entry.version,
            iconURL: resolve(entry.iconURL, against: baseURL),
            downloadURL: resolve(entry.downloadURL, against: baseURL),
            languages: entry.languages,
            contentRating: entry.contentRating,
            altNames: entry.altNames,
            baseURL: resolve(entry.baseURL, against: baseURL),
            minAppVersion: entry.minAppVersion,
            maxAppVersion: entry.maxAppVersion
        )
    }

    private static func resolve(_ value: String?, against baseURL: URL) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
