//
//  Function.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

public class Function {
    var raw: IM3Function
    var runtime: Runtime

    init(runtime: Runtime, raw: IM3Function) {
        self.raw = raw
        self.runtime = runtime
    }

    func compile() throws {
        let result = CompileFunction(raw)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
    }

//    private func call(_ args: [String]) throws {
//        var cStringArgs = args.map { UnsafePointer(strdup($0)) }
//        let result = m3_CallArgv(raw, UInt32(args.count), &cStringArgs)
//        cStringArgs.forEach { $0?.deallocate() }
//        if let result {
//            throw Wasm3Error(ffiResult: result)
//        }
//    }

    private func call(_ args: [WasmType]) throws {
        var argsCopy = args
        let result = argsCopy.withUnsafeMutableBufferPointer { buffer in
            var argPtrs: [UnsafeRawPointer?] = buffer.baseAddress.map { base in
                (0..<buffer.count).map { UnsafeRawPointer(base + $0) }
            } ?? []
            return m3_Call(raw, UInt32(args.count), &argPtrs)
        }
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
    }

    public func call(_ args: WasmType...) throws {
        try call(args)
    }

    public func call<Ret: WasmType>(_ args: WasmType...) throws -> Ret {
        // check that function returns a value
        let retCount = GetFunctionNumReturns(raw)
        if retCount != 1 {
            // TODO: support multiple return types (for the future, since wasm doesn't support this yet anyways)
            throw Wasm3Error.invalidSignature
        }

        // check that function return type matches
        let retType = GetFunctionReturnType(raw, 0)
        switch retType {
            case UInt8(c_m3Type_i32.rawValue):
                guard
                    Int32.self == Ret.self
                    || UInt32.self == Ret.self
                    || (Int.self == Ret.self && Int.bitWidth == Int32.bitWidth)
                else { throw Wasm3Error.invalidSignature }
            case UInt8(c_m3Type_i64.rawValue):
                guard
                    Int64.self == Ret.self
                    || UInt64.self == Ret.self
                    || (Int.self == Ret.self && Int.bitWidth == Int64.bitWidth)
                else { throw Wasm3Error.invalidSignature }
            case UInt8(c_m3Type_f32.rawValue):
                guard Float32.self == Ret.self
                else { throw Wasm3Error.invalidSignature }
            case UInt8(c_m3Type_f64.rawValue):
                guard Float64.self == Ret.self
                else { throw Wasm3Error.invalidSignature }
            default:
                throw Wasm3Error.invalidSignature
        }

        // call function
        try call(args)

        // get output
        let retPointer = UnsafeMutablePointer<Ret>.allocate(capacity: 1)
        var output: UnsafeRawPointer? = UnsafeRawPointer(retPointer)
        defer {
            retPointer.deallocate()
        }
        let result = m3_GetResults(raw, 1, &output)
        if let result {
            throw Wasm3Error(ffiResult: result)
        }
        let retValue = output?.load(as: Ret.self)
        guard let retValue else {
            throw Wasm3Error.failedAllocation
        }
        return retValue
    }
}
