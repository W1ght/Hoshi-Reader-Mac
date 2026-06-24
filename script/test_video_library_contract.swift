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

private let rootView = try source("NativeMac/NativeMacRootView.swift")
private let detailView = try source("NativeMac/NativeMacDetailView.swift")
private let project = try source("Hoshi Reader.xcodeproj/project.pbxproj")
private let localization = try source("Localizable.xcstrings")
private let store = try source("Features/Video/VideoLibraryStore.swift")
private let thumbnailStore = try? source("Features/Video/VideoThumbnailStore.swift")
private let viewModel = try source("Features/Video/VideoLibraryViewModel.swift")
private let buildScript = try source("script/build_and_run_native.sh")
private let manualFixtureScript = try? source("script/verify_video_library_manual_fixture.sh")

require(
    !rootView.contains("if newSelection == .video {\n                selection = lastNonVideoSection\n                isSelectingVideoFile = true\n                return\n            }"),
    "Video sidebar selection should render the library page instead of immediately opening the file picker"
)
require(
    detailView.contains("VideoLibraryView("),
    "Native detail should render VideoLibraryView for the Video section"
)
for file in [
    "Video/VideoLibraryStore.swift",
    "Video/VideoLibraryViewModel.swift",
    "Video/VideoLibraryView.swift",
    "Video/VideoThumbnailStore.swift",
] {
    require(project.contains(file), "project membership exceptions should include \(file)")
}
for key in [
    "Add Video Folder",
    "%@ left",
    "Clear Progress",
    "Continue Watching",
    "No Videos in Progress",
    "No Video Folders",
    "Partially watched videos will appear here.",
    "Play from Beginning",
    "Recent",
    "All Videos",
    "Folders",
    "Finished",
    "List",
    "Mark as Watched",
    "Manage Sources",
    "Missing",
    "Posters",
    "Reveal in Finder",
    "Reveal Source in Finder",
    "Search Videos",
    "Sort Videos",
    "Unfinished",
    "Unwatched",
    "Video Layout",
    "Watched",
    "%d in progress",
    "%d missing",
    "%d videos",
    "Last Scanned",
    "Missing videos will appear here until their source is refreshed.",
    "Never scanned",
    "No Finished Videos",
    "No Missing Videos",
    "No Matching Videos",
    "No Unwatched Videos",
    "Refresh Source",
    "Try a different search or filter.",
    "Videos marked watched will appear here.",
    "Videos without playback progress will appear here.",
] {
    require(localization.contains("\"\(key)\""), "Localizable.xcstrings should include \(key)")
}

