//
//  TokenStorage.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CryptoKit

class TokenStorage {
    private static let tokenFileName = "google_drive_tokens.json"
    private static let storageRootOverrideEnvironmentKey = "HOSHI_TOKEN_STORAGE_ROOT"

    private struct TokenFile: Codable {
        var version: Int
        var encryptionKey: String
        var tokens: [String: String]
    }

    static func save(_ token: String, for key: String) {
        guard let data = token.data(using: .utf8) else { return }
        do {
            var file = try loadTokenFile() ?? newTokenFile()
            guard let encrypted = try encrypt(data, with: file.encryptionKey) else { return }
            file.tokens[key] = encrypted
            try writeTokenFile(file)
        } catch {
            return
        }
    }
    
    static func get(_ key: String) -> String? {
        do {
            guard
                let file = try loadTokenFile(),
                let encrypted = file.tokens[key],
                let data = try decrypt(encrypted, with: file.encryptionKey)
            else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    static func delete(_ key: String) {
        do {
            guard var file = try loadTokenFile(), file.tokens[key] != nil else { return }
            file.tokens.removeValue(forKey: key)
            try? writeTokenFile(file)
        } catch {
            return
        }
    }
    
    static func clear() {
        try? FileManager.default.removeItem(at: tokenFileURL())
        Task { @MainActor in
            GoogleDriveHandler.clearCache()
        }
    }

    private static func loadTokenFile() throws -> TokenFile? {
        let url = try tokenFileURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TokenFile.self, from: data)
    }

    private static func writeTokenFile(_ file: TokenFile) throws {
        let url = try tokenFileURL()
        if file.tokens.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private static func newTokenFile() -> TokenFile {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        return TokenFile(
            version: 1,
            encryptionKey: keyData.base64EncodedString(),
            tokens: [:]
        )
    }

    private static func encrypt(_ data: Data, with encodedKey: String) throws -> String? {
        guard let keyData = Data(base64Encoded: encodedKey) else { return nil }
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined?.base64EncodedString()
    }

    private static func decrypt(_ encodedValue: String, with encodedKey: String?) throws -> Data? {
        guard
            let encodedKey,
            let keyData = Data(base64Encoded: encodedKey),
            let combined = Data(base64Encoded: encodedValue)
        else {
            return nil
        }
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func tokenFileURL() throws -> URL {
        let root = try storageRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(tokenFileName)
    }

    private static func storageRoot() throws -> URL {
        if let override = getenv(storageRootOverrideEnvironmentKey) {
            return URL(fileURLWithPath: String(cString: override), isDirectory: true)
        }
        return try BookStorage.getAppDirectory()
    }
}
