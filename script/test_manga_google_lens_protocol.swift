import Foundation

@main
private enum MangaGoogleLensProtocolTests {
    static func main() throws {
        let response = makeResponse()
        let regions = try MangaGoogleLensProtocol.decodeResponse(
            response,
            pageIndex: 7,
            language: "ja"
        )

        require(regions.count == 3, "Lens paragraph lines should create per-character hit regions")
        require(
            regions.allSatisfy { $0.sentence == "日本語" },
            "every hit region must carry the complete OCR paragraph for mining"
        )
        require(regions.map(\.utf16Offset) == [0, 1, 2], "UTF-16 offsets must follow block reading order")
        require(Set(regions.map(\.blockID)).count == 1, "one Lens paragraph must remain one hover block")
        require(Set(regions.map(\.lineID)).count == 2, "line geometry must remain distinct inside a block")
        require(regions.allSatisfy(\.isVertical), "vertical Lens paragraphs must retain popup orientation")
        require(regions.allSatisfy { $0.pageIndex == 7 }, "decoded regions must retain their page")
        require(
            regions[0].normalizedBounds.minY > regions[1].normalizedBounds.minY,
            "vertical Lens text must be ordered from top to bottom in page coordinates"
        )
        require(
            regions.allSatisfy {
                $0.normalizedBounds.minX >= 0
                    && $0.normalizedBounds.minY >= 0
                    && $0.normalizedBounds.maxX <= 1
                    && $0.normalizedBounds.maxY <= 1
            },
            "Lens geometry must remain normalized to the page"
        )

        let request = MangaGoogleLensProtocol.makeRequest(
            imageData: Data([0xde, 0xad, 0xbe, 0xef]),
            width: 1200,
            height: 800,
            language: "ja"
        )
        require(request.count > 4, "the Lens protobuf request must wrap image bytes and metadata")

        print("Manga Google Lens protocol tests passed")
    }

    private static func makeResponse() -> Data {
        message(2, message(3, message(1, message(1,
            line(words: [("日", " "), ("本", "")], centerX: 0.80)
                + line(words: [("語", "")], centerX: 0.60)
        ))))
    }

    private static func line(
        words: [(String, String)],
        centerX: Float
    ) -> Data {
        let wordMessages = words.map { word, separator in
            message(1, string(2, word) + string(3, separator))
        }.reduce(into: Data()) { $0.append($1) }
        return message(2, wordMessages + message(2, geometry(centerX: centerX)))
    }

    private static func geometry(centerX: Float) -> Data {
        message(
            1,
            float32(1, centerX)
                + float32(2, 0.50)
                + float32(3, 0.40)
                + float32(4, 0.10)
                + float32(5, .pi / 2)
        )
    }

    private static func message(_ field: Int, _ value: Data) -> Data {
        bytes(field, value)
    }

    private static func string(_ field: Int, _ value: String) -> Data {
        bytes(field, Data(value.utf8))
    }

    private static func bytes(_ field: Int, _ value: Data) -> Data {
        var data = varint(UInt64((field << 3) | 2))
        data.append(varint(UInt64(value.count)))
        data.append(value)
        return data
    }

    private static func float32(_ field: Int, _ value: Float) -> Data {
        var bits = value.bitPattern.littleEndian
        var data = varint(UInt64((field << 3) | 5))
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        return data
    }

    private static func varint(_ value: UInt64) -> Data {
        var remaining = value
        var data = Data()
        while remaining > 0x7f {
            data.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
        return data
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
