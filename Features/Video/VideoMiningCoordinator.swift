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
        ankiMediaDirectory: URL? = nil,
        mediaStore: VideoMiningMediaStore = VideoMiningMediaStore()
    ) async -> MiningContext {
        let cues = document?.cues ?? []
        let resolution = VideoMiningSelectionResolution.resolve(
            cue: cue,
            cues: cues,
            selectedContext: selectedContext
        )
        let snapshot = engine.snapshot
        let audioRange = VideoAudioClipRange.resolve(
            cueStart: resolution.cueStart,
            cueEnd: resolution.cueEnd,
            subtitleDelay: snapshot.subtitleDelay,
            duration: snapshot.duration
        )
        var screenshotFilename: String?
        var audioClipFilename: String?
        var screenshotURL: URL?
        var audioClipURL: URL?
        var audioClipErrorMessage: String?

        if let ankiMediaDirectory {
            let filenames = VideoMiningContext.deterministicMediaFilenames(
                videoURL: videoURL,
                cueStart: resolution.cueStart,
                cueEnd: resolution.cueEnd,
                audioStart: audioRange?.start ?? resolution.cueStart,
                audioEnd: audioRange?.end ?? resolution.cueEnd
            )
            if captureScreenshot {
                screenshotFilename = filenames.screenshot
                let destination = mediaStore.directMediaURL(
                    filename: filenames.screenshot,
                    in: ankiMediaDirectory
                )
                Task { @MainActor in
                    let tempURL = mediaStore.screenshotURL()
                    do {
                        try await engine.captureScreenshot(to: tempURL)
                        try mediaStore.replaceMediaItem(
                            at: tempURL,
                            destination: destination
                        )
                    } catch {
                        print("Video screenshot capture failed: \(error)")
                    }
                }
            }
            if captureAudioClip {
                audioClipFilename = filenames.audioClip
                if let audioRange {
                    let destination = mediaStore.directMediaURL(
                        filename: filenames.audioClip,
                        in: ankiMediaDirectory
                    )
                    Task { @MainActor in
                        let tempURL = mediaStore.audioClipURL()
                        do {
                            try await engine.exportAudioClip(
                                from: audioRange.start,
                                to: audioRange.end,
                                to: tempURL
                            )
                            try mediaStore.replaceMediaItem(
                                at: tempURL,
                                destination: destination
                            )
                        } catch {
                            print("Video audio clip export failed: \(error)")
                        }
                    }
                } else {
                    print("Video audio clip export skipped: invalid subtitle range")
                }
            }
        } else {
            if captureScreenshot {
                let url = mediaStore.screenshotURL()
                if (try? await engine.captureScreenshot(to: url)) != nil {
                    screenshotURL = url
                }
            }
            if captureAudioClip {
                if let range = audioRange {
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
                screenshotFilename: screenshotFilename,
                audioClipFilename: audioClipFilename,
                screenshotURL: screenshotURL,
                audioClipURL: audioClipURL,
                audioClipErrorMessage: audioClipErrorMessage
            )
        )
    }
}
#endif
