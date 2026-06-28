import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let store = try source("Features/Video/VideoPlaybackHistoryStore.swift")
let viewModel = try source("Features/Video/VideoPlayerViewModel.swift")

require(
    store.contains("moe.shishamo.hoshi.video.playback-history")
        && store.contains("savePlaybackStateDeferred(")
        && store.contains("Self.persistenceQueue.async"),
    "playback progress persistence should have a dedicated background queue"
)

require(
    viewModel.contains("saveCurrentPosition(deferred: true)")
        && viewModel.contains("saveCurrentPosition(deferred: false)")
        && viewModel.contains("historyStore.savePlaybackStateDeferred("),
    "playback tick saves should be deferred while media-switch saves remain synchronous"
)

print("Video playback history persistence contract tests passed")
