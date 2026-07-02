//
//  TokenStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Security

struct GoogleDriveCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let clientId: String
}

class TokenStorage {
    private static let credentialsAccount = "googleDriveCredentials"
    private static let credentialsPresenceKey = "GoogleDriveCredentialsStored"
    private static let githubTokenAccount = "githubReleaseToken"
    private static let githubTokenPresenceKey = "GitHubReleaseTokenStored"
    private static let legacyCredentialAccounts = ["accessToken", "refreshToken", "clientId"]

    static var hasStoredCredentials: Bool {
        if let storedValue = UserDefaults.standard.object(forKey: credentialsPresenceKey) as? Bool {
            return storedValue
        }

        let hasCredentials = accountExists(credentialsAccount) || legacyCredentialAccounts.allSatisfy(accountExists)
        UserDefaults.standard.set(hasCredentials, forKey: credentialsPresenceKey)
        return hasCredentials
    }

    @discardableResult
    static func saveCredentials(_ credentials: GoogleDriveCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: credentialsAccount
        ]
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: credentialsAccount,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            UserDefaults.standard.set(true, forKey: credentialsPresenceKey)
            return true
        }
        UserDefaults.standard.removeObject(forKey: credentialsPresenceKey)
        return false
    }

    static func getCredentials() -> GoogleDriveCredentials? {
        if let credentials = getStoredCredentials() {
            UserDefaults.standard.set(true, forKey: credentialsPresenceKey)
            return credentials
        }

        guard let credentials = getLegacyCredentials() else {
            UserDefaults.standard.set(false, forKey: credentialsPresenceKey)
            return nil
        }

        _ = saveCredentials(credentials)
        return credentials
    }

    static func clear() {
        deleteAccount(credentialsAccount)
        legacyCredentialAccounts.forEach(deleteAccount)
        UserDefaults.standard.removeObject(forKey: credentialsPresenceKey)
        Task { @MainActor in
            GoogleDriveHandler.clearCache()
        }
    }

    static var hasStoredGitHubToken: Bool {
        if let storedValue = UserDefaults.standard.object(forKey: githubTokenPresenceKey) as? Bool {
            return storedValue
        }

        let hasToken = accountExists(githubTokenAccount)
        UserDefaults.standard.set(hasToken, forKey: githubTokenPresenceKey)
        return hasToken
    }

    @discardableResult
    static func saveGitHubToken(_ token: String) -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            clearGitHubToken()
            return true
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: githubTokenAccount
        ]
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: githubTokenAccount,
            kSecValueData as String: Data(trimmedToken.utf8)
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            UserDefaults.standard.set(true, forKey: githubTokenPresenceKey)
            return true
        }
        UserDefaults.standard.removeObject(forKey: githubTokenPresenceKey)
        return false
    }

    static func getGitHubToken() -> String? {
        guard let token = getString(for: githubTokenAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            UserDefaults.standard.set(false, forKey: githubTokenPresenceKey)
            return nil
        }
        UserDefaults.standard.set(true, forKey: githubTokenPresenceKey)
        return token
    }

    static func clearGitHubToken() {
        deleteAccount(githubTokenAccount)
        UserDefaults.standard.removeObject(forKey: githubTokenPresenceKey)
    }

    private static func getStoredCredentials() -> GoogleDriveCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: credentialsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleDriveCredentials.self, from: data)
    }

    private static func getLegacyCredentials() -> GoogleDriveCredentials? {
        guard
            let accessToken = getString(for: "accessToken"),
            let refreshToken = getString(for: "refreshToken"),
            let clientId = getString(for: "clientId")
        else {
            return nil
        }

        return GoogleDriveCredentials(accessToken: accessToken, refreshToken: refreshToken, clientId: clientId)
    }

    private static func getString(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func accountExists(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    private static func deleteAccount(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
