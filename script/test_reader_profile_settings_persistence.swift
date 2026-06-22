import Foundation

@MainActor
final class UserConfig {
    private var readerSettings: ReaderProfileSettings
    private var dictionarySettings: DictionaryProfileSettings

    init(
        readerSettings: ReaderProfileSettings = .defaults,
        dictionarySettings: DictionaryProfileSettings = .defaults
    ) {
        self.readerSettings = readerSettings
        self.dictionarySettings = dictionarySettings
    }

    func readerProfileSettings() -> ReaderProfileSettings {
        readerSettings
    }

    func dictionaryProfileSettings() -> DictionaryProfileSettings {
        dictionarySettings
    }

    func apply(readerProfileSettings settings: ReaderProfileSettings) {
        readerSettings = settings
    }

    func apply(dictionaryProfileSettings settings: DictionaryProfileSettings) {
        dictionarySettings = settings
    }
}

@main
private enum ReaderProfileSettingsPersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-reader-profile-settings-\(UUID().uuidString)")
        let suiteName = "moe.shishamo.hoshi.tests.reader-profile-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let repository = try ProfileRepository(appDirectory: root, defaults: defaults)
        let store = ProfileSettingsStore(repository: repository)
        var expected = ReaderProfileSettings.defaults
        expected.theme = "Dark"
        expected.fontSize = 31
        expected.horizontalPadding = 17

        store.persistReaderSettings(expected)

        let data = try Data(contentsOf: repository.readerSettingsURL(for: store.appliedProfileID))
        let persisted = try JSONDecoder().decode(ReaderProfileSettings.self, from: data)
        precondition(
            persisted == expected,
            "Reader changes must be written immediately to the active Profile snapshot"
        )

        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("NativeMac/HoshiNativeMacApp.swift"),
            encoding: .utf8
        )
        precondition(
            appSource.contains(".onChange(of: userConfig.readerProfileSettings())")
                && appSource.contains("ProfileSettingsStore.shared.persistReaderSettings(settings)"),
            "The app root must persist every changed Reader Profile snapshot"
        )

        print("Reader profile settings persistence tests passed")
    }
}
