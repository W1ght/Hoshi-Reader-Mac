import Foundation

struct MiningContextMediaRange: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
}

struct MiningContextSentence: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    var targetUTF16Range: NSRange? = nil
    var mediaRange: MiningContextMediaRange? = nil
}

struct MiningContextSelectionResult: Equatable, Sendable {
    let sentences: [MiningContextSentence]
    let currentSentenceIndex: Int
    let previousSentence: MiningContextSentence?
    let nextSentence: MiningContextSentence?

    var sentence: String {
        sentences.map(\.text).joined(separator: "\n")
    }

    var currentSentence: MiningContextSentence {
        sentences[currentSentenceIndex]
    }

    var mediaRange: MiningContextMediaRange? {
        let timed = sentences.compactMap(\.mediaRange)
        guard let first = timed.first else { return nil }
        return MiningContextMediaRange(
            start: timed.dropFirst().reduce(first.start) { min($0, $1.start) },
            end: timed.dropFirst().reduce(first.end) { max($0, $1.end) }
        )
    }
}

struct MiningContextSelection: Equatable, Sendable {
    private(set) var sentences: [MiningContextSentence]
    let currentIndex: Int
    private(set) var lowerBound: Int
    private(set) var upperBound: Int

    init(sentences: [MiningContextSentence], currentIndex: Int) {
        precondition(!sentences.isEmpty, "Mining context requires at least one sentence")
        let safeIndex = min(max(currentIndex, sentences.startIndex), sentences.index(before: sentences.endIndex))
        self.sentences = sentences
        self.currentIndex = safeIndex
        lowerBound = safeIndex
        upperBound = safeIndex
    }

    static func text(
        _ text: String,
        targetUTF16Location: Int?,
        mediaRange: MiningContextMediaRange? = nil
    ) -> MiningContextSelection {
        let sentence = MiningContextSentence(
            id: "current",
            text: text,
            targetUTF16Range: targetUTF16Location.map { NSRange(location: max(0, $0), length: 0) },
            mediaRange: mediaRange
        )
        return MiningContextSelection(sentences: [sentence], currentIndex: 0)
    }

    static func timedSentences<Cue>(
        from cues: [Cue],
        currentID: String,
        targetUTF16Location: Int?,
        id: (Cue) -> String,
        text: (Cue) -> String,
        mediaRange: (Cue) -> MiningContextMediaRange?
    ) -> MiningContextSelection? {
        let sentences = cues.compactMap { cue -> MiningContextSentence? in
            let cueText = text(cue)
            guard !cueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let cueID = id(cue)
            return MiningContextSentence(
                id: cueID,
                text: cueText,
                targetUTF16Range: cueID == currentID
                    ? targetUTF16Location.map { NSRange(location: max(0, $0), length: 0) }
                    : nil,
                mediaRange: mediaRange(cue)
            )
        }
        guard let currentIndex = sentences.firstIndex(where: { $0.id == currentID }) else {
            return nil
        }
        return MiningContextSelection(sentences: sentences, currentIndex: currentIndex)
    }

    static func decode(_ payload: Any?) -> MiningContextSelection? {
        guard let payload = payload as? [String: Any],
              let rawSentences = payload["sentences"] as? [[String: Any]] else {
            return nil
        }
        let sentences = rawSentences.enumerated().compactMap { index, raw -> MiningContextSentence? in
            guard let text = raw["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let targetRange = (raw["targetLocation"] as? NSNumber).map {
                NSRange(location: max(0, $0.intValue), length: 0)
            }
            return MiningContextSentence(
                id: raw["id"] as? String ?? String(index),
                text: text,
                targetUTF16Range: targetRange
            )
        }
        guard !sentences.isEmpty else { return nil }
        let currentIndex = (payload["currentIndex"] as? NSNumber)?.intValue
            ?? (payload["currentIndex"] as? Int)
            ?? 0
        return MiningContextSelection(sentences: sentences, currentIndex: currentIndex)
    }

    var selectedRange: ClosedRange<Int> {
        lowerBound...upperBound
    }

    var canAddPrevious: Bool { lowerBound > sentences.startIndex }
    var canRemovePrevious: Bool { lowerBound < currentIndex }
    var canAddNext: Bool { upperBound < sentences.index(before: sentences.endIndex) }
    var canRemoveNext: Bool { upperBound > currentIndex }

    mutating func addPrevious() {
        guard canAddPrevious else { return }
        lowerBound -= 1
    }

    mutating func removePrevious() {
        guard canRemovePrevious else { return }
        lowerBound += 1
    }

    mutating func addNext() {
        guard canAddNext else { return }
        upperBound += 1
    }

    mutating func removeNext() {
        guard canRemoveNext else { return }
        upperBound -= 1
    }

    mutating func setCurrentTargetUTF16Length(_ length: Int) {
        guard length > 0,
              let range = sentences[currentIndex].targetUTF16Range else { return }
        sentences[currentIndex].targetUTF16Range = NSRange(
            location: range.location,
            length: length
        )
    }

    var result: MiningContextSelectionResult {
        let selected = Array(sentences[selectedRange])
        return MiningContextSelectionResult(
            sentences: selected,
            currentSentenceIndex: currentIndex - lowerBound,
            previousSentence: lowerBound > sentences.startIndex ? sentences[lowerBound - 1] : nil,
            nextSentence: upperBound < sentences.index(before: sentences.endIndex) ? sentences[upperBound + 1] : nil
        )
    }
}
