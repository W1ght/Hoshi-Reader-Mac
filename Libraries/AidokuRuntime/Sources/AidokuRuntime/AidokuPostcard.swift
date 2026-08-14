import Foundation

public struct AidokuPostcardWriter: Sendable {
    public private(set) var data = Data()

    public init() {}

    public mutating func write(_ value: Bool) { data.append(value ? 1 : 0) }
    public mutating func write(_ value: UInt8) { data.append(value) }
    public mutating func write(_ value: UInt16) { writeVarUInt(UInt64(value)) }
    public mutating func write(_ value: UInt32) { writeVarUInt(UInt64(value)) }
    public mutating func write(_ value: UInt64) { writeVarUInt(value) }
    public mutating func write(_ value: Int32) { writeVarUInt(zigZag(Int64(value))) }
    public mutating func write(_ value: Int64) { writeVarUInt(zigZag(value)) }

    public mutating func write(_ value: Float) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public mutating func write(_ value: Double) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public mutating func write(_ value: String) {
        let bytes = Data(value.utf8)
        writeVarUInt(UInt64(bytes.count))
        data.append(bytes)
    }

    public mutating func write(_ value: Data) {
        writeVarUInt(UInt64(value.count))
        data.append(value)
    }

    public mutating func write<T>(_ value: T?, body: (inout Self, T) -> Void) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        body(&self, value)
    }

    public mutating func write<T>(_ values: [T], body: (inout Self, T) -> Void) {
        writeVarUInt(UInt64(values.count))
        for value in values { body(&self, value) }
    }

    public mutating func write<K, V>(
        _ values: [K: V],
        key: (inout Self, K) -> Void,
        value: (inout Self, V) -> Void
    ) {
        writeVarUInt(UInt64(values.count))
        for pair in values.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
            key(&self, pair.key)
            value(&self, pair.value)
        }
    }

    public mutating func writeVarUInt(_ value: UInt64) {
        var remainder = value
        while remainder >= 0x80 {
            data.append(UInt8(remainder & 0x7f) | 0x80)
            remainder >>= 7
        }
        data.append(UInt8(remainder))
    }

    private func zigZag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }
}

public struct AidokuPostcardReader: Sendable {
    public let data: Data
    public private(set) var offset = 0

    public init(data: Data) {
        self.data = data
    }

    public mutating func readBool() throws -> Bool {
        switch try readUInt8() {
        case 0: false
        case 1: true
        default: throw AidokuRuntimeError.malformedPostcard
        }
    }

    public mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw AidokuRuntimeError.malformedPostcard }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func readUInt16() throws -> UInt16 {
        let value = try readVarUInt()
        guard value <= UInt16.max else { throw AidokuRuntimeError.malformedPostcard }
        return UInt16(value)
    }

    public mutating func readUInt32() throws -> UInt32 {
        let value = try readVarUInt()
        guard value <= UInt32.max else { throw AidokuRuntimeError.malformedPostcard }
        return UInt32(value)
    }

    public mutating func readUInt64() throws -> UInt64 { try readVarUInt() }

    public mutating func readInt32() throws -> Int32 {
        let value = try readSigned()
        guard value >= Int64(Int32.min), value <= Int64(Int32.max) else {
            throw AidokuRuntimeError.malformedPostcard
        }
        return Int32(value)
    }

    public mutating func readInt64() throws -> Int64 { try readSigned() }

    public mutating func readFloat() throws -> Float {
        Float(bitPattern: try readFixedWidth(UInt32.self))
    }

    public mutating func readDouble() throws -> Double {
        Double(bitPattern: try readFixedWidth(UInt64.self))
    }

    public mutating func readString(maxBytes: Int = AidokuLimits.maximumJSONBytes) throws -> String {
        let bytes = try readData(maxBytes: maxBytes)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw AidokuRuntimeError.malformedPostcard
        }
        return value
    }

    public mutating func readData(maxBytes: Int) throws -> Data {
        let length = try readLength(maximum: maxBytes)
        guard data.count - offset >= length else { throw AidokuRuntimeError.malformedPostcard }
        defer { offset += length }
        return data.subdata(in: offset..<(offset + length))
    }

    public mutating func readOptional<T>(_ body: (inout Self) throws -> T) throws -> T? {
        switch try readUInt8() {
        case 0: nil
        case 1: try body(&self)
        default: throw AidokuRuntimeError.malformedPostcard
        }
    }

    public mutating func readArray<T>(
        maximumCount: Int = 100_000,
        _ body: (inout Self) throws -> T
    ) throws -> [T] {
        let count = try readLength(maximum: maximumCount)
        var output: [T] = []
        output.reserveCapacity(count)
        for _ in 0..<count { output.append(try body(&self)) }
        return output
    }

    public mutating func readDictionary<K: Hashable, V>(
        maximumCount: Int = 10_000,
        key: (inout Self) throws -> K,
        value: (inout Self) throws -> V
    ) throws -> [K: V] {
        let count = try readLength(maximum: maximumCount)
        var output: [K: V] = [:]
        output.reserveCapacity(count)
        for _ in 0..<count { output[try key(&self)] = try value(&self) }
        return output
    }

    public mutating func finish() throws {
        guard offset == data.count else { throw AidokuRuntimeError.malformedPostcard }
    }

    public mutating func readVarUInt() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            let byte = try readUInt8()
            let payload = UInt64(byte & 0x7f)
            guard shift < 64, payload <= (UInt64.max >> shift) else {
                throw AidokuRuntimeError.malformedPostcard
            }
            result |= payload << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw AidokuRuntimeError.malformedPostcard
    }

    private mutating func readSigned() throws -> Int64 {
        let value = try readVarUInt()
        return Int64(bitPattern: value >> 1) ^ -Int64(value & 1)
    }

    private mutating func readLength(maximum: Int) throws -> Int {
        let value = try readVarUInt()
        guard value <= UInt64(maximum), value <= UInt64(Int.max) else {
            throw AidokuRuntimeError.malformedPostcard
        }
        return Int(value)
    }

    private mutating func readFixedWidth<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let count = MemoryLayout<T>.size
        guard data.count - offset >= count else { throw AidokuRuntimeError.malformedPostcard }
        var value: T = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination, from: offset..<(offset + count))
        }
        offset += count
        return T(littleEndian: value)
    }
}
