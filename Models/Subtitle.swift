#if HOSHI_VIDEO
import Foundation

enum SubtitleFormat: String, Codable, Sendable {
    case srt
    case webVTT
    case ass
    case ssa
    case embedded
}

struct SubtitleCue: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct SubtitleDocument: Hashable, Sendable {
    let sourceURL: URL
    let format: SubtitleFormat
    let cues: [SubtitleCue]
    let warnings: [String]
}

struct SubtitleTranscriptRow: Identifiable, Equatable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let primaryText: String
    let secondaryText: String?
}

struct SubtitleTranscript: Sendable {
    let rows: [SubtitleTranscriptRow]
    let changeToken: ChangeToken

    nonisolated init(
        primary: SubtitleDocument?,
        secondary: SubtitleDocument?,
        generation: Int = 0
    ) {
        let secondaryCues = (secondary?.cues ?? []).sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        var secondaryIndex = 0
        let primaryCues = primary?.cues ?? []
        rows = primaryCues.map { cue in
            while secondaryIndex < secondaryCues.count,
                  secondaryCues[secondaryIndex].endTime < cue.startTime {
                secondaryIndex += 1
            }

            var candidateIndex = secondaryIndex
            var bestSecondaryCue: SubtitleCue?
            var bestOverlap: TimeInterval = 0
            while candidateIndex < secondaryCues.count,
                  secondaryCues[candidateIndex].startTime <= cue.endTime {
                let candidate = secondaryCues[candidateIndex]
                let overlap = Self.overlap(candidate, cue)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSecondaryCue = candidate
                }
                candidateIndex += 1
            }

            return SubtitleTranscriptRow(
                id: cue.id,
                startTime: cue.startTime,
                endTime: cue.endTime,
                primaryText: cue.text,
                secondaryText: bestSecondaryCue?.text
            )
        }
        changeToken = ChangeToken(
            generation: generation,
            rowCount: rows.count,
            firstRowID: rows.first?.id,
            lastRowID: rows.last?.id
        )
    }

    func row(containing time: TimeInterval) -> SubtitleTranscriptRow? {
        guard let index = rowIndex(containing: time) else { return nil }
        return rows[index]
    }

    func rowIndex(containing time: TimeInterval) -> Int? {
        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle].startTime <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var index = low - 1
        while index >= 0 {
            let row = rows[index]
            if row.startTime <= time && time <= row.endTime {
                return index
            }
            if row.endTime < time {
                return nil
            }
            index -= 1
        }
        return nil
    }

    func nearestRowIndex(at time: TimeInterval) -> Int? {
        guard !rows.isEmpty else { return nil }
        if let activeIndex = rowIndex(containing: time) {
            return activeIndex
        }

        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if rows[middle].startTime < time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return min(max(low, 0), rows.count - 1)
    }

    func relativeRowIndex(
        atPlaybackTime playbackTime: TimeInterval,
        subtitleDelay: TimeInterval,
        offset: Int
    ) -> Int? {
        guard let currentIndex = nearestRowIndex(
            at: playbackTime - subtitleDelay
        ) else {
            return nil
        }
        let targetIndex = currentIndex + offset
        guard rows.indices.contains(targetIndex) else { return nil }
        return targetIndex
    }

    func rows(in range: Range<Int>) -> ArraySlice<SubtitleTranscriptRow> {
        let lower = min(max(range.lowerBound, 0), rows.count)
        let upper = min(max(range.upperBound, lower), rows.count)
        return rows[lower..<upper]
    }

    nonisolated private static func overlap(_ left: SubtitleCue, _ right: SubtitleCue) -> TimeInterval {
        max(0, min(left.endTime, right.endTime) - max(left.startTime, right.startTime))
    }

    struct ChangeToken: Equatable, Sendable {
        let generation: Int
        let rowCount: Int
        let firstRowID: String?
        let lastRowID: String?
    }
}

