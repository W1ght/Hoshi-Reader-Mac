import Foundation

private enum NativeSettingsNavigationContractTests {
    static func read(_ relativePath: String) -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent(relativePath)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Unable to read \(relativePath)")
        }
        return source
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func run() {
        let root = read("NativeMac/NativeMacRootView.swift")
        let settings = read("NativeMac/NativeReuseViews.swift")
        let dictionary = read("Features/Settings/DictionaryView.swift")
        let profiles = read("Features/Settings/ProfilesView.swift")

        require(
            root.contains(".id(selectedSection)"),
            "Changing the main sidebar section must reset any detail navigation destination"
        )
        require(
            !dictionary.contains("DictionarySettingsView()"),
            "Dictionary preferences must be shown inline instead of pushing a nested Settings destination"
        )
        require(
            dictionary.contains("DictionaryBehaviorSettingsSections()"),
            "The dictionary page must keep lookup and display preferences inline"
        )
        require(
            dictionary.contains("dictionaryManager.recommendedDictionaries.map")
                && !dictionary.contains("following dictionaries (33 MB):"),
            "Recommended dictionary confirmation must follow the active Profile language"
        )
        require(
            settings.contains("case profiles") && settings.contains("ProfilesView()"),
            "Native Settings must expose the Profiles management page"
        )
        require(
            profiles.contains("setGlobalActiveProfile") && profiles.contains("setPrimaryProfile"),
            "Profiles must support active and per-language default selection"
        )
        require(
            profiles.contains("copyFromProfileID: repository.activeProfile.id"),
            "Normal profile creation must copy the current active profile"
        )

        print("Native settings navigation contract passed")
    }
}

NativeSettingsNavigationContractTests.run()
