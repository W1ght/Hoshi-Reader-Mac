import Foundation
import Observation

enum VideoWindowOpenSource: Equatable {
    case playback(VideoPlaybackSource)
    case unresolvedRemote(RemoteVideoWindowOpenRequest)
}

struct VideoWindowOpenRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let source: VideoWindowOpenSource
    let subtitleURL: URL?
    let startsFromBeginning: Bool

    init(
        id: UUID = UUID(),
        playbackSource: VideoPlaybackSource,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) {
        self.id = id
        self.source = .playback(playbackSource)
        self.url = playbackSource.displayURL.standardizedFileURL
        self.subtitleURL = subtitleURL?.standardizedFileURL
        self.startsFromBeginning = startsFromBeginning
    }

    init(
        id: UUID = UUID(),
        remoteRequest: RemoteVideoWindowOpenRequest
    ) {
        self.id = id
        self.source = .unresolvedRemote(remoteRequest)
        self.url = remoteRequest.identity.canonicalURL
            ?? remoteRequest.identity.originalURL
        self.subtitleURL = nil
        self.startsFromBeginning = remoteRequest.startsFromBeginning
    }

    init(
        id: UUID = UUID(),
        url: URL,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) {
        self.init(
            id: id,
            playbackSource: .localFile(url),
            subtitleURL: subtitleURL,
            startsFromBeginning: startsFromBeginning
        )
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
    func requestOpen(
        _ url: URL,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) -> VideoWindowOpenRequest {
        requestOpen(
            .localFile(url),
            subtitleURL: subtitleURL,
            startsFromBeginning: startsFromBeginning
        )
    }

    @discardableResult
    func requestOpen(
        _ playbackSource: VideoPlaybackSource,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) -> VideoWindowOpenRequest {
        requestOpen(
            VideoWindowOpenRequest(
                playbackSource: playbackSource,
                subtitleURL: subtitleURL,
                startsFromBeginning: startsFromBeginning
            )
        )
    }

    @discardableResult
    func requestOpen(
        remoteRequest: RemoteVideoWindowOpenRequest
    ) -> VideoWindowOpenRequest {
        requestOpen(VideoWindowOpenRequest(remoteRequest: remoteRequest))
    }

    private func requestOpen(
        _ request: VideoWindowOpenRequest
    ) -> VideoWindowOpenRequest {
        if !isWindowPresented {
            sessionID = UUID()
        }
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
