import Foundation

private func source(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("FAIL: \(message)")
    }
}

private func expectContains(_ source: String, _ needle: String, _ message: String) {
    expect(source.contains(needle), "\(message)\nMissing: \(needle)")
}

private func expectNotContains(_ source: String, _ needle: String, _ message: String) {
    expect(!source.contains(needle), "\(message)\nUnexpected: \(needle)")
}

let glass = try source("NativeMac/NativeGlassSurface.swift")
let root = try source("NativeMac/NativeMacRootView.swift")
let detail = try source("NativeMac/NativeMacDetailView.swift")
let reuse = try source("NativeMac/NativeReuseViews.swift")
let dictionarySearch = try source("Features/Dictionary/DictionarySearchView.swift")
let dictionarySettings = try source("Features/Settings/DictionaryView.swift")
let changelog = try source("docs/CHANGELOG.md")

expectContains(
    glass,
    "struct NativeGlassPageBackground: View",
    "Native glass page background should live in one shared native surface file"
)

expectContains(
    glass,
    "func nativeGlassCardSurface(cornerRadius: CGFloat = 18)",
    "Settings cards and other repeated surfaces should share one glass card modifier"
)

expectContains(
    glass,
    "func nativeGlassCapsuleSurface()",
    "Search fields and compact controls should share one glass capsule modifier"
)

expectContains(
    glass,
    "static func tint(for userConfig: UserConfig, colorScheme: ColorScheme) -> Color",
    "Glass tint should be calculated from the existing app theme and color scheme"
)

expectContains(
    root,
    "return .hidden",
    "Main window toolbar background should be hidden for app sections so glass extends into the titlebar"
)

expectContains(
    detail,
    "NativeGlassPageBackground()",
    "Main detail column should paint the shared glass background behind the selected section"
)

expectContains(
    reuse,
    "NativeGlassPageBackground()",
    "Reusable native Bookshelf and Settings surfaces should use the shared glass background"
)

expectContains(
    reuse,
    ".nativeGlassCardSurface(cornerRadius: 18)",
    "Native Settings cards should use the shared glass card surface"
)

expectContains(
    dictionarySearch,
    "NativeGlassTopScrim()",
    "Dictionary search should use a theme-aware glass top scrim instead of an opaque window-background gradient"
)

expectContains(
    dictionarySearch,
    ".nativeGlassCapsuleSurface()",
    "Dictionary search bar should use the shared glass capsule surface"
)

expectNotContains(
    dictionarySearch,
    "private var platformBackgroundColor: Color",
    "Dictionary search should not keep a page-level window-background color helper"
)

expectNotContains(
    dictionarySearch,
    "LinearGradient(colors: [platformBackgroundColor, .clear]",
    "Dictionary search should not cover the page with an opaque window-background gradient"
)

expectContains(
    dictionarySettings,
    "NativeGlassPageBackground()",
    "Dictionary CSS editor should use the shared native glass page background"
)

expectContains(
    changelog,
    "主界面、书架、词典和设置",
    "Changelog should mention the user-visible glass background update"
)

print("Native glass background contract passed")
