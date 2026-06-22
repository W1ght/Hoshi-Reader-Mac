import AppKit
import SwiftUI

struct NativeWindowActivityReader: NSViewRepresentable {
    let onChange: @MainActor (NSWindow?, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: Coordinator) {
        coordinator.attach(to: nil)
        nsView.coordinator = nil
    }

    final class WindowTrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: @MainActor (NSWindow?, Bool) -> Void
        private weak var window: NSWindow?

        init(onChange: @escaping @MainActor (NSWindow?, Bool) -> Void) {
            self.onChange = onChange
            super.init()
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            removeObservers()
            self.window = window
            guard let window else {
                notify(window: nil, isKey: false)
                return
            }
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            center.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            notify(window: window, isKey: window.isKeyWindow)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            notify(window: window, isKey: true)
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            notify(window: window, isKey: false)
        }

        private func notify(window: NSWindow?, isKey: Bool) {
            DispatchQueue.main.async { [weak self, weak window] in
                self?.onChange(window, isKey)
            }
        }

        private func removeObservers() {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
