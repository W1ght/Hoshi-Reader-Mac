import Foundation
import Observation

struct VideoWindowOpenRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let playbackSource: VideoPlaybackSource
    let subtitleURL: URL?

    init(
        id: UUID = UUID(),
        playbackSource: VideoPlaybackSource,
        subtitleURL: URL? = nil
    ) {
        self.id = id
        self.playbackSource = playbackSource
        self.url = playbackSource.displayURL.standardizedFileURL
        self.subtitleURL = subtitleURL?.standardizedFileURL
    }

    init(id: UUID = UUID(), url: URL, subtitleURL: URL? = nil) {
        self.init(id: id, playbackSource: .localFile(url), subtitleURL: subtitleURL)
    }
}

struct VideoWindowOpenGate {
    private(set) var isRenderReady = false
    private var pendingRequest: VideoWindowOpenRequest?

    mutating func receive(
        _ request: VideoWindowOpenRequest
    ) -> VideoWindowOpenRequest? {
        guard !isRenderReady else { return request }
        pendingRequest = request
        return nil
    }

    mutating func renderDidBecomeReady() -> VideoWindowOpenRequest? {
        guard !isRenderReady else { return nil }
        isRenderReady = true
        defer { pendingRequest = nil }
        return pendingRequest
    }
}

@Observable
@MainActor
final class VideoWindowCoordinator {
    static let windowID = "video-player"

    private(set) var pendingRequest: VideoWindowOpenRequest?
    private(set) var sessionID = UUID()
    private(set) var isWindowPresented = false

    @discardableResult
    func requestOpen(_ url: URL, subtitleURL: URL? = nil) -> VideoWindowOpenRequest {
        requestOpen(.localFile(url), subtitleURL: subtitleURL)
    }

    @discardableResult
    func requestOpen(
        _ playbackSource: VideoPlaybackSource,
        subtitleURL: URL? = nil
    ) -> VideoWindowOpenRequest {
        if !isWindowPresented {
            sessionID = UUID()
        }
        let request = VideoWindowOpenRequest(
            playbackSource: playbackSource,
            subtitleURL: subtitleURL
        )
        pendingRequest = request
        return request
    }

    func consume(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
    }

    func windowDidAppear() {
        isWindowPresented = true
    }

    func windowDidDisappear() {
        isWindowPresented = false
        pendingRequest = nil
    }
}
