import Foundation

public enum AidokuWasmSanitizer {
    public struct Inspection: Sendable, Equatable {
        public let imports: Set<String>
        public let exports: Set<String>
    }

    private static let pageBytes = 65_536
    private static let maximumPages = UInt64(AidokuLimits.maximumLinearMemoryBytes / pageBytes)

    /// Rewrites the module's single linear-memory declaration so Wasm3 cannot
    /// grow it beyond Niratan's 64 MiB boundary. Imported memories and multiple
    /// memories are rejected because they cannot be safely rewritten here.
    public static func restrictingLinearMemory(in data: Data) throws -> Data {
        guard data.count >= 8,
              data.starts(with: [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]) else {
            throw AidokuRuntimeError.invalidWasm
        }
        let bytes = [UInt8](data)
        var cursor = 8
        var output = Array(bytes[0..<8])
        var foundMemory = false
        while cursor < bytes.count {
            let sectionID = bytes[cursor]
            cursor += 1
            let sectionLength = try readULEB(bytes, cursor: &cursor)
            guard sectionLength <= UInt64(bytes.count - cursor) else {
                throw AidokuRuntimeError.invalidWasm
            }
            let end = cursor + Int(sectionLength)
            let payload = Array(bytes[cursor..<end])
            cursor = end
            if sectionID == 2, try importSectionContainsMemory(payload) {
                throw AidokuRuntimeError.incompatibleSource("imported linear memory is not supported")
            }
            if sectionID == 5 {
                guard !foundMemory else {
                    throw AidokuRuntimeError.incompatibleSource("multiple linear memories are not supported")
                }
                foundMemory = true
                let rewritten = try rewriteMemorySection(payload)
                output.append(sectionID)
                output.append(contentsOf: encodeULEB(UInt64(rewritten.count)))
                output.append(contentsOf: rewritten)
            } else {
                output.append(sectionID)
                output.append(contentsOf: encodeULEB(UInt64(payload.count)))
                output.append(contentsOf: payload)
            }
        }
        guard foundMemory else {
            throw AidokuRuntimeError.incompatibleSource("the source has no linear memory")
        }
        return Data(output)
    }

    public static func inspect(_ data: Data) throws -> Inspection {
        guard data.count >= 8,
              data.starts(with: [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]) else {
            throw AidokuRuntimeError.invalidWasm
        }
        let bytes = [UInt8](data)
        var cursor = 8
        var imports = Set<String>()
        var exports = Set<String>()
        while cursor < bytes.count {
            let sectionID = bytes[cursor]
            cursor += 1
            let length = try readULEB(bytes, cursor: &cursor)
            guard length <= UInt64(bytes.count - cursor) else { throw AidokuRuntimeError.invalidWasm }
            let end = cursor + Int(length)
            var sectionCursor = cursor
            if sectionID == 2 {
                let count = try readULEB(bytes, cursor: &sectionCursor)
                guard count <= 10_000 else { throw AidokuRuntimeError.invalidWasm }
                for _ in 0..<count {
                    let namespace = try readName(bytes, cursor: &sectionCursor)
                    let name = try readName(bytes, cursor: &sectionCursor)
                    guard sectionCursor < end else { throw AidokuRuntimeError.invalidWasm }
                    let kind = bytes[sectionCursor]
                    sectionCursor += 1
                    switch kind {
                    case 0: _ = try readULEB(bytes, cursor: &sectionCursor)
                    case 1:
                        guard sectionCursor < end else { throw AidokuRuntimeError.invalidWasm }
                        sectionCursor += 1
                        try skipLimits(bytes, cursor: &sectionCursor)
                    case 2: try skipLimits(bytes, cursor: &sectionCursor)
                    case 3:
                        guard sectionCursor + 2 <= end else { throw AidokuRuntimeError.invalidWasm }
                        sectionCursor += 2
                    default: throw AidokuRuntimeError.invalidWasm
                    }
                    imports.insert("\(namespace).\(name)")
                }
            } else if sectionID == 7 {
                let count = try readULEB(bytes, cursor: &sectionCursor)
                guard count <= 10_000 else { throw AidokuRuntimeError.invalidWasm }
                for _ in 0..<count {
                    exports.insert(try readName(bytes, cursor: &sectionCursor))
                    guard sectionCursor < end else { throw AidokuRuntimeError.invalidWasm }
                    sectionCursor += 1
                    _ = try readULEB(bytes, cursor: &sectionCursor)
                }
            }
            guard sectionCursor <= end else { throw AidokuRuntimeError.invalidWasm }
            cursor = end
        }
        return Inspection(imports: imports, exports: exports)
    }

