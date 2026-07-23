import Foundation

enum VideoMiningContextSelectionBuilder {
    static func build(
        cues: [SubtitleCue],
        currentCueID: String,
        targetUTF16Location: Int
    ) -> MiningContextSelection? {
        let usableCues = cues.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let currentIndex = usableCues.firstIndex(where: { $0.id == currentCueID }) else {
            return nil
        }
        let sentences = usableCues.map { cue in
            MiningContextSentence(
                id: cue.id,
                text: cue.text,
                targetUTF16Range: cue.id == currentCueID
                    ? NSRange(location: max(0, targetUTF16Location), length: 0)
                    : nil,
                mediaRange: MiningContextMediaRange(start: cue.startTime, end: cue.endTime)
            )
        }
        return MiningContextSelection(sentences: sentences, currentIndex: currentIndex)
    }
}
