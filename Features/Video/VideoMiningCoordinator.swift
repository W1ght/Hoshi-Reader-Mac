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
            let shouldGenerateScreenshot = captureScreenshot
            let shouldGenerateAudioClip = captureAudioClip && audioRange != nil
            if captureScreenshot {
                screenshotFilename = filenames.screenshot
            }
            if captureAudioClip {
                if audioRange != nil {
                    audioClipFilename = filenames.audioClip
                } else {
                    audioClipErrorMessage = String(
                        localized: "Unable to capture the subtitle audio clip."
                    )
                    print("Video audio clip export skipped: invalid subtitle range")
                }
            }
            if shouldGenerateScreenshot || shouldGenerateAudioClip {
                await suspendVideoThumbnailsForMining()
                Task { @MainActor in
                    if shouldGenerateScreenshot {
                        let destination = mediaStore.directMediaURL(
                            filename: filenames.screenshot,
                            in: ankiMediaDirectory
                        )
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
                    if shouldGenerateAudioClip, let audioRange {
                        let destination = mediaStore.directMediaURL(
                            filename: filenames.audioClip,
                            in: ankiMediaDirectory
                        )
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
                    await resumeVideoThumbnailsForMining()
                }
            }
        } else {
            if captureScreenshot || captureAudioClip {
                await suspendVideoThumbnailsForMining()
            }
            defer {
                if captureScreenshot || captureAudioClip {
                    Task {
                        await resumeVideoThumbnailsForMining()
                    }
                }
            }
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

    private static func suspendVideoThumbnailsForMining() async {
        await VideoThumbnailScheduler.shared.suspend(reason: .mining)
    }

    private static func resumeVideoThumbnailsForMining() async {
        await VideoThumbnailScheduler.shared.resume(reason: .mining)
    }
}
#endif
