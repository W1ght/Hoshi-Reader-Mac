//
//  ReaderKeyboardShortcutUIKitBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

extension ReaderKeyboardShortcut {
    init?(uiKey key: UIKey) {
        guard let keyValue = Self.keyValue(for: key) else {
            return nil
        }

        self.key = keyValue
        self.modifiers = Self.eventModifiers(from: key.modifierFlags).rawValue
    }

    func matches(_ key: UIKey) -> Bool {
        guard let pressed = ReaderKeyboardShortcut(uiKey: key) else {
            return false
        }
        return pressed.key == self.key && pressed.modifiers == self.modifiers
    }

    private static func keyValue(for key: UIKey) -> String? {
        switch key.keyCode {
        case .keyboardLeftArrow: return "leftArrow"
        case .keyboardRightArrow: return "rightArrow"
        case .keyboardUpArrow: return "upArrow"
        case .keyboardDownArrow: return "downArrow"
        case .keyboardPageUp: return "pageUp"
        case .keyboardPageDown: return "pageDown"
        case .keyboardSpacebar: return "space"
        case .keyboardEscape: return nil
        default:
            guard let character = key.charactersIgnoringModifiers.lowercased().first,
                  !character.isWhitespace else {
                return nil
            }
            return String(character)
        }
    }

    private static func eventModifiers(from flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
