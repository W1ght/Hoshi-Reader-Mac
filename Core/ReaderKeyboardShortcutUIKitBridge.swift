//
//  ReaderKeyboardShortcutUIKitBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

#if canImport(UIKit)
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
        case .keyboardOpenBracket: return "["
        case .keyboardCloseBracket: return "]"
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
            return normalizedCharacterKey(character)
        }
    }

    private static func normalizedCharacterKey(_ character: Character) -> String {
        switch character {
        case "[", "［", "【", "「", "『", "〔", "〖", "〘", "〚":
            return "["
        case "]", "］", "】", "」", "』", "〕", "〗", "〙", "〛":
            return "]"
        default:
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
#elseif canImport(AppKit)
import AppKit

extension ReaderKeyboardShortcut {
    init?(nsEvent event: NSEvent) {
        guard let keyValue = Self.keyValue(for: event) else {
            return nil
        }

        key = keyValue
        modifiers = Self.eventModifiers(from: event.modifierFlags).rawValue
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let pressed = ReaderKeyboardShortcut(nsEvent: event) else {
            return false
        }
        return pressed.key == key && pressed.modifiers == modifiers
    }

    private static func keyValue(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 33: return "["
        case 30: return "]"
        case 123: return "leftArrow"
        case 124: return "rightArrow"
        case 126: return "upArrow"
        case 125: return "downArrow"
        case 116: return "pageUp"
        case 121: return "pageDown"
        case 49: return "space"
        case 53: return nil
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first,
                  !character.isWhitespace else {
                return nil
            }
            return normalizedCharacterKey(character)
        }
    }

    private static func normalizedCharacterKey(_ character: Character) -> String {
        switch character {
        case "[", "［", "【", "「", "『", "〔", "〖", "〘", "〚":
            return "["
        case "]", "］", "】", "」", "』", "〕", "〗", "〙", "〛":
            return "]"
        default:
            return String(character)
        }
    }

    private static func eventModifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        if filtered.contains(.command) { modifiers.insert(.command) }
        if filtered.contains(.shift) { modifiers.insert(.shift) }
        if filtered.contains(.option) { modifiers.insert(.option) }
        if filtered.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
#endif
