//
//  GoogleDrivePresentationAnchor.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AuthenticationServices
import AppKit

enum GoogleDrivePresentationAnchor {
    @MainActor
    static func current() -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSWindow()
    }
}
