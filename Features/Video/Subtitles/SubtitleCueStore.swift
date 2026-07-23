import Foundation

struct SubtitleCueSlice: Equatable, Sendable {
    let showing: [SubtitleCue]
    let lastShown: [SubtitleCue]
    let nextToShow: [SubtitleCue]
}

enum SubtitleOffsetAlignmentDirection: Equatable, Sendable {
    case previous
    case next
}

struct SubtitleCueStore: Sendable {
    let document: SubtitleDocument
    private let timedCues: [SubtitleCue]
    private let longCues: [SubtitleCue]
    private let cuesByStart: [SubtitleCue]
    private let cuesByEnd: [SubtitleCue]
    private let maxTimedCueDuration: TimeInterval
    nonisolated private static let longCueThreshold: TimeInterval = 30

    nonisolated init(document: SubtitleDocument) {
        self.document = document
        let sortedCues = document.cues.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        var timedCues: [SubtitleCue] = []
        var longCues: [SubtitleCue] = []
        var maxTimedCueDuration: TimeInterval = 0

        for cue in sortedCues {
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
        self.cuesByStart = sortedCues
        self.cuesByEnd = sortedCues.sorted {
            if $0.endTime == $1.endTime {
                return $0.startTime < $1.startTime
            }
            return $0.endTime < $1.endTime
        }
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

    func slice(
        atPlaybackTime time: TimeInterval,
        subtitleDelay: TimeInterval
    ) -> SubtitleCueSlice {
        slice(at: time - subtitleDelay)
    }

    func slice(at time: TimeInterval) -> SubtitleCueSlice {
        SubtitleCueSlice(
            showing: cues(at: time),
            lastShown: latestCuesEnding(before: time),
            nextToShow: earliestCuesStarting(after: time)
        )
    }

    func delayAligningAdjacentCue(
        atPlaybackTime playbackTime: TimeInterval,
        subtitleDelay: TimeInterval,
        direction: SubtitleOffsetAlignmentDirection
    ) -> TimeInterval? {
        let adjacentCues = switch direction {
        case .previous:
            slice(
                atPlaybackTime: playbackTime,
                subtitleDelay: subtitleDelay
            ).lastShown
        case .next:
            slice(
                atPlaybackTime: playbackTime,
                subtitleDelay: subtitleDelay
            ).nextToShow
        }
        let cue = direction == .previous ? adjacentCues.last : adjacentCues.first
        guard let cue else { return nil }
        return playbackTime - cue.startTime
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

    private func latestCuesEnding(before time: TimeInterval) -> [SubtitleCue] {
        var low = 0
        var high = cuesByEnd.count
        while low < high {
            let middle = (low + high) / 2
            if cuesByEnd[middle].endTime < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let lastIndex = low - 1
        guard lastIndex >= 0 else { return [] }
        let endTime = cuesByEnd[lastIndex].endTime
        var index = lastIndex
        var result: [SubtitleCue] = []
        while index >= 0, cuesByEnd[index].endTime == endTime {
            result.append(cuesByEnd[index])
            index -= 1
        }
        return result.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
    }

    private func earliestCuesStarting(after time: TimeInterval) -> [SubtitleCue] {
        var low = 0
        var high = cuesByStart.count
        while low < high {
            let middle = (low + high) / 2
            if cuesByStart[middle].startTime <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < cuesByStart.count else { return [] }
        let startTime = cuesByStart[low].startTime
        var index = low
        var result: [SubtitleCue] = []
        while index < cuesByStart.count, cuesByStart[index].startTime == startTime {
            result.append(cuesByStart[index])
            index += 1
        }
        return result
    }
}
