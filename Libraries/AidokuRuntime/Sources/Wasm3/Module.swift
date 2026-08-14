//
//  Module.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

// MARK: - Parsed Module

public class ParsedModule {
    var data: [UInt8]
    var raw: IM3Module?
    var env: Environment

    init(env: Environment, bytes: [UInt8]) throws {
        let mod = UnsafeMutablePointer<IM3Module?>.allocate(capacity: 1)
        defer {
            mod.deallocate()
        }
        let result = m3_ParseModule(env.raw, mod, bytes, UInt32(bytes.count))
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
        guard let mod = mod.pointee else {
            throw Wasm3Error.failedAllocation
        }
        self.data = bytes
        self.raw = mod
        self.env = env
    }

    public static func parse(env: Environment, bytes: [UInt8]) throws -> ParsedModule {
        try ParsedModule(env: env, bytes: bytes)
    }
}

// MARK: - Module

public class Module {
    private var id = UUID()

    var raw: IM3Module
    public var runtime: Runtime

    private static let linkedFunctionCache = LinkedFunctionCache()

    public static func parse(env: Environment, bytes: [UInt8]) throws -> ParsedModule {
        try ParsedModule.parse(env: env, bytes: bytes)
    }

    init(runtime: Runtime, raw: IM3Module) {
        self.runtime = runtime
        self.raw = raw
    }

    public func findFunction(name: String) throws -> Function {
        var fun: IM3Function?
        let result = m3_FindFunction(&fun, runtime.raw, name)
        if let fun {
            return Function(runtime: runtime, raw: fun)
        } else {
            if let result {
                throw Wasm3Error(ffiResult: result)
            } else {
                throw Wasm3Error.missingFunction
            }
        }
    }

    public func function(index: Int) -> Function? {
        guard index >= 0 else { return nil }
        let numFunctions = raw.pointee.numFunctions
        guard numFunctions > 0, numFunctions < index else {
            return nil
        }
        var fnPointer = raw.pointee.functions[index]
        let fun = Function(runtime: runtime, raw: &fnPointer)
        try? fun.compile()
        return fun
    }

    public func name() -> String? {
        String(cString: raw.pointee.name)
    }

    public func linkWasi() throws {
        let result = m3_LinkWASI(raw)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
    }
}

// MARK: Linking

extension Module {
    private func typeToSignature(_ type: WasmType.Type) -> String? {
        switch type {
            case is Int32.Type, is UInt32.Type: "i"
            case is Int64.Type, is UInt64.Type, is Int.Type: "I"
            case is Float32.Type: "f"
            case is Float64.Type: "F"
            default: nil
        }
    }

