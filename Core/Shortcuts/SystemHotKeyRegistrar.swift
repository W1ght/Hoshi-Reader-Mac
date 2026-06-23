import Carbon
import Foundation
import SwiftUI

struct SystemHotKeyDescriptor: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init?(binding: KeyboardShortcutBinding) {
        guard let keyCode = binding.keyCode ?? Self.inferredKeyCode(for: binding.key) else {
            return nil
        }
        self.keyCode = UInt32(keyCode)
        self.modifiers = Self.carbonModifiers(for: binding.eventModifiers)
    }

    private static func carbonModifiers(for modifiers: SwiftUI.EventModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func inferredKeyCode(for key: String) -> UInt16? {
        let keys: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            "space": kVK_Space, "escape": kVK_Escape,
            "leftArrow": kVK_LeftArrow, "rightArrow": kVK_RightArrow,
            "upArrow": kVK_UpArrow, "downArrow": kVK_DownArrow,
            "pageUp": kVK_PageUp, "pageDown": kVK_PageDown
        ]
        return keys[key].map(UInt16.init)
    }
}

enum SystemHotKeyRegistrationStatus: Equatable {
    case inactive
    case registered
    case unsupportedBinding
    case conflict
    case failed(OSStatus)
}

@MainActor
final class SystemHotKeyRegistrar {
    private static let signature: OSType = 0x48534C55 // HSLU
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private lazy var eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == SystemHotKeyRegistrar.signature,
              hotKeyID.id == SystemHotKeyRegistrar.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        let registrar = Unmanaged<SystemHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                registrar.action?()
            }
        }
        return noErr
    }

    func register(binding: KeyboardShortcutBinding, action: @escaping () -> Void) -> SystemHotKeyRegistrationStatus {
        unregister()
        guard let descriptor = SystemHotKeyDescriptor(binding: binding) else {
            return .unsupportedBinding
        }
        guard descriptor.modifiers != 0 else {
            return .unsupportedBinding
        }
        installEventHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            self.action = nil
            return status == OSStatus(eventHotKeyExistsErr) ? .conflict : .failed(status)
        }
        hotKeyRef = reference
        self.action = action
        return .registered
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        action = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}
