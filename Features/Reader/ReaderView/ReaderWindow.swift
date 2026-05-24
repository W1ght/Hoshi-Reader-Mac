//
//  ReaderWindow.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

private struct DismissReaderKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct OpenReaderTabKey: EnvironmentKey {
    static let defaultValue: ((Int) -> Void)? = nil
}

extension EnvironmentValues {
    var dismissReader: (() -> Void)? {
        get { self[DismissReaderKey.self] }
        set { self[DismissReaderKey.self] = newValue }
    }

    var openReaderTab: ((Int) -> Void)? {
        get { self[OpenReaderTabKey.self] }
        set { self[OpenReaderTabKey.self] = newValue }
    }
}

@MainActor
final class ReaderWindow {
    private var window: UIWindow?
    private var windowObserver: NSObjectProtocol?
    private var onDismiss: (() -> Void)?
    private var isProgrammaticDismiss = false

    func present<Content: View>(title: String?, @ViewBuilder content: () -> Content, onDismiss: @escaping () -> Void) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        self.onDismiss = onDismiss
        let dismiss: () -> Void = { [weak self] in self?.dismiss(onDismiss: onDismiss) }
        let host = UIHostingController(rootView: AnyView(content().environment(\.dismissReader, dismiss)))
        host.title = title ?? "Reader"

        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.alpha = 0
        window.makeKeyAndVisible()
        self.window = window
        #if targetEnvironment(macCatalyst)
        scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 640)
        #endif
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeHiddenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isProgrammaticDismiss else {
                    return
                }
                self.cleanupWindow()
                self.onDismiss?()
            }
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            window.alpha = 1
        }
    }

    func dismiss(onDismiss: (() -> Void)? = nil) {
        guard let window else { return }
        isProgrammaticDismiss = true
        cleanupWindow()
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
            self.isProgrammaticDismiss = false
            onDismiss?()
        }
    }

    private func cleanupWindow() {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        self.window = nil
    }
}