struct SubtitleTranscriptWindow: Equatable, Sendable {
    let windowSize: Int
    let extensionSize: Int
    private(set) var visibleRange: Range<Int> = 0..<0

    init(windowSize: Int = 80, extensionSize: Int = 40) {
        self.windowSize = max(1, windowSize)
        self.extensionSize = max(1, extensionSize)
    }

    mutating func reset(rowCount: Int, focusing index: Int) {
        guard rowCount > 0 else {
            visibleRange = 0..<0
            return
        }
        let focus = min(max(index, 0), rowCount - 1)
        let halfWindow = windowSize / 2
        var lower = max(0, focus - halfWindow)
        let upper = min(rowCount, lower + windowSize)
        lower = max(0, upper - windowSize)
        visibleRange = lower..<upper
    }

    mutating func followPlayback(rowCount: Int, focusing index: Int) {
        guard rowCount > 0 else {
            visibleRange = 0..<0
            return
        }
        if visibleRange.isEmpty {
            reset(rowCount: rowCount, focusing: index)
            return
        }
        let focus = min(max(index, 0), rowCount - 1)
        let margin = max(1, min(extensionSize, windowSize / 4))
        if !visibleRange.contains(focus)
            || focus < visibleRange.lowerBound + margin
            || focus >= visibleRange.upperBound - margin {
            reset(rowCount: rowCount, focusing: focus)
        }
    }

    mutating func extendBefore(rowCount: Int) {
        guard rowCount > 0, !visibleRange.isEmpty else { return }
        let lower = max(0, visibleRange.lowerBound - extensionSize)
        visibleRange = lower..<visibleRange.upperBound
    }

    mutating func extendAfter(rowCount: Int) {
        guard rowCount > 0, !visibleRange.isEmpty else { return }
        let upper = min(rowCount, visibleRange.upperBound + extensionSize)
        visibleRange = visibleRange.lowerBound..<upper
    }
}

enum VideoSubtitleAutoloadCandidate {
    private static let supportedExtensions = ["srt", "vtt", "ass", "ssa"]

    static func bestCandidate(
        for mediaURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard mediaURL.isFileURL else { return nil }

        let directory = mediaURL.deletingLastPathComponent()
        let mediaStem = mediaURL.deletingPathExtension().lastPathComponent
        for fileExtension in supportedExtensions {
            let exactURL = directory
                .appendingPathComponent(mediaStem)
                .appendingPathExtension(fileExtension)
            if fileManager.fileExists(atPath: exactURL.path) {
                return exactURL.standardizedFileURL
            }
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents
            .filter { candidate in
                supportedExtensions.contains(candidate.pathExtension.lowercased())
                    && Self.matchesLanguageSuffixedSidecar(candidate, mediaStem: mediaStem)
            }
            .sorted(by: compareCandidateOrder)
            .first?
            .standardizedFileURL
    }

    private static func matchesLanguageSuffixedSidecar(
        _ candidate: URL,
        mediaStem: String
    ) -> Bool {
        let subtitleStem = candidate.deletingPathExtension().lastPathComponent
        return subtitleStem.hasPrefix(mediaStem + ".")
            || subtitleStem.hasPrefix(mediaStem + " ")
    }

    private static func compareCandidateOrder(_ left: URL, _ right: URL) -> Bool {
        let leftExtension = left.pathExtension.lowercased()
        let rightExtension = right.pathExtension.lowercased()
        if leftExtension != rightExtension {
            let leftPriority = supportedExtensions.firstIndex(of: leftExtension) ?? Int.max
            let rightPriority = supportedExtensions.firstIndex(of: rightExtension) ?? Int.max
            return leftPriority < rightPriority
        }
        return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
    }
}

enum SubtitleParserError: LocalizedError {
    case unsupportedFormat
    case noValidCues

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Unsupported subtitle format."
        case .noValidCues:
            "No valid subtitle cues were found."
        }
    }
}
#endif
