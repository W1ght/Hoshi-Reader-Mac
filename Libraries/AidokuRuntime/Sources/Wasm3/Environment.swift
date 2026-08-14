//
//  Environment.swift
//  Wasm3
//
//  Created by Skitty on 6/18/23.
//

import Foundation
import wasm3_c

public class Environment {
    var raw: IM3Environment

    public init() throws {
        let env = m3_NewEnvironment()
        guard let env else {
            throw Wasm3Error.failedAllocation
        }
        raw = env
    }

    deinit {
        m3_FreeEnvironment(raw)
    }

    public func createRuntime(stackSize: UInt32) throws -> Runtime {
        try Runtime(env: self, stackSize: stackSize)
    }

    public func parseModule(bytes: [UInt8]) throws -> ParsedModule {
        try ParsedModule.parse(env: self, bytes: bytes)
    }
}

extension Environment: Equatable {
    public static func == (lhs: Environment, rhs: Environment) -> Bool {
        lhs.raw == rhs.raw
    }
}
