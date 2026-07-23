import AppKit
import Observation

enum VideoAmbientRefreshReason {
    case load
    case pause
    case seek
    case playback
}

@Observable
@MainActor
final class VideoAmbientBackdropModel {
    private(set) var image: NSImage?

    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastRequestTime: TimeInterval?

    private static let playbackInterval: TimeInterval = 3.0
    private static let previewMaximumDimension = 320

    func reset(for generation: Int) {
        captureTask?.cancel()
        captureTask = nil
        self.generation = generation
        lastRequestTime = nil
        image = nil
    }

    func refresh(
        reason: VideoAmbientRefreshReason,
        engine: any PlaybackEngine,
        generation: Int,
        isLoaded: Bool,
        isPlaying: Bool,
        isActive: Bool,
        isFullScreen: Bool,
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        guard generation == self.generation,
              isLoaded,
              isActive,
              captureTask == nil else {
            return
        }

        if reason == .playback {
            guard isPlaying else { return }
            if let lastRequestTime,
               now - lastRequestTime < Self.playbackInterval {
                return
            }
        }

        lastRequestTime = now
        captureTask = Task { [weak self] in
            guard let self else { return }
            let preview = await engine.captureAmbientPreview(
                maximumDimension: Self.previewMaximumDimension
            )
            guard !Task.isCancelled,
                  let preview,
                  preview.generation == self.generation else {
                self.captureTask = nil
                return
            }
            self.image = preview.image
            self.captureTask = nil
        }
    }

    func suspend(clear: Bool) {
        captureTask?.cancel()
        captureTask = nil
        if clear {
            image = nil
            lastRequestTime = nil
        }
    }
}
