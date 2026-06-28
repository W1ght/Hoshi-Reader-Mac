#if HOSHI_VIDEO
import Foundation

enum SubtitleParser {
    nonisolated static func parse(data: Data, sourceURL: URL) throws -> SubtitleDocument {
        let format = try format(for: sourceURL)
        let text = decode(data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        switch format {
        case .ass, .ssa:
            return try parseAdvancedSubStationAlpha(
                text,
                sourceURL: sourceURL,
                format: format
            )
        case .srt, .webVTT, .embedded:
            break
        }

        let normalizedText = text.replacing(#/\n{2,}/#, with: "\n\n")
        let blocks = normalizedText.components(separatedBy: "\n\n")
        var warnings: [String] = []
        var cues: [SubtitleCue] = []

        for (index, block) in blocks.enumerated() {
            guard let cue = parseBlock(block, index: index, format: format) else {
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "WEBVTT", !trimmed.hasPrefix("NOTE") {
                    warnings.append("Skipped subtitle block \(index + 1).")
                }
                continue
            }
            cues.append(cue)
        }

        cues.sort {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        guard !cues.isEmpty else {
            throw SubtitleParserError.noValidCues
        }
        return SubtitleDocument(sourceURL: sourceURL, format: format, cues: cues, warnings: warnings)
    }

    nonisolated private static func format(for url: URL) throws -> SubtitleFormat {
        switch url.pathExtension.lowercased() {
        case "srt":
            return .srt
        case "vtt":
            return .webVTT
        case "ass":
            return .ass
        case "ssa":
            return .ssa
        default:
            throw SubtitleParserError.unsupportedFormat
        }
    }

    nonisolated private static func decode(_ data: Data) -> String {
        if let value = String(data: data, encoding: .utf8) {
            return value.replacingOccurrences(of: "\u{feff}", with: "")
        }
        if let value = String(data: data, encoding: .utf16) {
            return value.replacingOccurrences(of: "\u{feff}", with: "")
        }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func parseBlock(_ block: String, index: Int, format: SubtitleFormat) -> SubtitleCue? {
        var lines = block.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return nil }

        if format == .webVTT, lines.first?.hasPrefix("WEBVTT") == true {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return nil }

        let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
        guard let timingIndex else { return nil }
        let timing = lines[timingIndex].components(separatedBy: "-->")
        guard timing.count == 2 else { return nil }
        let endToken = timing[1].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? timing[1]
        guard let start = parseTimestamp(timing[0]),
              let end = parseTimestamp(endToken),
              end >= start else {
            return nil
        }

        let text = lines
            .dropFirst(timingIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let declaredID = timingIndex > 0
            ? lines[timingIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return SubtitleCue(
            id: declaredID.isEmpty ? "\(index)" : declaredID,
            startTime: start,
            endTime: end,
            text: text
        )
    }

    nonisolated private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let timestamp = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = timestamp.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double
        if parts.count == 3 {
            guard let parsedHours = Double(parts[0]),
                  let parsedMinutes = Double(parts[1]),
                  let parsedSeconds = Double(parts[2]) else {
                return nil
            }
            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            guard let parsedMinutes = Double(parts[0]),
                  let parsedSeconds = Double(parts[1]) else {
                return nil
            }
            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    nonisolated private static func parseAdvancedSubStationAlpha(
        _ text: String,
        sourceURL: URL,
        format: SubtitleFormat
    ) throws -> SubtitleDocument {
        var warnings: [String] = []
        var cues: [SubtitleCue] = []
        var isInEventsSection = false
        var eventFields = defaultASSDialogueFields

        for (lineIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                isInEventsSection = line.lowercased() == "[events]"
                continue
            }
            guard isInEventsSection else { continue }

            if let formatValue = value(after: "Format:", in: line) {
                let parsedFields = formatValue
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }
                if parsedFields.contains("start"),
                   parsedFields.contains("end"),
                   parsedFields.contains("text") {
                    eventFields = parsedFields
                }
                continue
            }

            if value(after: "Comment:", in: line) != nil {
                continue
            }

            guard let dialogueValue = value(after: "Dialogue:", in: line) else {
                continue
            }

            guard let cue = parseASSDialogue(
                dialogueValue,
                fields: eventFields,
                lineNumber: lineIndex + 1
            ) else {
                warnings.append("Skipped ASS dialogue line \(lineIndex + 1).")
                continue
            }
            cues.append(cue)
        }

        cues.sort {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        guard !cues.isEmpty else {
            throw SubtitleParserError.noValidCues
        }
        return SubtitleDocument(
            sourceURL: sourceURL,
            format: format,
            cues: cues,
            warnings: warnings
        )
    }

    nonisolated private static let defaultASSDialogueFields = [
        "layer",
        "start",
        "end",
        "style",
        "name",
        "marginl",
        "marginr",
        "marginv",
        "effect",
        "text"
    ]

    nonisolated private static func parseASSDialogue(
        _ rawDialogue: String,
        fields: [String],
        lineNumber: Int
    ) -> SubtitleCue? {
        guard let startIndex = fields.firstIndex(of: "start"),
              let endIndex = fields.firstIndex(of: "end"),
              let textIndex = fields.firstIndex(of: "text") else {
            return nil
        }

        let parts = rawDialogue
            .split(
                separator: ",",
                maxSplits: max(fields.count - 1, 0),
                omittingEmptySubsequences: false
            )
            .map(String.init)
        guard parts.indices.contains(startIndex),
              parts.indices.contains(endIndex),
              parts.indices.contains(textIndex),
              let start = parseTimestamp(parts[startIndex]),
              let end = parseTimestamp(parts[endIndex]),
              end >= start else {
            return nil
        }

        let text = cleanedASSText(parts[textIndex])
        guard !text.isEmpty else { return nil }

        return SubtitleCue(
            id: "ass-\(lineNumber)",
            startTime: start,
            endTime: end,
            text: text
        )
    }

    nonisolated private static func cleanedASSText(_ rawText: String) -> String {
        var output = ""
        var isInOverrideTag = false
        var index = rawText.startIndex
        while index < rawText.endIndex {
            let character = rawText[index]
            if character == "{" {
                isInOverrideTag = true
            } else if character == "}", isInOverrideTag {
                isInOverrideTag = false
            } else if !isInOverrideTag {
                output.append(character)
            }
            index = rawText.index(after: index)
        }

        return output
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func value(after prefix: String, in line: String) -> String? {
        guard line.range(
            of: prefix,
            options: [.anchored, .caseInsensitive]
        ) != nil else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
