//
//  TokenStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Security
import OSLog

class TokenStorage {
    private static let service = "de.manhhao.hoshi.google-drive"
    private static let fallbackPrefix = "TokenStorage.GoogleDrive."
    private static let logger = Logger(subsystem: "de.manhhao.hoshi", category: "Sync")

    @discardableResult
    static func save(_ token: String, for key: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            logger.debug("Saved sync token '\(key, privacy: .public)' in Keychain")
            return true
        }

        logger.warning("Keychain save failed for sync token '\(key, privacy: .public)' with status \(status, privacy: .public); using Mac fallback storage")
        UserDefaults.standard.set(token, forKey: fallbackKey(key))
        return true
    }
    
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        if status != errSecItemNotFound {
            logger.warning("Keychain read failed for sync token '\(key, privacy: .public)' with status \(status, privacy: .public); checking fallback storage")
        }
        if let legacy = getLegacyKeychainValue(key) {
            save(legacy, for: key)
            deleteLegacyKeychainValue(key)
            return legacy
        }
        return UserDefaults.standard.string(forKey: fallbackKey(key))
    }
    
    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        deleteLegacyKeychainValue(key)
        UserDefaults.standard.removeObject(forKey: fallbackKey(key))
    }
    
    static func clear() {
        delete("accessToken")
        delete("refreshToken")
        delete("clientId")
        Task { @MainActor in
            GoogleDriveHandler.clearCache()
        }
    }
    
    private static func fallbackKey(_ key: String) -> String {
        fallbackPrefix + key
    }

    private static func getLegacyKeychainValue(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacyKeychainValue(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
