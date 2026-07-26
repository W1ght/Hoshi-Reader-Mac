//
//  HoshiShiftHoverWKWebView.swift
//  Niratan
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit
import WebKit

private final class HoshiShiftHoverWKWebViewResources: @unchecked Sendable {
    var modifierFlagsMonitor: Any?
}

/// Keeps Shift-hover lookup responsive without making a hovered WebView the
/// first responder. Moving first-responder ownership between nested lookup
/// WebViews can race WebKit's asynchronous NSTextInputClient replies.
class HoshiShiftHoverWKWebView: WKWebView {
    private let shiftHoverResources = HoshiShiftHoverWKWebViewResources()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeShiftHoverModifierMonitor()
        guard window != nil else { return }

        shiftHoverResources.modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  self.containsCurrentPointer(in: window) else {
                return event
            }

            let isShiftPressed = event.modifierFlags.contains(.shift)
            self.evaluateJavaScript(
                "window.hoshiSelection?.setNativeShiftPressed?.(\(isShiftPressed ? "true" : "false"));"
            )
            return event
        }
    }

    @discardableResult
    func relinquishTextInputFocus() -> Bool {
        guard let window,
              let firstResponderView = window.firstResponder as? NSView,
              firstResponderView === self || firstResponderView.isDescendant(of: self) else {
            return false
        }
        return window.makeFirstResponder(nil)
    }

    deinit {
        let resources = shiftHoverResources
        Task { @MainActor in
            if let modifierFlagsMonitor = resources.modifierFlagsMonitor {
                NSEvent.removeMonitor(modifierFlagsMonitor)
            }
        }
    }

    private func containsCurrentPointer(in window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard let hitView = contentView.hitTest(contentPoint) else { return false }
        return hitView === self || hitView.isDescendant(of: self)
    }

    private func removeShiftHoverModifierMonitor() {
        guard let modifierFlagsMonitor = shiftHoverResources.modifierFlagsMonitor else {
            return
        }
        NSEvent.removeMonitor(modifierFlagsMonitor)
        shiftHoverResources.modifierFlagsMonitor = nil
    }
}
