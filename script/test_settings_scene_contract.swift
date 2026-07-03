import Foundation

private let appSource = try String(contentsOfFile: "NativeMac/HoshiNativeMacApp.swift", encoding: .utf8)
private let nativeReuseViews = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("FAIL: \(message)")
    }
}

private func expectContains(_ source: String, _ needle: String, _ message: String) {
    expect(source.contains(needle), "\(message)\nMissing: \(needle)")
}

private func substring(after needle: String, in source: String) -> String {
    guard let range = source.range(of: needle) else {
        return ""
    }
    return String(source[range.lowerBound...])
}

private let settingsSceneSource = substring(after: "Settings {", in: appSource)

expectContains(
    appSource,
    "Settings {",
    "The app should declare a native macOS Settings scene so Niratan > Settings opens a compact preferences window"
)

expectContains(
    appSource,
    "NativeSettingsWindowRoot()",
    "The Settings scene should delegate to a dedicated settings window root"
)

expectContains(
    appSource,
    "struct NativeSettingsWindowRoot: View",
    "The settings window root should stay thin and local to the app scene wiring"
)

expectContains(
    appSource,
    "NativeSettingsReuseView()",
    "The settings window root should reuse the existing native Settings sidebar/detail surface"
)

expectContains(
    appSource,
    ".environment(userConfig)",
    "The Settings scene should receive the same shared UserConfig environment as the main window"
)

expectContains(
    settingsSceneSource,
    ".environment(selectionLookupCoordinator)",
    "The Settings scene should receive SelectionLookupCoordinator because Keyboard Shortcuts reads it from the environment"
)

expectContains(
    settingsSceneSource,
    "selectionLookupCoordinator.configure(userConfig: userConfig)",
    "The Settings scene should configure SelectionLookupCoordinator when opened without the main window"
)

expectContains(
    appSource,
    ".preferredColorScheme(preferredColorScheme)",
    "The Settings scene should follow the same app theme resolution as the main window"
)

expectContains(
    settingsSceneSource,
    ".onChange(of: userConfig.readerProfileSettings())",
    "The Settings scene should persist Reader profile settings even when the main window is closed"
)

expectContains(
    settingsSceneSource,
    "ProfileSettingsStore.shared.persistReaderSettings(settings)",
    "Reader profile settings changes from the Settings scene should be written to the active profile store"
)

expectContains(
    settingsSceneSource,
    ".onChange(of: userConfig.dictionaryProfileSettings())",
    "The Settings scene should persist Dictionary profile settings even when the main window is closed"
)

expectContains(
    settingsSceneSource,
    "ProfileSettingsStore.shared.persistDictionarySettings(settings)",
    "Dictionary profile settings changes from the Settings scene should be written to the active profile store"
)

expectContains(
    nativeReuseViews,
    "struct NativeSettingsReuseView: View",
    "The reusable Settings surface should remain available to both the main section and the Settings scene"
)

print("Settings scene contract passed")
