//
//  Type.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

public protocol WasmType {}

// default wasm types
extension Int32: WasmType {}
extension Int64: WasmType {}
extension Float32: WasmType {}
extension Float64: WasmType {}

// types we can also support to make life easier
extension Int: WasmType {}
extension UInt32: WasmType {}
extension UInt64: WasmType {}

func typeToM3Value(_ type: WasmType.Type) -> UInt8 {
    switch type {
        case is Int32.Type, is UInt32.Type: UInt8(c_m3Type_i32.rawValue)
        case is Int64.Type, is UInt64.Type, is Int.Type: UInt8(c_m3Type_i32.rawValue)
        case is Float32.Type: UInt8(c_m3Type_f32.rawValue)
        case is Float64.Type: UInt8(c_m3Type_f64.rawValue)
        default: UInt8(c_m3Type_unknown.rawValue)
    }
}

// MARK: Safe Integer Conversion

extension Int32 {
    init(safe value: UInt32) {
        if value > UInt32(Self.max) {
            self = Self(-value.distance(to: UInt32.max) - 1)
        } else {
            self = Self(value)
        }
    }
}

extension Int64 {
    init(safe value: UInt64) {
        let max = UInt64(Self.max)
        if value > max {
            self = Self(-value.distance(to: UInt64.max) - 1)
        } else {
            self = Self(value)
        }
    }
}

extension UInt32 {
    init(safe value: Int32) {
        if value < 0 {
            self = Self.max - Self(value.distance(to: -1))
        } else {
            self = Self(value)
        }
    }
}

extension UInt64 {
    init(safe value: Int64) {
        if value < 0 {
            self = Self.max - Self(value.distance(to: -1))
        } else {
            self = Self(value)
        }
    }
}
