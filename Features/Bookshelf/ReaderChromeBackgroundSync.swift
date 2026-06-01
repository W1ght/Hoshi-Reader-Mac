//
//  ReaderChromeBackgroundSync.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

struct ReaderChromeBackgroundSync: UIViewControllerRepresentable {
    var isActive: Bool
    var backgroundColor: Color

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.update(
                from: controller,
                isActive: isActive,
                backgroundColor: UIColor(backgroundColor)
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(
                from: uiViewController,
                isActive: isActive,
                backgroundColor: UIColor(backgroundColor)
            )
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.restore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: UIWindow?
        private var originalWindowBackground: UIColor?
        private var originalRootBackground: UIColor?

        func update(from controller: UIViewController, isActive: Bool, backgroundColor: UIColor) {
            guard let window = controller.view.window else {
                return
            }

            if self.window !== window {
                restore()
                self.window = window
                originalWindowBackground = window.backgroundColor
                originalRootBackground = window.rootViewController?.view.backgroundColor
            }

            guard isActive else {
                restore()
                return
            }

            window.backgroundColor = backgroundColor
            window.rootViewController?.view.backgroundColor = backgroundColor
        }

        func restore() {
            guard let window else {
                return
            }
            window.backgroundColor = originalWindowBackground
            window.rootViewController?.view.backgroundColor = originalRootBackground
            self.window = nil
            originalWindowBackground = nil
            originalRootBackground = nil
        }
    }
}
