import Foundation

enum SasayakiPlaybackLifecycleTest {
    static func assertContains(_ haystack: String, _ needle: String, _ message: String) {
        if !haystack.contains(needle) {
            fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
            exit(1)
        }
    }

    static func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
        if haystack.contains(needle) {
            fputs("FAIL: \(message)\nUnexpected: \(needle)\n", stderr)
            exit(1)
        }
    }

    static func sourceSection(
        _ source: String,
        from start: String,
        to end: String,
        _ message: String
    ) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            fputs("FAIL: \(message)\nMissing section boundary: \(start) ... \(end)\n", stderr)
            exit(1)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let nativeReader = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeReaderView.swift"),
            encoding: .utf8
        )
        let sasayakiPlayer = try String(
            contentsOf: root.appendingPathComponent("Features/Sasayaki/SasayakiPlayer.swift"),
            encoding: .utf8
        )
        let sasayakiShortcutActions = try String(
            contentsOf: root.appendingPathComponent("Features/Sasayaki/SasayakiShortcutActions.swift"),
            encoding: .utf8
        )
        let popupView = try String(
            contentsOf: root.appendingPathComponent("Features/Popup/PopupView.swift"),
            encoding: .utf8
        )

        let lifecycleClose = sourceSection(
            nativeReader,
            from: "func prepareForReaderLifecycleClose()",
            to: "func nextChapter() -> Bool",
            "native Reader should expose a close/lifecycle persistence boundary"
        )
        assertContains(
            lifecycleClose,
            "flushStats()",
            "Reader close/lifecycle cleanup should keep the existing statistics flush"
        )
        assertContains(
            lifecycleClose,
            "sasayakiPlayer?.teardown()",
            "Reader close/lifecycle cleanup should flush the latest Sasayaki playback position"
        )

        let disappearLifecycle = sourceSection(
            nativeReader,
            from: ".onDisappear {",
            to: ".onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))",
            "native Reader should expose its disappear lifecycle handler"
        )
        assertContains(
            disappearLifecycle,
            "model.prepareForReaderLifecycleClose()",
            "Reader disappear should persist the final Sasayaki playback position through the shared lifecycle boundary"
        )

        let terminationLifecycle = sourceSection(
            nativeReader,
            from: ".onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))",
            to: ".onReceive(NotificationCenter.default.publisher(for: XboxControllerManager.actionNotification))",
            "native Reader should expose its app-termination lifecycle handler"
        )
        assertContains(
            terminationLifecycle,
            "NSApplication.willTerminateNotification",
            "app termination should persist the final Sasayaki playback position even if SwiftUI disappear is bypassed"
        )
        assertContains(
            terminationLifecycle,
            "model.prepareForReaderLifecycleClose()",
            "app termination should use the same Sasayaki persistence path as Reader close"
        )

        let jumpCueAction = sourceSection(
            sasayakiShortcutActions,
            from: "static let jumpCue = ShortcutAction(",
            to: "static let all =",
            "Sasayaki shortcut actions should expose the jump-cue action"
        )
        assertContains(
            jumpCueAction,
            "defaultBinding: .j",
            "Sasayaki jump cue should keep the default j shortcut"
        )

        let shortcutHandlers = sourceSection(
            nativeReader,
            from: "private var sasayakiShortcutHandlers:",
            to: "private func handleReaderPreviousPageShortcut()",
            "native Reader should map Sasayaki shortcut actions to handlers"
        )
        assertContains(
            shortcutHandlers,
            "SasayakiShortcutActions.jumpCue.id: handleSasayakiJumpCueShortcut",
            "the j Sasayaki shortcut should dispatch to the jump-cue handler"
        )

        let jumpCueHandler = sourceSection(
            nativeReader,
            from: "private func handleSasayakiJumpCueShortcut()",
            to: "private func handleControllerShortcut(",
            "native Reader should expose its Sasayaki jump shortcut handler"
        )
        assertContains(
            jumpCueHandler,
            "jumpToSasayakiCue()",
            "the j Sasayaki shortcut should use the shared popup jump path"
        )

        let jumpToCue = sourceSection(
            nativeReader,
            from: "private func jumpToSasayakiCue()",
            to: "var body: some View",
            "native Reader should expose the popup Sasayaki jump path"
        )
        assertContains(
            jumpToCue,
            "model.sasayakiPlayer?.playCue(from: cue, stop: false)",
            "the j Sasayaki shortcut should jump by playing the popup cue without a stop boundary"
        )
        assertContains(
            jumpToCue,
            "model.closePopup(resumePausedPlayback: false)",
            "the j Sasayaki shortcut should close the lookup popup without resuming the old paused position"
        )

        let dismissPopupSection = sourceSection(
            nativeReader,
            from: "func dismissPopup(id: UUID",
            to: "func navigateBackward()",
            "native Reader should expose targeted popup dismissal"
        )
        assertContains(
            dismissPopupSection,
            "resumePausedPlayback: Bool = true",
            "targeted popup dismissal should let Sasayaki jumps opt out of resuming old playback"
        )
        assertContains(
            dismissPopupSection,
            "closePopup(resumePausedPlayback: resumePausedPlayback)",
            "root popup dismissal should pass through the requested Sasayaki resume behavior"
        )

        let popupLayerSection = sourceSection(
            nativeReader,
            from: "private func popupLayer(screenSize: CGSize)",
            to: "private var nativeTopInfoOverlay",
            "native Reader should wire popup dismissal callbacks"
        )
        assertContains(
            popupLayerSection,
            "onSasayakiJumpDismiss",
            "Reader popups should provide a Sasayaki-specific dismissal path"
        )
        assertContains(
            popupLayerSection,
            "model.dismissPopup(id: popupId, resumePausedPlayback: false)",
            "Reader popup Sasayaki controls should not resume the old auto-paused playback position"
        )

        let closePopupSection = sourceSection(
            nativeReader,
            from: "func closePopup(resumePausedPlayback: Bool = true)",
            to: "func closeChildPopups(parent index: Int)",
            "native Reader should expose popup close behavior"
        )
        assertContains(
            closePopupSection,
            "if resumePausedPlayback, wasPaused, sasayakiPlayer?.isPlaying == false",
            "regular popup close should keep the existing auto-resume behavior while allowing Sasayaki jumps to opt out"
        )

        let popupSasayakiControls = sourceSection(
            popupView,
            from: "private func sasayakiControls(",
            to: "private func popupContent(",
            "shared popup view should expose Sasayaki controls"
        )
        assertContains(
            popupSasayakiControls,
            "player.playCue(from: cue, stop: false)",
            "popup forward-frame control should keep the existing Sasayaki cue jump behavior"
        )
        assertContains(
            popupSasayakiControls,
            "(onSasayakiJumpDismiss ?? onSwipeDismiss)?()",
            "popup forward-frame control should use the Sasayaki-specific dismissal callback when provided"
        )

        let playCueSection = sourceSection(
            sasayakiPlayer,
            from: "func playCue(from cue: SasayakiMatch, stop: Bool)",
            to: "func flushPlayback()",
            "Sasayaki player should expose popup cue playback"
        )
        assertContains(
            playCueSection,
            "updateCue: false",
            "popup cue jumps should seek without waiting for cue display updates"
        )
        assertContains(
            playCueSection,
            "stopPlaybackTime: stop ? cue.endTime + delay : nil",
            "playCue(stop: false) should keep playback running after the j shortcut jump"
        )

        let flushSection = sourceSection(
            sasayakiPlayer,
            from: "func flushPlayback()",
            to: "func teardown()",
            "Sasayaki player should expose its close-time flush boundary"
        )
        assertContains(
            flushSection,
            "if let pendingSeekPosition",
            "closing immediately after a j cue jump should flush the requested seek target instead of the old AVPlayer time"
        )
        assertContains(
            flushSection,
            "persistPlaybackPosition(pendingSeekPosition)",
            "close-time flush should reuse the immediate Sasayaki persistence path for pending cue jumps"
        )
        guard let pendingFlushRange = flushSection.range(of: "if let pendingSeekPosition"),
              let playerTimeRange = flushSection.range(of: "player?.currentTime().seconds"),
              pendingFlushRange.lowerBound < playerTimeRange.lowerBound else {
            fputs("FAIL: pending cue-jump position should be flushed before reading AVPlayer currentTime\n", stderr)
            exit(1)
        }

        let tickSection = sourceSection(
            sasayakiPlayer,
            from: "private func tick(",
            to: "private func seek(",
            "Sasayaki player should expose its periodic playback tick"
        )
        assertContains(
            tickSection,
            "if let pendingSeekPosition",
            "periodic ticks should respect pending cue jumps before saving AVPlayer samples"
        )
        assertContains(
            tickSection,
            "guard abs(seconds - pendingSeekPosition) <= seekLandingTolerance else { return }",
            "old AVPlayer time samples should not overwrite a just-persisted cue jump"
        )
        assertContains(
            tickSection,
            "self.pendingSeekPosition = nil",
            "pending cue jumps should only clear once AVPlayer reports time near the requested target"
        )
        guard let tickPendingRange = tickSection.range(of: "if let pendingSeekPosition"),
              let tickSaveRange = tickSection.range(of: "savePlayback()"),
              tickPendingRange.lowerBound < tickSaveRange.lowerBound else {
            fputs("FAIL: stale tick filtering should happen before periodic playback save\n", stderr)
            exit(1)
        }

        let seekSection = sourceSection(
            sasayakiPlayer,
            from: "private func seek(",
            to: "private func setupPlayer(url: URL)",
            "Sasayaki player should expose its seek boundary"
        )
        assertContains(
            seekSection,
            "pendingSeekPosition = seconds",
            "Sasayaki cue jumps should remember the requested target until AVPlayer finishes seeking"
        )
        assertContains(
            seekSection,
            "persistPlaybackPosition(seconds)",
            "cue jumps should persist the target Sasayaki position before waiting for the AVPlayer seek callback"
        )
        assertContains(
            seekSection,
            "seekGeneration += 1",
            "overlapping Sasayaki seeks should have a generation token"
        )
        assertContains(
            seekSection,
            "guard self.seekGeneration == generation else { return }",
            "stale AVPlayer seek completions should not update playback state after a newer seek"
        )
        assertNotContains(
            seekSection,
            "pendingSeekPosition = nil",
            "seek completion should not clear pending cue jumps before AVPlayer emits a matching time sample"
        )
        guard let immediatePersistRange = seekSection.range(of: "persistPlaybackPosition(seconds)"),
              let avSeekRange = seekSection.range(of: "player.seek("),
              immediatePersistRange.lowerBound < avSeekRange.lowerBound else {
            fputs("FAIL: cue jump persistence should happen before AVPlayer seek starts\n", stderr)
            exit(1)
        }

        let persistSection = sourceSection(
            sasayakiPlayer,
            from: "private func persistPlaybackPosition(",
            to: "private func setupPlayer(url: URL)",
            "Sasayaki player should expose immediate playback position persistence"
        )
        assertContains(
            persistSection,
            "playback.lastPosition = seconds",
            "immediate Sasayaki persistence should update the sidecar playback position"
        )
        assertContains(
            persistSection,
            "savePlayback()",
            "immediate Sasayaki persistence should write the sidecar without waiting for the periodic tick"
        )
        assertContains(
            persistSection,
            "onPlayback()",
            "immediate Sasayaki persistence should trigger audiobook auto-export scheduling"
        )

        print("sasayaki playback lifecycle persistence passed")
    }
}

try SasayakiPlaybackLifecycleTest.main()
