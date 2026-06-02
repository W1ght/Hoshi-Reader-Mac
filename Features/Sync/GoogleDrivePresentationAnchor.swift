//
//  GoogleDrivePresentationAnchor.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AuthenticationServices

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum GoogleDrivePresentationAnchor {
    @MainActor
    static func current() -> ASPresentationAnchor {
        #if canImport(UIKit)
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let windowScene else {
            return UIWindow()
        }
        return windowScene.keyWindow ?? windowScene.windows.first ?? UIWindow(windowScene: windowScene)
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSWindow()
        #endif
    }
}
