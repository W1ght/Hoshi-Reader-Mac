import Foundation

enum VideoMiningCoordinator {
    @MainActor
    static func context(
        cue: SubtitleCue,
        selectedContext: MiningContextSelectionResult? = nil,
        document: SubtitleDocument?,
        videoURL: URL,
        videoTitle: String,
        mediaIdentity: VideoMediaIdentity,
        engine: any PlaybackEngine,
        captureScreenshot: Bool,
        compressScreenshot: Bool,
        screenshotQuality: Double = 0.80,
        captureAudioClip: Bool,
        audioFormat: AnkiAudioCompressionFormat = .aac,
        audioBitrateKbps: Int = 64,
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
        let screenshotFormat: VideoScreenshotFormat = compressScreenshot ? .jpeg : .png

        if let ankiMediaDirectory {
            let filenames = VideoMiningContext.deterministicMediaFilenames(
                identityKey: mediaIdentity.persistenceKey,
                cueStart: resolution.cueStart,
                cueEnd: resolution.cueEnd,
                audioStart: audioRange?.start ?? resolution.cueStart,
                audioEnd: audioRange?.end ?? resolution.cueEnd,
                screenshotFormat: screenshotFormat,
                screenshotQuality: screenshotQuality,
                audioFormat: audioFormat,
                audioBitrateKbps: audioBitrateKbps
            )
            let screenshotDestination = mediaStore.directMediaURL(
                filename: filenames.screenshot,
                in: ankiMediaDirectory
            )
            let audioDestination = mediaStore.directMediaURL(
                filename: filenames.audioClip,
                in: ankiMediaDirectory
            )
            let shouldGenerateScreenshot = captureScreenshot
                && mediaStore.claimDirectMediaGeneration(at: screenshotDestination)
            let shouldGenerateAudioClip = captureAudioClip
                && audioRange != nil
                && mediaStore.claimDirectMediaGeneration(at: audioDestination)
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
                        let tempURL = mediaStore.screenshotURL()
                        do {
                            try await engine.captureScreenshot(to: tempURL)
                            let preparedURL = try mediaStore.preparedScreenshot(
                                at: tempURL,
                                compress: compressScreenshot,
                                quality: screenshotQuality
                            )
                            try mediaStore.replaceMediaItem(
                                at: preparedURL,
                                destination: screenshotDestination
                            )
                        } catch {
                            print("Video screenshot capture failed: \(error)")
                        }
                        mediaStore.finishDirectMediaGeneration(at: screenshotDestination)
                    }
                    if shouldGenerateAudioClip, let audioRange {
                        let tempURL = mediaStore.audioClipURL()
                        do {
                            try await engine.exportAudioClip(
                                from: audioRange.start,
                                to: audioRange.end,
                                to: tempURL
                            )
                            let preparedURL = try await mediaStore.preparedAudioClip(
                                at: tempURL,
                                format: audioFormat,
                                bitrateKbps: audioBitrateKbps
                            )
                            try mediaStore.replaceMediaItem(
                                at: preparedURL,
                                destination: audioDestination
                            )
                        } catch {
                            print("Video audio clip export failed: \(error)")
                        }
                        mediaStore.finishDirectMediaGeneration(at: audioDestination)
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
                do {
                    try await engine.captureScreenshot(to: url)
                    screenshotURL = try mediaStore.preparedScreenshot(
                        at: url,
                        compress: compressScreenshot,
                        quality: screenshotQuality
                    )
                } catch {
                    print("Video screenshot capture failed: \(error)")
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
                        audioClipURL = try await mediaStore.preparedAudioClip(
                            at: url,
                            format: audioFormat,
                            bitrateKbps: audioBitrateKbps
                        )
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
            documentTitle: videoTitle,
            coverURL: nil,
            video: VideoMiningContext(
                fileName: videoTitle,
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
