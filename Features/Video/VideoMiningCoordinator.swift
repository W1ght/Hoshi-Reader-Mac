#if HOSHI_VIDEO
import Foundation

enum VideoMiningCoordinator {
    @MainActor
    static func context(
        cue: SubtitleCue,
        document: SubtitleDocument?,
        videoURL: URL,
        engine: any PlaybackEngine,
        captureScreenshot: Bool,
        captureAudioClip: Bool,
        mediaStore: VideoMiningMediaStore = VideoMiningMediaStore()
    ) async -> MiningContext {
        let cues = document?.cues ?? []
        let index = cues.firstIndex(where: { $0.id == cue.id })
        let previous = index.flatMap { $0 > 0 ? cues[$0 - 1].text : nil }
        let next = index.flatMap { $0 + 1 < cues.count ? cues[$0 + 1].text : nil }
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
                cueStart: cue.startTime,
                cueEnd: cue.endTime,
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
            sentence: cue.text,
            documentTitle: videoURL.lastPathComponent,
            coverURL: nil,
            video: VideoMiningContext(
                fileName: videoURL.lastPathComponent,
                cueText: cue.text,
                cueStart: cue.startTime,
                cueEnd: cue.endTime,
                previousCueText: previous,
                nextCueText: next,
                screenshotURL: screenshotURL,
                audioClipURL: audioClipURL,
                audioClipErrorMessage: audioClipErrorMessage
            )
        )
    }
}
#endif
