#if HOSHI_VIDEO
import Foundation

enum VideoMiningCoordinator {
    @MainActor
    static func context(
        cue: SubtitleCue,
        selectedContext: MiningContextSelectionResult? = nil,
        document: SubtitleDocument?,
        videoURL: URL,
        engine: any PlaybackEngine,
        captureScreenshot: Bool,
        captureAudioClip: Bool,
        mediaStore: VideoMiningMediaStore = VideoMiningMediaStore()
    ) async -> MiningContext {
        let cues = document?.cues ?? []
        let resolution = VideoMiningSelectionResolution.resolve(
            cue: cue,
            cues: cues,
            selectedContext: selectedContext
        )
        var screenshotURL: URL?
        if captureScreenshot {
            let url = mediaStore.screenshotURL()
            if (try? await engine.captureScreenshot(to: url)) != nil {
                screenshotURL = url
            }
        }
        var audioClipURL: URL?
        var audioClipErrorMessage: String?
        if captureAudioClip {
            let snapshot = engine.snapshot
            if let range = VideoAudioClipRange.resolve(
                cueStart: resolution.cueStart,
                cueEnd: resolution.cueEnd,
                subtitleDelay: snapshot.subtitleDelay,
                duration: snapshot.duration
            ) {
                let url = mediaStore.audioClipURL()
                do {
                    try await engine.exportAudioClip(
                        from: range.start,
                        to: range.end,
                        to: url
                    )
                    audioClipURL = url
                } catch {
                    audioClipErrorMessage = String(
                        localized: "Unable to capture the subtitle audio clip."
                    )
                }
            } else {
                audioClipErrorMessage = String(
                    localized: "Unable to capture the subtitle audio clip."
                )
            }
        }
        return MiningContext(
            sentence: resolution.sentence,
            documentTitle: videoURL.lastPathComponent,
            coverURL: nil,
            video: VideoMiningContext(
                fileName: videoURL.lastPathComponent,
                cueText: resolution.cueText,
                cueStart: resolution.cueStart,
                cueEnd: resolution.cueEnd,
                previousCueText: resolution.previousCueText,
                nextCueText: resolution.nextCueText,
                screenshotURL: screenshotURL,
                audioClipURL: audioClipURL,
                audioClipErrorMessage: audioClipErrorMessage
            )
        )
    }
}
#endif