let libraryView = try source("Features/Video/VideoLibraryView.swift")
require(
    libraryView.contains("VideoLibraryControlBar(viewModel: viewModel)")
        && libraryView.contains("private struct VideoLibraryControlBar"),
    "Video library should keep browsing controls in a fixed page header"
)
require(
    libraryView.contains("ScrollView(.horizontal, showsIndicators: false)"),
    "Video library page header should remain accessible in narrow windows instead of collapsing toolbar controls"
)
require(
    libraryView.contains("VideoLibraryHeaderGlassSurface")
        && libraryView.contains("GlassEffectContainer")
        && libraryView.contains(".glassEffect(")
        && libraryView.contains(".regular.interactive()")
        && libraryView.contains(".thinMaterial"),
    "Video library page header should use a Liquid Glass surface with a material fallback"
)
require(
    !libraryView.contains(".background(.bar)"),
    "Video library page header should not use the old opaque bar background"
)
require(
    libraryView.contains("TextField(\"Search Videos\"")
        && libraryView.contains("Picker(\"Sort Videos\"")
        && libraryView.contains("Picker(\"Video Layout\"")
        && libraryView.contains("Toggle(isOn: $viewModel.showUnfinishedOnly)"),
    "Video library page header should expose search, sort, layout, and unfinished filtering controls"
)
require(
    libraryView.contains("VideoLibraryPosterGridView")
        && libraryView.contains("LazyVGrid")
        && libraryView.contains("VideoThumbnailImageView"),
    "Video library should expose a poster grid backed by thumbnails"
)
require(
    libraryView.contains("Label(\"Mark as Watched\"")
        && libraryView.contains("Label(\"Clear Progress\"")
        && libraryView.contains("Label(\"Play from Beginning\""),
    "Video library row context menu should expose playback state actions"
)
require(
    libraryView.contains("viewModel.sourceSummaries")
        && libraryView.contains("summary.itemCount")
        && libraryView.contains("summary.inProgressCount")
        && libraryView.contains("summary.missingCount")
        && libraryView.contains("Label(\"Refresh Source\"")
        && libraryView.contains("Label(\"Reveal Source in Finder\""),
    "Video source management should show source status counts and per-source actions"
)
if let primaryActionRange = libraryView.range(of: "ToolbarItemGroup(placement: .primaryAction)") {
    let toolbarTail = libraryView[primaryActionRange.lowerBound...]
    let toolbarEnd = toolbarTail.range(of: "private struct VideoLibraryControlBar")?.lowerBound ?? toolbarTail.endIndex
    let primaryActionToolbar = toolbarTail[..<toolbarEnd]
    require(
        !primaryActionToolbar.contains("TextField(\"Search Videos\"")
            && !primaryActionToolbar.contains("Picker(\"Sort Videos\"")
            && !primaryActionToolbar.contains("Toggle(isOn: $viewModel.showUnfinishedOnly)"),
        "Video library search, sort, and unfinished controls should not collapse into the primary-action toolbar"
    )
} else {
    require(false, "Video library should keep a primary-action toolbar for compact action buttons")
}
require(
    libraryView.contains("UserDefaults.didChangeNotification")
        && libraryView.contains("viewModel.refreshPlaybackHistory()"),
    "Video library should refresh Recent/progress when playback history changes"
)
require(
    viewModel.contains("playbackHistoryRevision")
        && viewModel.contains("func refreshPlaybackHistory()")
        && viewModel.contains("_ = playbackHistoryRevision"),
    "Video library view model should expose an observable playback history refresh revision"
)
require(
    viewModel.contains("case continueWatching")
        && viewModel.contains("case unwatched")
        && viewModel.contains("case finished")
        && viewModel.contains("case missing")
        && viewModel.contains("enum VideoLibraryLayoutMode")
        && viewModel.contains("layoutMode")
        && viewModel.contains("VideoLibrarySourceSummary")
        && viewModel.contains("sourceSummaries")
        && viewModel.contains("func refreshSource")
        && viewModel.contains("func markWatched")
        && viewModel.contains("func clearProgress")
        && viewModel.contains("func openFromBeginningURL"),
    "Video library view model should support smart filters, source summaries, poster layout, and playback state actions"
)
require(
    thumbnailStore?.contains("VideoThumbnailStore") == true
        && thumbnailStore?.contains("AVAssetImageGenerator") == true
        && thumbnailStore?.contains("VideoThumbnails") == true
        && thumbnailStore?.contains("thumbnailPNGData") == true,
    "Video thumbnail store should generate and cache poster frames"
)
require(
    viewModel.contains("No Matching Videos")
        && viewModel.contains("Try a different search or filter."),
    "Video library view model should expose filtered empty-state copy"
)
require(
    store.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL")
        && store.contains("ProcessInfo.processInfo.environment"),
    "Video library store should support a catalog override for disposable UI validation"
)
require(
    buildScript.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL")
        && buildScript.contains("--env"),
    "native launch script should pass the disposable Video library catalog override into the launched app"
)
require(
    manualFixtureScript?.contains("HOSHI_VIDEO_LIBRARY_CATALOG_URL") == true
        && manualFixtureScript?.contains("mktemp -d") == true
        && manualFixtureScript?.contains("--video --verify") == true,
    "Video library manual fixture script should launch Video with a disposable catalog"
)

print("Video library contract tests passed")
