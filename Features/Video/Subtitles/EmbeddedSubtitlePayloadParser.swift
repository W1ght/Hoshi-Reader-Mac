#if HOSHI_VIDEO
import Foundation

nonisolated enum ASSSubtitleTextSanitizer {
    static func clean(_ rawText: String) -> String {
        var output = ""
        output.reserveCapacity(rawText.count)
        var drawingScale = 0
        var index = rawText.startIndex

        while index < rawText.endIndex {
            if rawText[index] == "{",
               let closeIndex = rawText[index...].firstIndex(of: "}") {
                updateDrawingScale(
                    from: rawText[rawText.index(after: index)..<closeIndex],
                    drawingScale: &drawingScale
                )
                index = rawText.index(after: closeIndex)
                continue
            }
            if drawingScale == 0 {
                output.append(rawText[index])
            }
            index = rawText.index(after: index)
        }

        return output
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func updateDrawingScale(
        from overrideBlock: Substring,
        drawingScale: inout Int
    ) {
        for rawTag in overrideBlock.split(separator: "\\", omittingEmptySubsequences: true) {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tag.first?.lowercased() == "p" else { continue }
            let valueStart = tag.index(after: tag.startIndex)
            let valueText = tag[valueStart...].prefix(while: { $0.isNumber })
            guard !valueText.isEmpty, let value = Int(valueText) else { continue }
            drawingScale = max(value, 0)
        }
    }
}

nonisolated struct EmbeddedSubtitlePacketRecord: Hashable, Sendable {
    let rawPayload: Data
    let presentationTimestamp: Int64
    let decodingTimestamp: Int64
    let packetDuration: Int64
    let timeBaseNumerator: Int
    let timeBaseDenominator: Int
    let packetFlags: Int
    let filePosition: Int64
    let startTime: TimeInterval
    let endTime: TimeInterval
}

enum EmbeddedSubtitlePayloadParser {
    nonisolated static func supportsText(codec: String?) -> Bool {
        guard let codec else { return false }
        switch codec.lowercased() {
        case "ass", "ssa", "subrip", "srt", "text", "webvtt", "mov_text":
            return true
        default:
            return false
        }
    }

    nonisolated static func text(from payload: String, codec: String?) -> String {
        var text = payload
        if let codec, codec.lowercased() == "ass" || codec.lowercased() == "ssa" {
            var commaCount = 0
            if let textStart = text.indices.first(where: { index in
                guard text[index] == "," else { return false }
                commaCount += 1
                return commaCount == 8
            }) {
                text = String(text[text.index(after: textStart)...])
            }
            text = ASSSubtitleTextSanitizer.clean(text)
        }
        return text
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .replacing(#/<br\s*\/?>/#, with: "\n")
            .replacing(#/<[^>]+>/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func reconstructedASSData(
        codecPrivate: Data?,
        packets: [EmbeddedSubtitlePacketRecord],
        codec: String?
    ) -> Data? {
        try? reconstructedASSData(
            codecPrivate: codecPrivate,
            packets: packets,
            codec: codec,
            isCancelled: { false }
        )
    }

    nonisolated static func reconstructedASSData(
        codecPrivate: Data?,
        packets: [EmbeddedSubtitlePacketRecord],
        codec: String?,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Data? {
        try throwIfCancelled(isCancelled)
        guard let codec = codec?.lowercased(), codec == "ass" || codec == "ssa",
              let codecPrivate, !codecPrivate.isEmpty, !packets.isEmpty else {
            return nil
        }

        let rawHeader = String(decoding: codecPrivate, as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "")
        guard !rawHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let newline = rawHeader.contains("\r\n") ? "\r\n" : "\n"
        var lines = rawHeader
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        try throwIfCancelled(isCancelled)

        let eventsIndex = lines.firstIndex(where: {
            normalizedSectionName($0) == "events"
        })
        var eventEndIndex: Int
        let formatFields: [String]
        if let eventsIndex {
            eventEndIndex = lines[(eventsIndex + 1)...].firstIndex(where: {
                normalizedSectionName($0) != nil
            }) ?? lines.endIndex
            if let formatLineIndex = lines[(eventsIndex + 1)..<eventEndIndex].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("format:")
            }) {
                formatFields = assEventFormatFields(from: lines[formatLineIndex])
            } else {
                formatFields = defaultASSEventFormatFields(codec: codec)
                lines.insert("Format: \(formatFields.joined(separator: ", "))", at: eventsIndex + 1)
                eventEndIndex = eventEndIndex + 1
            }
        } else {
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[Events]")
            formatFields = defaultASSEventFormatFields(codec: codec)
            lines.append("Format: \(formatFields.joined(separator: ", "))")
            eventEndIndex = lines.endIndex
        }

        guard !formatFields.isEmpty else { return nil }
        var dialogueLines: [String] = []
        dialogueLines.reserveCapacity(packets.count)
        for packet in packets {
            try throwIfCancelled(isCancelled)
            guard let payload = String(data: packet.rawPayload, encoding: .utf8),
                  let fields = matroskaASSFields(from: payload),
                  let startTimestamp = assTimestamp(packet.startTime),
                  let packetEndTimestamp = assTimestamp(packet.endTime) else {
                continue
            }
            let endTimestamp = packet.endTime < packet.startTime
                ? startTimestamp
                : packetEndTimestamp
            let values = formatFields.map { field in
                assEventValue(
                    for: field,
                    packetFields: fields,
                    startTimestamp: startTimestamp,
                    endTimestamp: endTimestamp
                )
            }
            dialogueLines.append("Dialogue: \(values.joined(separator: ","))")
        }
        try throwIfCancelled(isCancelled)
        guard !dialogueLines.isEmpty else { return nil }
        lines.insert(contentsOf: dialogueLines, at: eventEndIndex)
        let result = (lines.joined(separator: newline) + newline).data(using: .utf8)
        try throwIfCancelled(isCancelled)
        return result
    }

    private nonisolated static func normalizedSectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[", trimmed.last == "]", trimmed.count > 2 else {
            return nil
        }
        return trimmed.dropFirst().dropLast().lowercased()
    }

    private nonisolated static func assEventFormatFields(from line: String) -> [String] {
        guard let colon = line.firstIndex(of: ":") else { return [] }
        return line[line.index(after: colon)...]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private nonisolated static func defaultASSEventFormatFields(codec: String) -> [String] {
        if codec == "ssa" {
            return [
                "Marked", "Start", "End", "Style", "Name",
                "MarginL", "MarginR", "MarginV", "Effect", "Text",
            ]
        }
        return [
            "Layer", "Start", "End", "Style", "Name",
            "MarginL", "MarginR", "MarginV", "Effect", "Text",
        ]
    }

    private nonisolated static func matroskaASSFields(from payload: String) -> [String]? {
        let fields = payload
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
            .map(String.init)
        return fields.count == 9 ? fields : nil
    }

    private nonisolated static func assEventValue(
        for rawField: String,
        packetFields: [String],
        startTimestamp: String,
        endTimestamp: String
    ) -> String {
        let field = rawField
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return switch field {
        case "readorder":
            packetFields[0]
        case "layer":
            packetFields[1]
        case "marked":
            packetFields[1].lowercased().hasPrefix("marked=")
                ? packetFields[1]
                : "Marked=\(packetFields[1])"
        case "start":
            startTimestamp
        case "end":
            endTimestamp
        case "style":
            packetFields[2]
        case "name", "actor":
            packetFields[3]
        case "marginl":
            packetFields[4]
        case "marginr":
            packetFields[5]
        case "marginv":
            packetFields[6]
        case "effect":
            packetFields[7]
        case "text":
            packetFields[8]
        default:
            ""
        }
    }

    private nonisolated static func assTimestamp(_ time: TimeInterval) -> String? {
        guard time.isFinite, time >= 0 else { return nil }
        let roundedCentiseconds = (time * 100).rounded()
        guard roundedCentiseconds.isFinite,
              roundedCentiseconds >= 0,
              roundedCentiseconds < Double(Int.max) else {
            return nil
        }
        let centiseconds = Int(roundedCentiseconds)
        let hours = centiseconds / 360_000
        let minutes = (centiseconds / 6_000) % 60
        let seconds = (centiseconds / 100) % 60
        let remainder = centiseconds % 100
        return "\(hours):" + String(
            format: "%02d:%02d.%02d",
            minutes,
            seconds,
            remainder
        )
    }

    private nonisolated static func throwIfCancelled(
        _ isCancelled: @Sendable () -> Bool
    ) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }
}
#endif
