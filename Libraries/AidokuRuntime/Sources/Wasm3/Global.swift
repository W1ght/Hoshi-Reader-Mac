//
//  Global.swift
//  Wasm3
//
//  Created by Skitty on 7/16/23.
//

import Foundation
import wasm3_c

public class Global<T: WasmType> {
    var raw: IM3Global
    public var type: T.Type

    init(type: T.Type, raw: IM3Global) {
        self.type = type
        self.raw = raw
    }

    func value() throws -> T {
        let value = UnsafeMutablePointer<M3TaggedValue>.allocate(capacity: 1)
        defer { value.deallocate() }
        let result = m3_GetGlobal(raw, value)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
        // swiftlint:disable force_cast
        switch type {
            case is Int32.Type: return Int32(safe: value.pointee.value.i32) as! T
            case is Int64.Type: return Int64(safe: value.pointee.value.i64) as! T
            case is Float32.Type: return value.pointee.value.f32 as! T
            case is Float64.Type: return value.pointee.value.f64 as! T
            case is Int.Type: return Int(Int64(safe: value.pointee.value.i64)) as! T
            case is UInt32.Type: return value.pointee.value.i32 as! T
            case is UInt64.Type: return value.pointee.value.i64 as! T
            default: throw Wasm3Error.invalidSignature
        }
        // swiftlint:enable force_cast
    }

    func set(_ value: T) throws {
        let type = M3ValueType(rawValue: UInt32(typeToM3Value(type)))
        // swiftlint:disable force_cast
        let value = switch T.self {
            case is Int32.Type: M3ValueUnion(i32: UInt32(safe: value as! Int32))
            case is Int64.Type: M3ValueUnion(i64: UInt64(safe: value as! Int64))
            case is Float32.Type: M3ValueUnion(f32: value as! Float32)
            case is Float64.Type: M3ValueUnion(f64: value as! Float64)
            case is Int.Type: M3ValueUnion(i64: UInt64(safe: Int64(value as! Int)))
            case is UInt32.Type: M3ValueUnion(i32: value as! UInt32)
            case is UInt64.Type: M3ValueUnion(i64: value as! UInt64)
            default: throw Wasm3Error.invalidSignature
        }
        // swiftlint:enable force_cast
        var taggedValue = M3TaggedValue(type: type, value: value)
        let result = m3_SetGlobal(raw, &taggedValue)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
    }
}
