import CoreGraphics
import Foundation

nonisolated enum MangaMokuroError: LocalizedError {
    case invalidMetadata

    var errorDescription: String? {
        String(localized: "The Mokuro text metadata could not be read.")
    }
}

nonisolated enum MangaMokuroParser {
    static func isMetadata(_ data: Data) -> Bool {
        (try? pagePaths(in: data)) != nil
    }

    static func pagePaths(in data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else {
            throw MangaMokuroError.invalidMetadata
        }
        return pages.compactMap { page in
            guard let path = page["img_path"] as? String else { return nil }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func regions(
        in data: Data,
        pagePath: String,
        pageIndex: Int
    ) throws -> [MangaOCRTextRegion]? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawPages = root["pages"] as? [[String: Any]] else {
            throw MangaMokuroError.invalidMetadata
        }
        let pageName = URL(fileURLWithPath: pagePath).lastPathComponent
        let namedPage = rawPages.first {
            guard let imagePath = $0["img_path"] as? String else { return false }
            return URL(fileURLWithPath: imagePath).lastPathComponent
                .caseInsensitiveCompare(pageName) == .orderedSame
        }
        let rawPage = namedPage
            ?? (rawPages.indices.contains(pageIndex) ? rawPages[pageIndex] : nil)
        guard let rawPage, let page = parsePage(rawPage) else { return nil }
        return makeRegions(page: page, pageIndex: pageIndex)
    }

    private struct Page {
        let imagePath: String
        let width: CGFloat
        let height: CGFloat
        let blocks: [Block]
    }

    private struct Block {
        let box: [CGFloat]
        let isVertical: Bool
        let lines: [String]
        let lineCoordinates: [[[CGFloat]]]
    }

    private static func parsePage(_ raw: [String: Any]) -> Page? {
        let width = number(raw["img_width"])
        let height = number(raw["img_height"])
        guard width > 0, height > 0 else { return nil }
        let blocks = (raw["blocks"] as? [[String: Any]] ?? []).compactMap(parseBlock)
        return Page(
            imagePath: raw["img_path"] as? String ?? "",
            width: width,
            height: height,
            blocks: blocks
        )
    }

    private static func parseBlock(_ raw: [String: Any]) -> Block? {
        let box = numbers(raw["box"] ?? [])
        let lines = (raw["lines"] as? [Any] ?? [])
            .map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard box.count >= 4, !lines.isEmpty else { return nil }
        let coordinates = (raw["lines_coords"] as? [Any] ?? []).map { polygon in
            (polygon as? [Any] ?? []).map(numbers)
        }
        return Block(
            box: box,
            isVertical: raw["vertical"] as? Bool == true,
            lines: lines,
            lineCoordinates: coordinates
        )
    }

    private static func makeRegions(
        page: Page,
        pageIndex: Int
    ) -> [MangaOCRTextRegion] {
        page.blocks.enumerated().flatMap { blockIndex, block in
            let blockID = "mokuro-\(pageIndex)-\(blockIndex)"
            let sentence = block.lines.joined()
            let blockRect = normalizedRect(
                x1: block.box[0],
                y1: block.box[1],
                x2: block.box[2],
                y2: block.box[3],
                page: page
            )
            var baseOffset = 0
            return block.lines.enumerated().flatMap { lineIndex, line in
                let lineRect = lineIndex < block.lineCoordinates.count
                    ? normalizedPolygon(
                        block.lineCoordinates[lineIndex],
                        page: page
                    )
                    : nil
                let resolvedRect = lineRect ?? fallbackLineRect(
                    blockRect: blockRect,
                    lineIndex: lineIndex,
                    lineCount: block.lines.count,
                    isVertical: block.isVertical
                )
                defer { baseOffset += line.utf16.count }
                return makeCharacterRegions(
                    line: line,
                    sentence: sentence,
                    baseOffset: baseOffset,
                    rect: resolvedRect,
                    pageIndex: pageIndex,
                    blockID: blockID,
                    lineID: "\(blockID)-\(lineIndex)",
                    isVertical: block.isVertical
                )
            }
        }
    }

    private static func makeCharacterRegions(
        line: String,
        sentence: String,
        baseOffset: Int,
        rect: CGRect,
        pageIndex: Int,
        blockID: String,
        lineID: String,
        isVertical: Bool
    ) -> [MangaOCRTextRegion] {
        let characters = line.indices.map { index in
            (
                offset: baseOffset + line[..<index].utf16.count,
                character: line[index]
            )
        }.filter { !$0.character.isWhitespace }
        guard !characters.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let count = CGFloat(characters.count)
        return characters.enumerated().map { index, character in
            let characterRect: CGRect
            if isVertical {
                let height = rect.height / count
                characterRect = CGRect(
                    x: rect.minX,
                    y: rect.maxY - CGFloat(index + 1) * height,
                    width: rect.width,
                    height: height
                )
            } else {
                let width = rect.width / count
                characterRect = CGRect(
                    x: rect.minX + CGFloat(index) * width,
                    y: rect.minY,
                    width: width,
                    height: rect.height
                )
            }
            return MangaOCRTextRegion(
                id: "\(lineID)-\(character.offset)",
                pageIndex: pageIndex,
                blockID: blockID,
                lineID: lineID,
                sentence: sentence,
                utf16Offset: character.offset,
                isVertical: isVertical,
                normalizedBounds: characterRect
            )
        }
    }

    private static func normalizedPolygon(
        _ polygon: [[CGFloat]],
        page: Page
    ) -> CGRect? {
        let points = polygon.compactMap { point -> CGPoint? in
            guard point.count >= 2 else { return nil }
            return CGPoint(x: point[0], y: point[1])
        }
        guard !points.isEmpty else { return nil }
        let minX = points.map(\.x).min() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        guard maxX > minX, maxY > minY else { return nil }
        return normalizedRect(
            x1: minX,
            y1: minY,
            x2: maxX,
            y2: maxY,
            page: page
        )
    }

    private static func normalizedRect(
        x1: CGFloat,
        y1: CGFloat,
        x2: CGFloat,
        y2: CGFloat,
        page: Page
    ) -> CGRect {
        let left = min(max(0, x1 / page.width), 1)
        let top = min(max(0, y1 / page.height), 1)
        let right = min(max(0, x2 / page.width), 1)
        let bottom = min(max(0, y2 / page.height), 1)
        return CGRect(
            x: left,
            y: 1 - bottom,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    private static func fallbackLineRect(
        blockRect: CGRect,
        lineIndex: Int,
        lineCount: Int,
        isVertical: Bool
    ) -> CGRect {
        let count = CGFloat(max(1, lineCount))
        if isVertical {
            let width = blockRect.width / count
            return CGRect(
                x: blockRect.maxX - CGFloat(lineIndex + 1) * width,
                y: blockRect.minY,
                width: width,
                height: blockRect.height
            )
        }
        let height = blockRect.height / count
        return CGRect(
            x: blockRect.minX,
            y: blockRect.maxY - CGFloat(lineIndex + 1) * height,
            width: blockRect.width,
            height: height
        )
    }

    private static func number(_ value: Any?) -> CGFloat {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return CGFloat(Double(String(describing: value ?? "")) ?? 0)
    }

    private static func numbers(_ value: Any) -> [CGFloat] {
        (value as? [Any] ?? []).map(number)
    }
}
