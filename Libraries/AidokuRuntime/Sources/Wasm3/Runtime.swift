//
//  Runtime.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

public class Runtime {
    internal var raw: IM3Runtime
    private var env: Environment
    private var moduleData: [[UInt8]] = []

    public init(env: Environment, stackSize: UInt32) throws {
        let runtime = m3_NewRuntime(env.raw, stackSize, nil)
        guard let runtime else {
            throw Wasm3Error.failedAllocation
        }
        raw = runtime
        self.env = env
    }

    deinit {
        // frees runtime and all loaded modules
        m3_FreeRuntime(raw)
    }

    public func parseAndLoadModule(bytes: [UInt8]) throws -> Module {
        try loadModule(module: Module.parse(env: env, bytes: bytes))
    }

    public func loadModule(module: ParsedModule) throws -> Module {
        if env != module.env {
            throw Wasm3Error.mismatchedEnvironments
        }
        let mod: IM3Module? = module.raw
        let result = m3_LoadModule(raw, mod)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
        guard let mod else {
            throw Wasm3Error.failedAllocation
        }
        // module data needs to stay alive, so we store it in the runtime
        moduleData.append(module.data)
        return Module(runtime: self, raw: mod)
    }

    public func findFunction(name: String) -> Function? {
        for module in modules() {
            if let fun = try? module.findFunction(name: name) {
                return fun
            }
        }
        return nil
    }

    public func findModule(name: String) -> Module? {
        var ptr: IM3Module? = raw.pointee.modules
        while ptr != nil {
            if String(cString: ptr!.pointee.name) == name {
                return Module(runtime: self, raw: ptr!)
            }
            ptr = ptr?.pointee.next
        }
        return nil
    }

    public func modules() -> [Module] {
        var modules: [Module] = []
        var ptr: IM3Module? = raw.pointee.modules
        while ptr != nil {
            modules.append(Module(runtime: self, raw: ptr!))
            ptr = ptr?.pointee.next
        }
        return modules
    }

    public func resizeMemory(numPages: UInt32) throws {
        let result = ResizeMemory(raw, numPages)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
    }

    public func memory() throws -> Memory {
        var size: UInt32 = 0
        guard let pointer = m3_GetMemory(raw, &size, 0) else {
            throw Wasm3Error.invalidMemoryAccess
        }
        return Memory(raw: pointer, size: size)
    }

    public func memory(from pointer: UnsafeMutableRawPointer) -> Memory {
        let size = m3_GetMemorySize(raw)
        let pointer = pointer.assumingMemoryBound(to: UInt8.self)
        return Memory(raw: pointer, size: size)
    }
}
