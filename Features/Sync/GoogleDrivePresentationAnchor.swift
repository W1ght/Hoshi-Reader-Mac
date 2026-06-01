//
//  GoogleDrivePresentationAnchor.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AuthenticationServices
import UIKit

enum GoogleDrivePresentationAnchor {
    @MainActor
    static func current() -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let windowScene else {
            return UIWindow()
        }
        return windowScene.keyWindow ?? windowScene.windows.first ?? UIWindow(windowScene: windowScene)
    }
}