    private static func rewriteMemorySection(_ payload: [UInt8]) throws -> [UInt8] {
        var cursor = 0
        let count = try readULEB(payload, cursor: &cursor)
        guard count == 1 else {
            throw AidokuRuntimeError.incompatibleSource("multiple linear memories are not supported")
        }
        let flags = try readULEB(payload, cursor: &cursor)
        guard flags == 0 || flags == 1 else {
            throw AidokuRuntimeError.incompatibleSource("unsupported linear-memory flags")
        }
        let initial = try readULEB(payload, cursor: &cursor)
        guard initial <= maximumPages else {
            throw AidokuRuntimeError.incompatibleSource("initial linear memory exceeds 64 MiB")
        }
        if flags == 1 { _ = try readULEB(payload, cursor: &cursor) }
        guard cursor == payload.count else { throw AidokuRuntimeError.invalidWasm }
        var output = encodeULEB(1)
        output += encodeULEB(1)
        output += encodeULEB(initial)
        output += encodeULEB(maximumPages)
        return output
    }

    private static func importSectionContainsMemory(_ payload: [UInt8]) throws -> Bool {
        var cursor = 0
        let count = try readULEB(payload, cursor: &cursor)
        guard count <= 10_000 else { throw AidokuRuntimeError.invalidWasm }
        for _ in 0..<count {
            try skipName(payload, cursor: &cursor)
            try skipName(payload, cursor: &cursor)
            guard cursor < payload.count else { throw AidokuRuntimeError.invalidWasm }
            let kind = payload[cursor]
            cursor += 1
            switch kind {
            case 0: _ = try readULEB(payload, cursor: &cursor)
            case 1:
                guard cursor < payload.count else { throw AidokuRuntimeError.invalidWasm }
                cursor += 1
                try skipLimits(payload, cursor: &cursor)
            case 2: return true
            case 3:
                guard cursor + 2 <= payload.count else { throw AidokuRuntimeError.invalidWasm }
                cursor += 2
            default: throw AidokuRuntimeError.invalidWasm
            }
        }
        return false
    }

    private static func skipLimits(_ bytes: [UInt8], cursor: inout Int) throws {
        let flags = try readULEB(bytes, cursor: &cursor)
        _ = try readULEB(bytes, cursor: &cursor)
        if flags & 1 != 0 { _ = try readULEB(bytes, cursor: &cursor) }
    }

    private static func skipName(_ bytes: [UInt8], cursor: inout Int) throws {
        let length = try readULEB(bytes, cursor: &cursor)
        guard length <= UInt64(bytes.count - cursor) else { throw AidokuRuntimeError.invalidWasm }
        cursor += Int(length)
    }

    private static func readName(_ bytes: [UInt8], cursor: inout Int) throws -> String {
        let length = try readULEB(bytes, cursor: &cursor)
        guard length <= UInt64(bytes.count - cursor) else { throw AidokuRuntimeError.invalidWasm }
        let end = cursor + Int(length)
        guard let value = String(bytes: bytes[cursor..<end], encoding: .utf8) else {
            throw AidokuRuntimeError.invalidWasm
        }
        cursor = end
        return value
    }

    private static func readULEB(_ bytes: [UInt8], cursor: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard cursor < bytes.count else { throw AidokuRuntimeError.invalidWasm }
            let byte = bytes[cursor]
            cursor += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw AidokuRuntimeError.invalidWasm
    }

    private static func encodeULEB(_ value: UInt64) -> [UInt8] {
        var value = value
        var output: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            output.append(byte)
        } while value != 0
        return output
    }
}
