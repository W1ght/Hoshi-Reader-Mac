#if HOSHI_VIDEO
import Foundation

struct SubtitleCueStore: Sendable {
    let document: SubtitleDocument
    private let timedCues: [SubtitleCue]
    private let longCues: [SubtitleCue]
    private let maxTimedCueDuration: TimeInterval
    nonisolated private static let longCueThreshold: TimeInterval = 30

    nonisolated init(document: SubtitleDocument) {
        self.document = document
        var timedCues: [SubtitleCue] = []
        var longCues: [SubtitleCue] = []
        var maxTimedCueDuration: TimeInterval = 0

        for cue in document.cues {
            let duration = cue.endTime - cue.startTime
            if duration > Self.longCueThreshold {
                longCues.append(cue)
            } else {
                timedCues.append(cue)
                maxTimedCueDuration = max(maxTimedCueDuration, duration)
            }
        }

        self.timedCues = timedCues
        self.longCues = longCues
        self.maxTimedCueDuration = maxTimedCueDuration
    }

    func cues(at time: TimeInterval) -> [SubtitleCue] {
        var matches = longCues.filter {
            $0.startTime <= time && time <= $0.endTime
        }

        var index = firstTimedCueStarting(after: time) - 1
        let earliestPossibleStart = time - maxTimedCueDuration
        while index >= 0 {
            let cue = timedCues[index]
            if cue.startTime < earliestPossibleStart {
                break
            }
            if time <= cue.endTime {
                matches.append(cue)
            }
            index -= 1
        }

        return matches.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
    }

    func cues(
        atPlaybackTime time: TimeInterval,
        subtitleDelay: TimeInterval
    ) -> [SubtitleCue] {
        cues(at: time - subtitleDelay)
    }

    private func firstTimedCueStarting(after time: TimeInterval) -> Int {
        var low = 0
        var high = timedCues.count
        while low < high {
            let middle = (low + high) / 2
            if timedCues[middle].startTime <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
#endif
