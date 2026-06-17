#if HOSHI_VIDEO
import Foundation

enum SubtitleParser {
    nonisolated static func parse(data: Data, sourceURL: URL) throws -> SubtitleDocument {
        let format = try format(for: sourceURL)
        let text = decode(data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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
}
#endif
