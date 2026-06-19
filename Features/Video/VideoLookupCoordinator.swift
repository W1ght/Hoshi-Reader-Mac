#if HOSHI_VIDEO
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
        if presentation.popups.isEmpty {
            shouldResumePlayback = player.snapshot.isPlaying
            if shouldResumePlayback {
                player.engine.pause()
            }
        }
        videoLookupLog.info(
            "Presenting video lookup popup replacing=\(replacingExisting) popups=\(self.presentation.popups.count) wasPlaying=\(self.shouldResumePlayback)"
        )
        return presentation.present(
            selection: selection,
            userConfig: userConfig,
            replacingExisting: replacingExisting
        )
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
            runPendingCloseCompletions()
            return
        }

        isClosingPopupStack = true
        videoLookupLog.info(
            "Closing video lookup popup stack count=\(self.presentation.popups.count) shouldResume=\(self.shouldResumePlayback)"
        )
        presentation.closeAll {
            if self.shouldResumePlayback {
                player.engine.play()
            }
            self.activeCue = nil
            self.shouldResumePlayback = false
            self.isClosingPopupStack = false
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
            if self.shouldResumePlayback {
                player.engine.play()
            }
            self.activeCue = nil
            self.shouldResumePlayback = false
        }
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
#endif
