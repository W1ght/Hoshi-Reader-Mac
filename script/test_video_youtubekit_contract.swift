import Foundation

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func read(_ path: String) -> String {
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: unable to read \(path)\n", stderr)
        exit(1)
    }
    return value
}

private func containsForbiddenToken(_ contents: String, pattern: String) -> Bool {
    contents.range(of: pattern, options: .regularExpression) != nil
}

let project = read("Niratan.xcodeproj/project.pbxproj")
let loader = read("Features/Video/Remote/YouTubeKitMediaLoader.swift")
let resolver = read("Features/Video/Remote/YouTubeKitRemoteVideoResolver.swift")
let pageMetadataLoader = read("Features/Video/Remote/YouTubePageMetadataLoader.swift")
let libraryView = read("Features/Video/VideoLibraryView.swift")
let embedScript = read("script/embed_video_libraries.sh")
let buildScript = read("script/build_and_run_native.sh")
let packageScript = read("script/package_mac.sh")
let localization = read("Localizable.xcstrings")
let productionRoots = [
    "Features/Video",
    "NativeMac",
    "script/build_and_run_native.sh",
    "script/embed_video_libraries.sh",
    "script/package_mac.sh",
]

require(
    project.contains("https://github.com/alexeichhorn/YouTubeKit.git"),
    "Xcode project should reference the upstream YouTubeKit repository"
)
require(
    project.contains("Video/Remote/YouTubeAndroidVRPlayerResponseParser.swift"),
    "the Video target should compile the Android VR caption parser"
)

let experimentalLocalizedKeys = [
    "Experimental",
    "YouTube playback is experimental and may stop working when YouTube changes its service.",
]
let requiredLocalizedKeys = [
    "Add Link",
    "Open Link",
    "Publisher Subtitles",
    "Remove from Library",
    "Resolving Link...",
    "This link is not supported.",
    "This video is unavailable or private.",
    "This video requires sign-in or age verification.",
    "This video is not available in your region.",
    "Unable to find a playable YouTube video stream.",
    "Unable to load the remote subtitle.",
    "Unable to play audio for this remote video.",
    "Unable to refresh the remote video. Try again.",
    "Unable to resolve this YouTube video. Try again.",
    "YouTube Quality",
    "YouTube Video",
] + experimentalLocalizedKeys
require(
    libraryView.contains("Text(\"Experimental\")")
        && libraryView.contains(
            "Text(\"YouTube playback is experimental and may stop working when YouTube changes its service.\")"
        ),
    "the Add Link sheet should explain that YouTube playback is experimental"
)
let localizationData = Data(localization.utf8)
let localizationRoot = try JSONSerialization.jsonObject(with: localizationData)
    as? [String: Any]
let localizedStrings = localizationRoot?["strings"] as? [String: Any]
for key in requiredLocalizedKeys {
    let entry = localizedStrings?[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    require(
        localizations?["en"] != nil && localizations?["zh-Hans"] != nil,
        "YouTube streaming copy should include English and Simplified Chinese: \(key)"
    )
}
for key in experimentalLocalizedKeys {
    let entry = localizedStrings?[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    require(
        localizations?["zh-Hant"] != nil,
        "experimental YouTube streaming copy should include Traditional Chinese: \(key)"
    )
}
require(
    buildScript.contains("YouTubeKit_YouTubeKit.bundle")
        && packageScript.contains("YouTubeKit_YouTubeKit.bundle")
        && packageScript.contains("Light app unexpectedly contains YouTubeKit resources."),
    "official Light build and package paths should strip and reject YouTubeKit resources"
)
require(
    project.contains("65be95dbb1dbd749499e0638871568c823822276"),
    "YouTubeKit should be pinned to the audited 0.4.8 revision"
)
require(
    project.contains("YouTubeKit in Frameworks")
        && project.contains("productName = YouTubeKit;"),
    "the Niratan target should link the YouTubeKit product"
)
require(
    loader.contains("YouTube(url: url, methods: [.local])"),
    "YouTubeKit extraction must use the local JavaScriptCore method"
)
require(
    !loader.contains(".remote")
        && !resolver.contains(".remote"),
    "the hosted YouTubeKit remote fallback must not be used"
)
require(
    pageMetadataLoader.contains("ANDROID_VR")
        && pageMetadataLoader.contains("X-Youtube-Client-Name")
        && pageMetadataLoader.contains("YouTubeAndroidVRPlayerResponseParser")
        && pageMetadataLoader.contains("visitorData"),
    "publisher captions should come from the Android VR player response instead of empty watch-page timedtext URLs"
)
require(
    embedScript.contains("YouTubeKit_YouTubeKit.bundle")
        && embedScript.contains("UNLOCALIZED_RESOURCES_FOLDER_PATH")
        && embedScript.contains("CONFIGURATION:-")
        && embedScript.contains("rm -rf"),
    "Light builds should remove the Video-only YouTubeKit JavaScript resource bundle"
)

for root in productionRoots {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) else {
        continue
    }
    let files: [String]
    if isDirectory.boolValue {
        let enumerator = FileManager.default.enumerator(atPath: root)
        files = (enumerator?.allObjects as? [String] ?? [])
            .map { root + "/" + $0 }
            .filter { !$0.contains("/Vendor/") }
    } else {
        files = [root]
    }
    for file in files where !file.hasSuffix(".xcassets") {
        guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else {
            continue
        }
        let scannedContents: String
        if file.hasSuffix("Features/Video/Remote/RemoteVideoSource.swift") {
            scannedContents = contents.replacingOccurrences(
                of: #"decodedProviderID == "ytdlp""#,
                with: ""
            )
        } else {
            scannedContents = contents
        }
        require(
            !containsForbiddenToken(
                scannedContents,
                pattern: #"(?i)(^|[^a-z0-9])(?:yt-dlp|ytdlp)([^a-z0-9]|$)"#
            ),
            "production path should not reference yt-dlp: \(file)"
        )
        require(
            !containsForbiddenToken(
                scannedContents,
                pattern: #"(?i)(^|[^a-z0-9])deno([^a-z0-9]|$)"#
            ),
            "production path should not reference Deno: \(file)"
        )
    }
}

print("Video YouTubeKit contract tests passed")
