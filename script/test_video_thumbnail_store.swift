import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

private func maybeSource(_ path: String) -> String? {
    try? source(path)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let libraryView = try source("Features/Video/VideoLibraryView.swift")
let viewModel = try source("Features/Video/VideoLibraryViewModel.swift")
let clientHeader = try source("Features/Video/Playback/HSMpvClient.h")
let clientImplementation = try source("Features/Video/Playback/HSMpvClient.mm")
let project = try source("Hoshi Reader.xcodeproj/project.pbxproj")
let localization = try source("Localizable.xcstrings")
let thumbnailStore = maybeSource("Features/Video/VideoThumbnailStore.swift")

expect(
    thumbnailStore == nil,
    "VideoThumbnailStore.swift should be removed when video thumbnails are disabled"
)
expect(
    !libraryView.contains("VideoThumbnailStore")
        && !libraryView.contains("VideoThumbnailImageView")
        && !libraryView.contains("VideoLibraryPosterGridView")
        && !libraryView.contains("VideoLibraryPosterCardView")
        && !libraryView.contains("VideoLibraryPosterPlayOverlay")
        && !libraryView.contains("VideoLibraryBottomProgressBar")
        && !libraryView.contains("VideoLibraryLayoutToolbarControl")
        && !libraryView.contains("VideoLibraryLayoutSegmentedControl")
        && !libraryView.contains("LazyVGrid")
        && !libraryView.contains("generatesMissingThumbnail")
        && !libraryView.contains("thumbnailStore")
        && !libraryView.contains("layoutMode"),
    "Video library UI should not expose thumbnail, poster-grid, or layout-mode surfaces"
)
expect(
    !viewModel.contains("VideoLibraryLayoutMode")
        && !viewModel.contains("layoutMode"),
    "Video library state should not retain poster/list layout mode after thumbnails are removed"
)
expect(
    !clientHeader.contains("HSMpvThumbnailGenerator")
        && !clientImplementation.contains("HSMpvThumbnailGenerator")
        && !clientImplementation.contains("HSMpvRenderThumbnailPNGData")
        && !clientImplementation.contains("HSMpvCreateThumbnailOutputDirectory")
        && !clientImplementation.contains("thumbnailPNGData"),
    "mpv thumbnail generation bridge should be removed"
)
expect(
    !project.contains("Video/VideoThumbnailStore.swift"),
    "project membership exceptions should not include removed thumbnail store"
)
expect(
    !localization.contains("\"Posters\"")
        && !localization.contains("\"Video Layout\"")
        && !localization.contains("\"List\""),
    "layout-switch-only localization keys should be removed"
)

print("Video thumbnail removal contract passed")
