//
//  LocalAudioEndpoint.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

enum LocalAudioEndpoint {
    static let port: UInt16 = 18765
    static let url = "http://localhost:\(port)/localaudio/get/?term={term}&reading={reading}"
}
