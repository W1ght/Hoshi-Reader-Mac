#if HOSHI_VIDEO
import Foundation

enum MpvPlayerEngineError: LocalizedError {
    case initializationFailed(String)
    case mediaExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            message
        case .mediaExportFailed(let message):
            message
        }
    }
}

@MainActor
final class MpvPlayerEngine: PlaybackEngine {
    private let client: HSMpvClient?
    private let initializationError: String?
    private weak var attachedRenderView: HSMpvOpenGLView?
    private var loadedURL: URL?
    private(set) var snapshot = VideoPlaybackSnapshot()
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onEmbeddedSubtitleCuesChanged: (([VideoEmbeddedSubtitleCue]) -> Void)?

    init() {
        var errorMessage: NSString?
        client = HSMpvClient.make(errorMessage: &errorMessage)
        initializationError = errorMessage as String?
        client?.stateHandler = {
            [weak self] currentTime,
            duration,
            playing,
            loaded,
            speed,
            volume,
            muted,
            subtitleDelay,
            audioDelay,
            loopMode,
            abLoopStart,
            abLoopEnd,
            aspectRatio,
            rotation,
            videoWidth,
            videoHeight,
            errorMessage in
            guard let self else { return }
            snapshot = VideoPlaybackSnapshot(
                currentTime: currentTime,
                duration: duration,
                isPlaying: playing,
                isLoaded: loaded,
                speed: speed,
                volume: volume,
                isMuted: muted,
                subtitleDelay: subtitleDelay,
                audioDelay: audioDelay,
                loopMode: VideoLoopMode(rawValue: loopMode) ?? .none,
                abLoop: abLoopStart.isFinite && abLoopEnd.isFinite
                    ? VideoABLoop(start: abLoopStart, end: abLoopEnd)
                    : nil,
                aspectRatio: VideoAspectRatio(rawValue: aspectRatio) ?? .automatic,
                rotation: rotation,
                videoDisplaySize: videoWidth > 0 && videoHeight > 0
                    ? CGSize(width: videoWidth, height: videoHeight)
                    : nil,
                tracks: snapshot.tracks,
                chapters: snapshot.chapters
            )
            onSnapshotChanged?(snapshot)
            if let errorMessage {
                onError?(errorMessage)
            }
        }
        client?.trackHandler = { [weak self] tracks in
            guard let self else { return }
            snapshot.tracks = tracks.compactMap { track in
                let rawType = track.type == "sub" ? "subtitle" : track.type
                guard let type = VideoTrackType(rawValue: rawType) else {
                    return nil
                }
                return VideoTrack(
                    id: track.trackID,
                    type: type,
                    title: track.title,
                    language: track.language,
                    codec: track.codec,
                    ffIndex: track.ffIndex >= 0 ? track.ffIndex : nil,
                    externalFilename: track.externalFilename,
                    isImage: track.isImage,
                    isSelected: track.isSelected
                )
            }
            onSnapshotChanged?(snapshot)
        }
        client?.chapterHandler = { [weak self] chapters in
            guard let self else { return }
            snapshot.chapters = chapters.map {
                VideoChapter(
                    id: $0.chapterID,
                    title: $0.title,
                    startTime: $0.startTime
                )
            }
            onSnapshotChanged?(snapshot)
        }
        client?.subtitleCueHandler = { [weak self] cues in
            self?.onEmbeddedSubtitleCuesChanged?(cues.map {
                VideoEmbeddedSubtitleCue(
                    id: $0.cueID,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    text: $0.text
                )
            })
        }
        client?.playbackEndedHandler = { [weak self] in
            self?.onPlaybackEnded?()
        }
    }

    isolated deinit {
        client?.shutdown()
    }

    @discardableResult
    func attach(to view: HSMpvOpenGLView) -> Bool {
        if attachedRenderView === view { return true }
        guard let client, client.attach(to: view) else { return false }
        attachedRenderView = view
        return true
    }

