//
//  ReaderKeyboardShortcutAppKitBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import AppKit

extension KeyboardShortcutBinding {
    init?(nsEvent event: NSEvent) {
        guard let keyValue = Self.keyValue(for: event) else {
            return nil
        }

        key = keyValue
        modifiers = Self.eventModifiers(from: event.modifierFlags).rawValue
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let pressed = KeyboardShortcutBinding(nsEvent: event) else {
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
        case 53: return "escape"
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
