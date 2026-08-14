//
//  Memory.swift
//  Wasm3
//
//  Created by Skitty on 6/19/23.
//

import Foundation

public struct Memory {
    let raw: UnsafeMutablePointer<UInt8>
    let size: UInt32

    private func valid(offset: UInt32, length: UInt32) -> Bool {
        guard offset < UInt32.max else { return false }
        return offset + length <= size
    }
}

// MARK: Writing

public extension Memory {
    func write(bytes: [UInt8], offset: UInt32) throws {
        guard valid(offset: offset, length: UInt32(bytes.count)) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        raw.advanced(by: Int(offset))
            .initialize(from: bytes, count: bytes.count)
    }

    func write(data: Data, offset: UInt32) throws {
        guard valid(offset: offset, length: UInt32(data.count)) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        try data.withUnsafeBytes { pointer in
            guard let pointer = pointer.bindMemory(to: UInt8.self).baseAddress else {
                throw Wasm3Error.invalidMemoryAccess
            }
            raw.advanced(by: Int(offset))
                .initialize(from: pointer, count: data.count)
        }
    }

    func write<T: WasmType & FixedWidthInteger>(values: [T], offset: UInt32) throws {
        var values = values
        try write(
            data: Data(bytes: &values, count: values.count * MemoryLayout<T>.size),
            offset: offset
        )
    }

    func write(string: String, offset: UInt32) throws {
        try write(data: Data(string.utf8), offset: offset)
    }
}

// MARK: Reading

public extension Memory {
    func readBytes(offset: UInt32, length: UInt32) throws -> [UInt8] {
        guard valid(offset: offset, length: length) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        let pointer = UnsafeBufferPointer(
            start: raw.advanced(by: Int(offset)),
            count: Int(length)
        )
        return [UInt8](pointer)
    }

    func readData(offset: UInt32, length: UInt32) throws -> Data {
        guard valid(offset: offset, length: length) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        return Data(bytes: raw.advanced(by: Int(offset)), count: Int(length))
    }

    func readValues<T: WasmType>(offset: UInt32, length: UInt32) throws -> [T] {
        guard valid(offset: offset, length: length) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        let pointer = UnsafeRawPointer(raw)
            .advanced(by: Int(offset))
            .bindMemory(to: T.self, capacity: Int(length))
        return (0 ..< Int(length)).map { pointer[$0] }
    }

    func readString(offset: UInt32, length: UInt32) throws -> String {
        let data = try readData(offset: offset, length: length)
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
