import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

private func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Unable to read \(path)")
    }
    return contents
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

private func expectContains(_ source: String, _ needle: String, _ message: String) {
    expect(source.contains(needle), message)
}

private func controllerReceiveBlock(in source: String) -> String {
    let startNeedle = ".onReceive(NotificationCenter.default.publisher(for: XboxControllerManager.actionNotification))"
    guard let start = source.range(of: startNeedle)?.lowerBound else {
        fatalError("NativeReaderView should listen for controller action notifications")
    }
    guard let end = source[start...].range(of: "\n        .sheet(item: $activeSheet)")?.lowerBound else {
        fatalError("Unable to isolate controller action notification block")
    }
    return String(source[start..<end])
}

let controllerManager = read("Core/XboxControllerManager.swift")
let nativeReader = read("NativeMac/NativeReaderView.swift")
let controllerBlock = controllerReceiveBlock(in: nativeReader)

expectContains(
    controllerManager,
    "var shortcutActionID: String?",
    "Controller actions should expose their matching keyboard shortcut action id"
)
expectContains(
    controllerManager,
    "case .previousPage:\n            ReaderShortcutActions.previousPage.id",
    "Previous page controller action should map to the Reader previous-page shortcut action"
)
expectContains(
    controllerManager,
    "case .nextPage:\n            ReaderShortcutActions.nextPage.id",
    "Next page controller action should map to the Reader next-page shortcut action"
)
expectContains(
    controllerManager,
    "case .previousSasayakiCue:\n            SasayakiShortcutActions.previousCue.id",
    "Previous cue controller action should map to the Sasayaki previous-cue shortcut action"
)
expectContains(
    controllerManager,
    "case .playPauseSasayaki:\n            SasayakiShortcutActions.playPause.id",
    "Play/pause controller action should map to the Sasayaki play-pause shortcut action"
)
expectContains(
    controllerManager,
    "case .nextSasayakiCue:\n            SasayakiShortcutActions.nextCue.id",
    "Next cue controller action should map to the Sasayaki next-cue shortcut action"
)
expectContains(
    controllerManager,
    "case .replaySasayakiCue:\n            SasayakiShortcutActions.replayCue.id",
    "Replay cue controller action should map to the Sasayaki replay-cue shortcut action"
)
expectContains(
    controllerManager,
    "case .jumpSasayakiCue:\n            SasayakiShortcutActions.jumpCue.id",
    "Jump cue controller action should map to the Sasayaki jump-cue shortcut action"
)

expectContains(
    nativeReader,
    "private var readerShortcutHandlers: [String: ShortcutHandler]",
    "Reader shortcut handlers should be reusable by keyboard and controller dispatch"
)
expectContains(
    nativeReader,
    "private var sasayakiShortcutHandlers: [String: ShortcutHandler]",
    "Sasayaki shortcut handlers should be reusable by keyboard and controller dispatch"
)
expectContains(
    nativeReader,
    "private func handleControllerShortcut(_ action: XboxControllerAction)",
    "NativeReaderView should dispatch controller actions through keyboard shortcut handlers"
)
expectContains(
    controllerBlock,
    "handleControllerShortcut(action)",
    "Controller notification handling should call the shared shortcut dispatcher"
)

for directCall in [
    "navigateBackward()",
    "navigateForward()",
    "playPreviousSasayakiCue()",
    "toggleSasayakiPlayback()",
    "playNextSasayakiCue()",
    "replaySasayakiCue()",
    "jumpToSasayakiCue()"
] {
    expect(
        !controllerBlock.contains(directCall),
        "Controller notification block should not directly call \(directCall); use shared shortcut handlers"
    )
}

print("Controller shortcut alignment tests passed")
