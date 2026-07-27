import Foundation
import Security

actor SuwayomiConnectionStore {
    static let shared = SuwayomiConnectionStore()

    private let configurationFileName = "suwayomi.json"
    private let keychainService = "moe.shishamo.hoshi.suwayomi"

    func configuration(
        profileID: String
    ) async -> SuwayomiServerConfiguration {
        guard let url = try? await configurationURL(
                  profileID: profileID
              ),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(
                  SuwayomiServerConfiguration.self,
                  from: data
              ) else {
            return .defaultValue
        }
        return configuration
    }

    func credentials(profileID: String) -> SuwayomiCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess,
        let data = result as? Data,
        let secret = String(data: data, encoding: .utf8) else {
            return nil
        }
        return SuwayomiCredentials(secret: secret)
    }

    func save(
        profileID: String,
        configuration: SuwayomiServerConfiguration,
        secret: String?
    ) async throws {
        _ = try SuwayomiClient.normalizedServerURL(
            configuration.serverURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let url = try await configurationURL(profileID: profileID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)

        if let secret, !secret.isEmpty {
            try saveSecret(secret, profileID: profileID)
        } else if configuration.authMode == .none {
            deleteSecret(profileID: profileID)
        }
    }

    func clear(profileID: String) async throws {
        if let url = try? await configurationURL(profileID: profileID) {
            try? FileManager.default.removeItem(at: url)
        }
        deleteSecret(profileID: profileID)
    }

    private func configurationURL(profileID: String) async throws -> URL {
        let fileName = configurationFileName
        return try await MainActor.run {
            try ProfileRepository.shared
                .profileDirectory(for: profileID)
                .appendingPathComponent(fileName)
        }
    }

    private func saveSecret(
        _ secret: String,
        profileID: String
    ) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
        ]
        let status = SecItemUpdate(
            lookup as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = Data(secret.utf8)
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw SuwayomiConnectorError.unexpectedResponse
            }
        } else if status != errSecSuccess {
            throw SuwayomiConnectorError.unexpectedResponse
        }
    }

    private func deleteSecret(profileID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
