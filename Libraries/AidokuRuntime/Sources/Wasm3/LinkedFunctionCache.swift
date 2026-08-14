//
//  LinkedFunctionCache.swift
//  Wasm3
//
//  Created by Skitty on 6/8/25.
//

import Foundation

// A (hopefully) thread-safe cache for storing linked functions.
final class LinkedFunctionCache: @unchecked Sendable {
    typealias Key = UnsafeRawPointerBox

    private var storage: [Key: LinkedFunctionHolder] = [:]
    private let queue = DispatchQueue(label: "Wasm3.LinkedFunctionCache")

    func set(_ value: @escaping LinkedFunctionSignature, for key: Key) {
        let value = LinkedFunctionHolder(function: value)
        queue.sync {
            self.storage[key] = value
        }
    }

    func get(_ key: Key) -> LinkedFunctionHolder? {
        var result: LinkedFunctionHolder?
        queue.sync {
            result = self.storage[key]
        }
        return result
    }

//    func remove(_ key: Key) {
//        queue.async {
//            self.storage.removeValue(forKey: key)
//        }
//    }

//    func removeAll() {
//        queue.async {
//            self.storage.removeAll()
//        }
//    }
}

// (stack, memory) -> trap?
typealias LinkedFunctionSignature = (
    UnsafeMutablePointer<UInt64>?, UnsafeMutableRawPointer?
) -> UnsafeRawPointer?

// since pointers aren't marked as Sendable, we have to add @unchecked conformance
// should be safe since functions should only be used on a single thread
struct LinkedFunctionHolder: @unchecked Sendable {
    let function: LinkedFunctionSignature
}

struct UnsafeRawPointerBox: @unchecked Sendable, Hashable {
    let inner: UnsafeRawPointer

    init(_ inner: UnsafeRawPointer) {
        self.inner = inner
    }
}
