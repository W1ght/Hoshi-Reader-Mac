import Foundation
import Observation
import OSLog

private let videoLookupLog = Logger(subsystem: "moe.shishamo.hoshi", category: "VideoLookup")

@Observable
@MainActor
final class VideoLookupCoordinator {
    let presentation = PopupPresentationCoordinator()
    private(set) var activeCue: SubtitleCue?
    private var shouldResumePlayback = false
    @ObservationIgnored private var isThumbnailLookupSuspended = false
    @ObservationIgnored private var isClosingPopupStack = false
    @ObservationIgnored private var pendingCloseCompletions: [() -> Void] = []

    func present(
        selection: SelectionData,
        cue: SubtitleCue? = nil,
        player: VideoPlayerViewModel,
        userConfig: UserConfig,
        replacingExisting: Bool = false
    ) -> Int? {
        if let cue {
            activeCue = cue
        }
        let wasPopupStackEmpty = presentation.popups.isEmpty
        let matchedLength = presentation.present(
            selection: selection,
            userConfig: userConfig,
            replacingExisting: replacingExisting
        )

        guard let matchedLength else {
            if presentation.popups.isEmpty {
                resumePlaybackAfterPopupIfNeeded(player: player)
                activeCue = nil
                resumeVideoThumbnailsForLookupIfNeeded()
            }
            return nil
        }

        if wasPopupStackEmpty {
            if userConfig.videoAutoPauseOnLookup {
                shouldResumePlayback = player.snapshot.isPlaying
                if shouldResumePlayback {
                    player.engine.pause()
                }
            } else {
                shouldResumePlayback = false
            }
        }
        suspendVideoThumbnailsForLookupIfNeeded()
        videoLookupLog.info(
            "Presenting video lookup popup replacing=\(replacingExisting) popups=\(self.presentation.popups.count) wasPlaying=\(self.shouldResumePlayback)"
        )
        return matchedLength
    }

    func closeAll(player: VideoPlayerViewModel, completion: (() -> Void)? = nil) {
        if let completion {
            pendingCloseCompletions.append(completion)
        }

        if isClosingPopupStack {
            videoLookupLog.info(
                "Ignoring reentrant closeAll while close animation is active pending=\(self.pendingCloseCompletions.count)"
            )
            return
        }

        guard !presentation.popups.isEmpty else {
            resumePlaybackAfterPopupIfNeeded(player: player)
            resumeVideoThumbnailsForLookupIfNeeded()
            runPendingCloseCompletions()
            return
        }

        isClosingPopupStack = true
        videoLookupLog.info(
            "Closing video lookup popup stack count=\(self.presentation.popups.count) shouldResume=\(self.shouldResumePlayback)"
        )
        presentation.closeAll {
            self.resumePlaybackAfterPopupIfNeeded(player: player)
            self.activeCue = nil
            self.isClosingPopupStack = false
            self.resumeVideoThumbnailsForLookupIfNeeded()
            self.videoLookupLogCloseCompleted()
            self.runPendingCloseCompletions()
        }
    }

    func dismiss(id: UUID, player: VideoPlayerViewModel) {
        guard !isClosingPopupStack else {
            videoLookupLog.info("Ignoring dismiss while close animation is active")
            return
        }
        presentation.dismiss(id: id) {
            guard self.presentation.popups.isEmpty else {
                return
            }
            self.resumePlaybackAfterPopupIfNeeded(player: player)
            self.activeCue = nil
            self.resumeVideoThumbnailsForLookupIfNeeded()
        }
    }

    private func suspendVideoThumbnailsForLookupIfNeeded() {
        guard !isThumbnailLookupSuspended else { return }
        isThumbnailLookupSuspended = true
        Task {
            await VideoThumbnailScheduler.shared.suspend(reason: .lookup)
        }
    }

    private func resumeVideoThumbnailsForLookupIfNeeded() {
        guard isThumbnailLookupSuspended else { return }
        isThumbnailLookupSuspended = false
        Task {
            await VideoThumbnailScheduler.shared.resume(reason: .lookup)
        }
    }

    private func resumePlaybackAfterPopupIfNeeded(player: VideoPlayerViewModel) {
        if shouldResumePlayback {
            player.engine.play()
        }
        shouldResumePlayback = false
    }

    private func runPendingCloseCompletions() {
        guard !pendingCloseCompletions.isEmpty else { return }
        let completions = pendingCloseCompletions
        pendingCloseCompletions.removeAll()
        videoLookupLog.info("Running video lookup close completions count=\(completions.count)")
        completions.forEach { $0() }
    }

    private func videoLookupLogCloseCompleted() {
        videoLookupLog.info("Finished closing video lookup popup stack")
    }
}