    func detachRenderView() {
        attachedRenderView = nil
        client?.detachFromView()
    }

    func load(url: URL) throws {
        guard let client else {
            throw MpvPlayerEngineError.initializationFailed(
                initializationError ?? "Unable to initialize video playback."
            )
        }
        loadedURL = url
        snapshot.currentTime = 0
        snapshot.duration = 0
        snapshot.isPlaying = false
        snapshot.isLoaded = false
        snapshot.tracks = []
        snapshot.chapters = []
        onSnapshotChanged?(snapshot)
        client.loadFile(url)
    }

    func play() {
        client?.setPaused(false)
    }

    func pause() {
        client?.setPaused(true)
    }

    func seek(to time: TimeInterval) {
        client?.seek(to: time)
    }

    func setSpeed(_ speed: Double) {
        client?.setSpeed(speed)
    }

    func setVolume(_ volume: Double) {
        client?.setVolume(volume)
    }

    func setMuted(_ muted: Bool) {
        client?.setMuted(muted)
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        client?.setSubtitleDelay(delay)
    }

    func setAudioDelay(_ delay: TimeInterval) {
        client?.setAudioDelay(delay)
    }

    func setLoopMode(_ mode: VideoLoopMode) {
        client?.setLoopMode(mode.rawValue)
    }

    func setABLoop(_ loop: VideoABLoop?) {
        client?.setABLoopStart(
            loop.map { NSNumber(value: $0.start) },
            end: loop.map { NSNumber(value: $0.end) }
        )
    }

    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {
        client?.setAspectRatio(aspectRatio.rawValue)
    }

    func setRotation(_ degrees: Int) {
        client?.setRotation(degrees)
    }

    func setHardwareDecodingEnabled(_ enabled: Bool) {
        client?.setHardwareDecodingEnabled(enabled)
    }

    func setDeinterlacingEnabled(_ enabled: Bool) {
        client?.setDeinterlacingEnabled(enabled)
    }

    func setHDREnhancementEnabled(_ enabled: Bool) {
        client?.setHDREnhancementEnabled(enabled)
    }

    func setVideoEqualizer(_ adjustment: VideoEqualizerAdjustment, value: Double) {
        client?.setVideoEqualizer(adjustment.rawValue, value: value)
    }

    func seekToChapter(_ index: Int) {
        client?.seek(toChapter: index)
    }

    func captureAmbientPreview(maximumDimension: Int) async -> VideoAmbientPreview? {
        guard let client else { return nil }
        return await withCheckedContinuation { continuation in
            client.captureAmbientPreview(withMaximumDimension: maximumDimension) { image, generation in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: VideoAmbientPreview(
                        image: image,
                        generation: generation
                    )
                )
            }
        }
    }

    func captureScreenshot(to url: URL) async throws {
        var errorMessage: NSString?
        guard client?.captureScreenshot(to: url, errorMessage: &errorMessage) == true else {
            throw MpvPlayerEngineError.mediaExportFailed(
                errorMessage as String? ?? "Unable to capture the video frame."
            )
        }
    }

    func exportAudioClip(
        from start: TimeInterval,
        to end: TimeInterval,
        to url: URL
    ) async throws {
        guard let loadedURL else {
            throw MpvPlayerEngineError.mediaExportFailed(
                "Unable to determine the video audio range."
            )
        }
        try await VideoAudioClipExporter.export(
            sourceURL: loadedURL,
            from: start,
            to: end,
            audioTrackID: snapshot.tracks.first(where: {
                $0.type == .audio && $0.isSelected
            })?.id,
            outputURL: url
        )
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        client?.selectTrackType(type.rawValue, trackID: id.map(NSNumber.init(value:)))
    }

    func loadExternalSubtitle(url: URL) {
        client?.loadExternalSubtitle(url)
    }

    func shutdown() {
        client?.shutdown()
    }
}
#endif
