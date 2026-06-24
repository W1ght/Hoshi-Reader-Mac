#if HOSHI_VIDEO
import AppKit
import Foundation

enum VideoTrackType: String, Codable, CaseIterable, Hashable {
    case video
    case audio
    case subtitle
}

struct VideoTrack: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let type: VideoTrackType
    let title: String
    let language: String?
    let codec: String?
    let ffIndex: Int?
    let externalFilename: String?
    let isImage: Bool
    let isSelected: Bool

    var displayName: String {
        if let language, !language.isEmpty {
            return "\(title) · \(language)"
        }
        return title
    }
}

struct VideoEmbeddedSubtitleCue: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct VideoChapter: Identifiable, Equatable, Hashable {
    let id: Int
    let title: String
    let startTime: TimeInterval
}

enum VideoLoopMode: String, CaseIterable, Codable {
    case none
    case file
}

struct VideoABLoop: Equatable, Codable {
    let start: TimeInterval
    let end: TimeInterval
}

enum VideoAspectRatio: String, CaseIterable, Codable {
    case automatic = "-1"
    case ratio16x9 = "16:9"
    case ratio4x3 = "4:3"
    case ratio1x1 = "1:1"
    case ratio21x9 = "21:9"

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .ratio16x9: "16:9"
        case .ratio4x3: "4:3"
        case .ratio1x1: "1:1"
        case .ratio21x9: "21:9"
        }
    }
}

struct VideoPlaybackSnapshot: Equatable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var isLoaded = false
    var isSeeking = false
    var speed = 1.0
    var volume = 100.0
    var isMuted = false
    var subtitleDelay: TimeInterval = 0
    var audioDelay: TimeInterval = 0
    var loopMode: VideoLoopMode = .none
    var abLoop: VideoABLoop?
    var aspectRatio: VideoAspectRatio = .automatic
    var rotation = 0
    var tracks: [VideoTrack] = []
    var chapters: [VideoChapter] = []
}

struct VideoAmbientPreview {
    let image: NSImage
    let generation: Int
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var snapshot: VideoPlaybackSnapshot { get }
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onEmbeddedSubtitleCuesChanged: (([VideoEmbeddedSubtitleCue]) -> Void)? {
        get set
    }

    func load(url: URL) throws
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func setSpeed(_ speed: Double)
    func setVolume(_ volume: Double)
    func setMuted(_ muted: Bool)
    func setSubtitleDelay(_ delay: TimeInterval)
    func setAudioDelay(_ delay: TimeInterval)
    func setLoopMode(_ mode: VideoLoopMode)
    func setABLoop(_ loop: VideoABLoop?)
    func setAspectRatio(_ aspectRatio: VideoAspectRatio)
    func setRotation(_ degrees: Int)
    func seekToChapter(_ index: Int)
    func captureAmbientPreview(maximumDimension: Int) async -> VideoAmbientPreview?
    func captureScreenshot(to url: URL) async throws
    func exportAudioClip(from start: TimeInterval, to end: TimeInterval, to url: URL) async throws
    func loadExternalSubtitle(url: URL)
    func selectTrack(type: VideoTrackType, id: Int?)
    func shutdown()
}

extension PlaybackEngine {
    var onError: ((String) -> Void)? {
        get { nil }
        set {}
    }

    var onPlaybackEnded: (() -> Void)? {
        get { nil }
        set {}
    }

    var onEmbeddedSubtitleCuesChanged: (([VideoEmbeddedSubtitleCue]) -> Void)? {
        get { nil }
        set {}
    }

    func setAudioDelay(_ delay: TimeInterval) {}
    func setLoopMode(_ mode: VideoLoopMode) {}
    func setABLoop(_ loop: VideoABLoop?) {}
    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {}
    func setRotation(_ degrees: Int) {}
    func seekToChapter(_ index: Int) {}
    func captureAmbientPreview(maximumDimension: Int) async -> VideoAmbientPreview? { nil }
    func captureScreenshot(to url: URL) async throws {}
    func exportAudioClip(
        from start: TimeInterval,
        to end: TimeInterval,
        to url: URL
    ) async throws {}
    func loadExternalSubtitle(url: URL) {}
}

enum VideoTimeFormatter {
    static func string(from time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
