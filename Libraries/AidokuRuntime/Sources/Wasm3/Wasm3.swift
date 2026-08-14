//
//  Wasm3.swift
//  Wasm3
//
//  Created by Skitty on 5/27/25.
//

import wasm3_support

public enum Wasm3 {
    public static func yieldNext() {
        set_should_yield_next()
    }
}
