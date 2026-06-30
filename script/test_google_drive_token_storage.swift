import Foundation

enum BookStorage {
    static func getAppDirectory() throws -> URL {
        guard let root = getenv("HOSHI_TOKEN_STORAGE_ROOT") else {
            throw NSError(domain: "TokenStorageTest", code: 1)
        }
        return URL(fileURLWithPath: String(cString: root), isDirectory: true)
    }
}

@MainActor
enum GoogleDriveHandler {
    static func clearCache() {}
}

@main
struct GoogleDriveTokenStorageTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-token-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        setenv("HOSHI_TOKEN_STORAGE_ROOT", root.path, 1)

        TokenStorage.clear()
        expect(TokenStorage.get("accessToken") == nil, "empty store should not return an access token")

        TokenStorage.save("access-secret", for: "accessToken")
        TokenStorage.save("refresh-secret", for: "refreshToken")
        TokenStorage.save("client-id-value", for: "clientId")

        expect(TokenStorage.get("accessToken") == "access-secret", "access token should round-trip")
        expect(TokenStorage.get("refreshToken") == "refresh-secret", "refresh token should round-trip")
        expect(TokenStorage.get("clientId") == "client-id-value", "client id should round-trip")

        let storeURL = root.appendingPathComponent("google_drive_tokens.json")
        expect(FileManager.default.fileExists(atPath: storeURL.path), "token JSON should be created")

        let json = try String(contentsOf: storeURL, encoding: .utf8)
        expect(json.contains("encryptionKey"), "token JSON should include the local encryption key")
        expect(json.contains("access-secret") == false, "token JSON should not contain plaintext access token")
        expect(json.contains("refresh-secret") == false, "token JSON should not contain plaintext refresh token")
        expect(json.contains("client-id-value") == false, "token JSON should not contain plaintext client id")

        TokenStorage.save("access-secret-2", for: "accessToken")
        expect(TokenStorage.get("accessToken") == "access-secret-2", "saving an existing token should replace it")
        expect(TokenStorage.get("refreshToken") == "refresh-secret", "saving access token should preserve refresh token")

        TokenStorage.delete("refreshToken")
        expect(TokenStorage.get("refreshToken") == nil, "delete should remove one token")
        expect(TokenStorage.get("accessToken") == "access-secret-2", "delete should preserve other tokens")

        TokenStorage.clear()
        expect(TokenStorage.get("accessToken") == nil, "clear should remove access token")
        expect(TokenStorage.get("clientId") == nil, "clear should remove client id")
        expect(FileManager.default.fileExists(atPath: storeURL.path) == false, "clear should remove token JSON")

        print("Google Drive token storage checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
