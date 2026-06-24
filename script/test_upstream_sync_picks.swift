import Foundation

@main
private enum UpstreamSyncPickTests {
    static func main() {
        let config = AnkiConnectConfig(
            url: "http://127.0.0.1:8765",
            timeout: 10,
            duplicateScope: .deck,
            checkAllModels: true,
            forceSync: true,
            apiKey: "secret-token"
        )
        let data = try! JSONEncoder().encode(config)
        let json = String(decoding: data, as: UTF8.self)
        expect(json.contains("\"apiKey\""), "AnkiConnect config should persist the optional API key")
        let decoded = try! JSONDecoder().decode(AnkiConnectConfig.self, from: data)
        expect(decoded.apiKey == "secret-token", "AnkiConnect config should round-trip the API key")

        let legacyJSON = """
        {"url":"http://127.0.0.1:8765","timeout":10,"duplicateScope":"collection","checkAllModels":false,"forceSync":false}
        """
        let legacy = try! JSONDecoder().decode(AnkiConnectConfig.self, from: Data(legacyJSON.utf8))
        expect(legacy.apiKey == nil, "Legacy AnkiConnect config should decode without an API key")

        let ankiManager = read("Core/AnkiManager.swift")
        let ankiConnectView = read("Features/Settings/AnkiConnectView.swift")
        let dictionaries = read("Dictionaries.xcstrings")
        expect(
            ankiManager.contains("body[\"key\"] = apiKey"),
            "AnkiConnect requests should include the optional API key at the top level"
        )
        expect(
            ankiConnectView.contains("SecureField")
                && ankiConnectView.contains("API Key (optional)")
                && ankiConnectView.contains("ankiConnectConfig?.apiKey"),
            "AnkiConnect settings should expose an optional secure API key field"
        )
        expect(dictionaries.contains("\"API Key (optional)\""), "API key label should be localizable")

        let driveAuth = read("Features/Sync/GoogleDriveAuth.swift")
        let driveHandler = read("Features/Sync/GoogleDriveHandler.swift")
        let bookshelfModel = read("Features/Bookshelf/BookshelfViewModel.swift")
        expect(
            driveAuth.components(separatedBy: "request.timeoutInterval = 10").count >= 3,
            "Google token exchange and refresh requests should time out after 10 seconds"
        )
        expect(
            driveHandler.contains("private let session: URLSession")
                && driveHandler.contains("config.timeoutIntervalForRequest = 10")
                && driveHandler.contains("config.waitsForConnectivity = false"),
            "Google Drive API requests should use a non-waiting 10 second session"
        )
        expect(
            driveHandler.contains("pathMonitor.currentPath.status == .unsatisfied")
                && !driveHandler.contains("pathMonitor.currentPath.status != .satisfied"),
            "Google Drive should only block requests when the path is explicitly unsatisfied"
        )
        expect(
            driveHandler.contains("try await session.data(for: request)")
                && driveHandler.contains("session.dataTask(with: request)"),
            "Google Drive regular and progress downloads should use the timeout session"
        )
        expect(
            bookshelfModel.contains("suppressOfflineErrors: Bool = false")
                && bookshelfModel.contains(".timedOut")
                && bookshelfModel.contains(".networkConnectionLost"),
            "Bookshelf Google Drive refresh should optionally suppress transient offline timeout errors"
        )

        let coverImage = read("Util/CoverImage.swift")
        expect(
            coverImage.contains("private actor ThumbnailDecoder")
                && coverImage.contains("ThumbnailDecoder.shared.thumbnail"),
            "Book covers should serialize thumbnail decoding through one actor"
        )

        let shelfView = read("Features/Bookshelf/ShelfView.swift")
        expect(
            shelfView.contains("if section.isReading")
                && shelfView.contains("Text(\"Reading\")"),
            "Reading shelf title should use the localized Reading key"
        )

        let reader = read("NativeMac/NativeReaderView.swift")
        expect(
            reader.contains("Button(\"Close\"")
                && reader.contains("onClose()")
                && reader.contains("Unable to Open Book"),
            "Native Reader load failure should offer an explicit close action"
        )

        print("Upstream sync pick tests passed")
    }

    private static func read(_ path: String) -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            fputs("FAIL: could not read \(path): \(error)\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