    private func linkFunction(
        name: String,
        namespace: String,
        signature: String,
        function: @escaping LinkedFunctionSignature
    ) throws {
        guard
            let context = UnsafeMutableRawPointer(
                bitPattern: (id.uuidString + namespace + name).hashValue
            )
        else {
            throw Wasm3Error.failedAllocation
        }

        // save linked functions in a cache to be accessed from handler
        Self.linkedFunctionCache.set(function, for: .init(context))

        func handler(
            _: UnsafeMutablePointer<M3Runtime>?,
            _ context: UnsafeMutablePointer<M3ImportContext>?,
            _ stackPointer: UnsafeMutablePointer<UInt64>?,
            _ memory: UnsafeMutableRawPointer?
        ) -> UnsafeRawPointer? {
            guard
                let userData = context?.pointee.userdata,
                // swiftlint:disable:next prefer_self_in_static_references
                let function = Module.linkedFunctionCache.get(.init(userData))?.function
            else {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            return function(stackPointer, memory)
        }

        let result = m3_LinkRawFunctionEx(raw, namespace, name, signature, handler, context)
        if let result {
            let error = Wasm3Error(ffiResult: result)
            // Aidoku host imports are optional per source. Wasm3 reports a
            // lookup failure when this module does not import the function;
            // that is not a signature or linkage error.
            if error == .functionLookupFailed { return }
            throw error
        }
    }

    private static func argument<T: WasmType>(
        from stack: UnsafeMutablePointer<UInt64>?,
        at index: Int,
        // swiftlint:disable:next unused_parameter
        as type: T.Type
    ) throws -> T {
        guard let stack = UnsafeMutableRawPointer(stack)
        else { throw Wasm3Error.invalidMemoryAccess }
        return stack.load(
            fromByteOffset: index * MemoryLayout<Int64>.stride,
            as: T.self
        )
    }

    private static func storeReturn<Ret: WasmType>(value: Ret, stack: UnsafeMutablePointer<UInt64>?) throws {
        guard let stack = UnsafeMutableRawPointer(stack)
        else { throw Wasm3Error.invalidMemoryAccess }
        stack.storeBytes(of: value, as: Ret.self)
    }

    public func linkFunction<each T: WasmType>(
        name: String,
        namespace: String,
        function: @escaping (repeat each T) -> Void
    ) throws {
        let functionHandler: LinkedFunctionSignature = { stack, _ in
            var counter = 0
            do {
                function(
                    repeat
                    (try Self.argument(
                        from: stack,
                        at: {
                            let ret = counter
                            counter += 1
                            return ret
                        }(),
                        as: (each T).self)
                    )
                )
            } catch {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            return nil
        }
        let tuple = (repeat typeToSignature((each T).self))
        let arr = Mirror(reflecting: tuple).children.compactMap { $0.value as? String }
        let signature = "v(\(arr.joined(separator: " ")))"
        try linkFunction(
            name: name,
            namespace: namespace,
            signature: signature,
            function: functionHandler
        )
    }

    public func linkFunction<each T: WasmType>(
        name: String,
        namespace: String,
        function: @escaping (Memory, repeat each T) -> Void
    ) throws {
        let functionHandler: LinkedFunctionSignature = { [weak self] stack, _ in
            guard let self else {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            var counter = 0
            do {
                let memory = try self.runtime.memory()
                function(
                    memory,
                    repeat
                    (try Self.argument(
                        from: stack,
                        at: {
                            let ret = counter
                            counter += 1
                            return ret
                        }(),
                        as: (each T).self)
                    )
                )
            } catch {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            return nil
        }
        let tuple = (repeat typeToSignature((each T).self))
        let arr = Mirror(reflecting: tuple).children.compactMap { $0.value as? String }
        let signature = "v(\(arr.joined(separator: " ")))"
        try linkFunction(
            name: name,
            namespace: namespace,
            signature: signature,
            function: functionHandler
        )
    }

    public func linkFunction<each T: WasmType, Ret: WasmType>(
        name: String,
        namespace: String,
        function: @escaping (repeat each T) -> Ret
    ) throws {
        let functionHandler: LinkedFunctionSignature = { stack, _ in
            var counter = 1
            do {
                let result = function(
                    repeat
                    (try Self.argument(
                        from: stack,
                        at: {
                            let ret = counter
                            counter += 1
                            return ret
                        }(),
                        as: (each T).self)
                    )
                )
                try Self.storeReturn(value: result, stack: stack)
            } catch {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            return nil
        }
        let tuple = (repeat typeToSignature((each T).self))
        let arr = Mirror(reflecting: tuple).children.compactMap { $0.value as? String }
        guard let retType = typeToSignature(Ret.self)
        else { throw Wasm3Error.invalidSignature }
        let signature = "\(retType)(\(arr.joined(separator: " ")))"
        try linkFunction(
            name: name,
            namespace: namespace,
            signature: signature,
            function: functionHandler
        )
    }

    public func linkFunction<each T: WasmType, Ret: WasmType>(
        name: String,
        namespace: String,
        function: @escaping (Memory, repeat each T) -> Ret
    ) throws {
        let functionHandler: LinkedFunctionSignature = { [weak self] stack, heap in
            guard let self, let heap else {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            var counter = 1
            do {
                let memory = self.runtime.memory(from: heap)
                let result = function(
                    memory,
                    repeat
                    (try Self.argument(
                        from: stack,
                        at: {
                            let ret = counter
                            counter += 1
                            return ret
                        }(),
                        as: (each T).self)
                    )
                )
                try Self.storeReturn(value: result, stack: stack)
            } catch {
                return UnsafeRawPointer(m3Err_trapUnreachable)
            }
            return nil
        }
        let tuple = (repeat typeToSignature((each T).self))
        let arr = Mirror(reflecting: tuple).children.compactMap { $0.value as? String }
        guard let retType = typeToSignature(Ret.self)
        else { throw Wasm3Error.invalidSignature }
        let signature = "\(retType)(\(arr.joined(separator: " ")))"
        try linkFunction(
            name: name,
            namespace: namespace,
            signature: signature,
            function: functionHandler
        )
    }
}

public extension Module {
    // wasm3 does this automatically on load
//    public func linkGlobal<T: WasmType>(
//        name: String,
//        namespace: String,
//        type: T.Type,
//        mutable: Bool
//    ) throws -> Global<T> {
//        var globalRaw: IM3Global?
//        Module_AddGlobal(raw, &globalRaw, typeToM3Value(type), mutable, true)
//        guard let globalRaw else {
//            throw Wasm3Error.failedAllocation
//        }
//        let global = Global(type: type, raw: globalRaw)
//        return global
//    }

    func findGlobal<T: WasmType>(name: String, type: T.Type) -> Global<T>? {
        let result = m3_FindGlobal(raw, name)
        guard let result else { return nil }
        return Global(type: type, raw: result)
    }
}
