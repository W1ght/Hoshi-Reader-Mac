import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoWindowOpenRequestTests {
    @MainActor
    static func main() {
        let videoURL = URL(fileURLWithPath: "/tmp/Episode.mkv")
        let subtitleURL = URL(fileURLWithPath: "/tmp/Episode.ja.srt")

        let coordinator = VideoWindowCoordinator()
        let request = coordinator.requestOpen(videoURL, subtitleURL: subtitleURL)

        expect(request.url == videoURL.standardizedFileURL, "request should standardize video URL")
        expect(request.subtitleURL == subtitleURL.standardizedFileURL, "request should carry bound subtitle URL")
        expect(coordinator.pendingRequest == request, "coordinator should publish the pending request")

        var gate = VideoWindowOpenGate()
        expect(gate.receive(request) == nil, "gate should hold requests until render is ready")
        expect(
            gate.renderDidBecomeReady()?.subtitleURL == subtitleURL.standardizedFileURL,
            "gate should release the pending subtitle request when render becomes ready"
        )

        print("Video window open request tests passed")
    }
}
