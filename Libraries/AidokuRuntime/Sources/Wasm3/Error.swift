//
//  Error.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

public enum Wasm3Error: Error, Equatable {
    case failedAllocation
    case invalidMemoryAccess
    case invalidSignature
    case mismatchedEnvironments
    case missingFunction

    // parse errors
    case incompatibleWasmVersion
    case wasmUnderrun

    // link errors
    case functionLookupFailed
    case missingImportedFunction

    // fallback
    case wasm3Error(String)

    init(ffiResult: M3Result) {
        switch ffiResult {
            case m3Err_incompatibleWasmVersion:
                self = .incompatibleWasmVersion
            case m3Err_wasmUnderrun:
                self = .wasmUnderrun
            case m3Err_functionLookupFailed:
                self = .functionLookupFailed
            case m3Err_functionImportMissing:
                self = .missingImportedFunction
            default:
                let string = String(cString: ffiResult)
                if string == "function signature mismatch" {
                    self = .invalidSignature
                } else {
                    self = .wasm3Error(string)
                }
        }
    }
}

// TODO: traps https://docs.rs/wasm3/0.3.1/src/wasm3/error.rs.html
