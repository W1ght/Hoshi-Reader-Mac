import Foundation

enum SasayakiPlaybackLifecycleTest {
    static func assertContains(_ haystack: String, _ needle: String, _ message: String) {
        if !haystack.contains(needle) {
            fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
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

        print("sasayaki playback lifecycle persistence passed")
    }
}

try SasayakiPlaybackLifecycleTest.main()
