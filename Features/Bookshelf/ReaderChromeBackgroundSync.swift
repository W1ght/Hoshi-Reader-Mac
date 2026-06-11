//
//  ReaderChromeBackgroundSync.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

#if canImport(UIKit)
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
#elseif canImport(AppKit)
import AppKit

struct ReaderChromeBackgroundSync: NSViewRepresentable {
    var isActive: Bool
    var backgroundColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.update(
                from: view,
                isActive: isActive,
                backgroundColor: NSColor(backgroundColor)
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(
                from: nsView,
                isActive: isActive,
                backgroundColor: NSColor(backgroundColor)
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.restore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var originalWindowBackground: NSColor?
        private var originalContentBackground: CGColor?
        private var originalWantsLayer = false

        func update(from view: NSView, isActive: Bool, backgroundColor: NSColor) {
            guard let window = view.window else {
                return
            }

            if self.window !== window {
                restore()
                self.window = window
                originalWindowBackground = window.backgroundColor
                originalWantsLayer = window.contentView?.wantsLayer ?? false
                originalContentBackground = window.contentView?.layer?.backgroundColor
            }

            guard isActive else {
                restore()
                return
            }

            window.backgroundColor = backgroundColor
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = backgroundColor.cgColor
        }

        func restore() {
            guard let window else {
                return
            }
            window.backgroundColor = originalWindowBackground
            window.contentView?.layer?.backgroundColor = originalContentBackground
            window.contentView?.wantsLayer = originalWantsLayer
            self.window = nil
            originalWindowBackground = nil
            originalContentBackground = nil
            originalWantsLayer = false
        }
    }
}
#endif
