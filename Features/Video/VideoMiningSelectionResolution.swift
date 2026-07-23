import Foundation

struct VideoMiningSelectionResolution: Equatable {
    let sentence: String
    let cueText: String
    let cueStart: TimeInterval
    let cueEnd: TimeInterval
    let previousCueText: String?
    let nextCueText: String?

    static func resolve(
        cue: SubtitleCue,
        cues: [SubtitleCue],
        selectedContext: MiningContextSelectionResult?
    ) -> VideoMiningSelectionResolution {
        let index = cues.firstIndex(where: { $0.id == cue.id })
        let selectedMediaRange = selectedContext?.mediaRange
        let usesTimedContext = selectedMediaRange != nil
        return VideoMiningSelectionResolution(
            sentence: selectedContext?.sentence ?? cue.text,
            cueText: usesTimedContext ? (selectedContext?.sentence ?? cue.text) : cue.text,
            cueStart: selectedMediaRange?.start ?? cue.startTime,
            cueEnd: selectedMediaRange?.end ?? cue.endTime,
            previousCueText: usesTimedContext
                ? selectedContext?.previousSentence?.text
                : index.flatMap { $0 > 0 ? cues[$0 - 1].text : nil },
            nextCueText: usesTimedContext
                ? selectedContext?.nextSentence?.text
                : index.flatMap { $0 + 1 < cues.count ? cues[$0 + 1].text : nil }
        )
    }
}
