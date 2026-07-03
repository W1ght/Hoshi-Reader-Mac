import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func requireContains(_ source: String, _ needle: String, _ message: String) {
    require(source.contains(needle), "\(message)\nMissing: \(needle)")
}

private func requireNotContains(_ source: String, _ needle: String, _ message: String) {
    require(!source.contains(needle), "\(message)\nUnexpected: \(needle)")
}

let fileManager = FileManager.default

require(
    fileManager.fileExists(atPath: root.appendingPathComponent("Niratan.xcodeproj").path),
    "Xcode project should use the Niratan name"
)
require(
    !fileManager.fileExists(atPath: root.appendingPathComponent("Hoshi Reader.xcodeproj").path),
    "legacy Xcode project path should not remain in the working tree"
)

let project = try source("Niratan.xcodeproj/project.pbxproj")
let lightScheme = try source("Niratan.xcodeproj/xcshareddata/xcschemes/Niratan.xcscheme")
let videoScheme = try source("Niratan.xcodeproj/xcshareddata/xcschemes/Niratan Video.xcscheme")
let buildScript = try source("script/build_and_run_native.sh")
let packageScript = try source("script/package_mac.sh")
let releaseScript = try source("script/release_mac.sh")
let releaseWorkflow = try source(".github/workflows/release-mac.yml")
let updateChecker = try source("Util/Extensions.swift")
let readme = try source("README.md")

requireContains(project, "/* Niratan.app */", "build product should be Niratan.app")
requireContains(project, "name = \"Niratan\";", "native target should be named Niratan")
requireContains(project, "productName = \"Niratan\";", "native target product should be named Niratan")
requireContains(project, "INFOPLIST_KEY_CFBundleDisplayName = \"Niratan\";", "display name should be Niratan")
requireContains(project, "PRODUCT_BUNDLE_IDENTIFIER = moe.shishamo.hoshi;", "bundle id should remain stable for user data compatibility")
requireNotContains(project, "Hoshi Reader.app", "project file should not refer to the old app bundle name")

for scheme in [lightScheme, videoScheme] {
    requireContains(scheme, "BuildableName = \"Niratan.app\"", "shared schemes should build Niratan.app")
    requireContains(scheme, "BlueprintName = \"Niratan\"", "shared schemes should target Niratan")
    requireContains(scheme, "ReferencedContainer = \"container:Niratan.xcodeproj\"", "shared schemes should point to Niratan.xcodeproj")
}
requireContains(videoScheme, "buildConfiguration = \"Debug-Video\"", "Video scheme should keep the Video debug configuration")
requireContains(videoScheme, "buildConfiguration = \"Release-Video\"", "Video scheme should keep the Video release configuration")

requireContains(buildScript, "APP_NAME=\"Niratan\"", "build script should launch Niratan")
requireContains(buildScript, "PROJECT_NAME=\"Niratan.xcodeproj\"", "build script should build the renamed project")
requireContains(buildScript, "SCHEME_NAME=\"Niratan Video\"", "build script should expose the renamed Video scheme")
requireContains(buildScript, "EXPECTED_BUNDLE_ID=\"moe.shishamo.hoshi\"", "build script should verify the compatibility bundle id")

requireContains(packageScript, "APP_NAME=\"Niratan\"", "package script should package Niratan")
requireContains(packageScript, "ARTIFACT_NAME=\"Niratan-Mac-$VERSION\"", "Light artifact should use the Niratan brand")
requireContains(packageScript, "ARTIFACT_NAME=\"Niratan-Mac-Video-$VERSION\"", "Video artifact should use the Niratan brand")
requireContains(packageScript, "hdiutil create -volname \"Niratan $VERSION\"", "DMG volume should use the Niratan brand")

requireContains(releaseScript, "PROJECT_NAME=\"Niratan.xcodeproj\"", "release script should bump the renamed project")
requireContains(releaseScript, "Niratan Mac $VERSION", "release tag message should use the Niratan brand")
requireContains(releaseScript, "https://github.com/W1ght/Niratan/releases/tag/$TAG", "release script should print the renamed release URL")

requireContains(releaseWorkflow, "artifact: niratan-mac-light", "release workflow artifact id should use the Niratan brand")
requireContains(releaseWorkflow, "artifact: niratan-mac-video", "release workflow Video artifact id should use the Niratan brand")
requireContains(releaseWorkflow, "Niratan-Mac-$version.dmg", "release workflow should publish the renamed Light DMG")
requireContains(releaseWorkflow, "Niratan-Mac-Video-$version.dmg", "release workflow should publish the renamed Video DMG")
requireContains(releaseWorkflow, "legacy_artifact=\"Hoshi-Reader-Mac-$version\"", "release workflow should attach legacy Light filenames for older updaters")
requireContains(releaseWorkflow, "legacy_artifact=\"Hoshi-Reader-Mac-Video-$version\"", "release workflow should attach legacy Video filenames for older updaters")

requireContains(updateChecker, "https://api.github.com/repos/W1ght/Niratan/releases/latest", "update checker should query the renamed release repo")
requireContains(updateChecker, "Niratan-Mac-\\(version).dmg", "update checker should look for renamed Light DMGs")
requireContains(updateChecker, "Niratan-Mac-Video-\\(version).dmg", "update checker should look for renamed Video DMGs")
requireContains(updateChecker, "\"Niratan-Mac\"", "update checker should use the renamed user agent")

let localizationData = try Data(contentsOf: root.appendingPathComponent("Localizable.xcstrings"))
guard
    let localizationRoot = try JSONSerialization.jsonObject(with: localizationData) as? [String: Any],
    let localizedStrings = localizationRoot["strings"] as? [String: Any]
else {
    fputs("FAIL: Localizable.xcstrings should be valid JSON with a strings object\n", stderr)
    exit(1)
}
require(localizedStrings["Niratan"] != nil, "Localizable.xcstrings should expose the Niratan app label")
require(localizedStrings["Hoshi Reader"] == nil, "Localizable.xcstrings should not keep the old app label key")
require(localizedStrings["Original Hoshi Reader Project"] != nil, "attribution to the original Hoshi Reader project should remain explicit")

requireContains(readme, "# Niratan", "README should present the renamed project")
requireContains(readme, "https://github.com/W1ght/Niratan/releases", "README should link to the renamed release page")

print("Branding contract checks passed")
