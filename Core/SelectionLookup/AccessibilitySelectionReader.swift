import AppKit
import ApplicationServices
import Carbon
import Foundation

protocol AccessibilitySelectionReading {
    var isTrusted: Bool { get }
    func requestAccess()
    func readSelectedText() -> Result<SelectionSnapshot, SelectionLookupError>
}

struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            let copiedItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copiedItem.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copiedItem.setString(string, forType: type)
                }
            }
            return copiedItem
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}

struct CopyShortcutSelectionFallback {
    var pasteboard: NSPasteboard = .general
    var timeout: TimeInterval = 0.22
    var pollInterval: TimeInterval = 0.02

    func readSelectedText() -> Result<SelectionSnapshot, SelectionLookupError> {
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }

        guard postCopyShortcut() else {
            return .failure(.readFailed)
        }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if pasteboard.changeCount != clearedChangeCount {
                let result = SelectionTextValidator.validate(pasteboard.string(forType: .string))
                if case .success = result {
                    return result
                }
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline

        return SelectionTextValidator.validate(pasteboard.string(forType: .string))
    }

    private func postCopyShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: false
              ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

struct AccessibilitySelectionReader: AccessibilitySelectionReading {
    var copyFallback = CopyShortcutSelectionFallback()

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText() -> Result<SelectionSnapshot, SelectionLookupError> {
        guard isTrusted else { return .failure(.permissionRequired) }
        let accessibilityResult = readAccessibilitySelectedText()
        if case .success = accessibilityResult {
            return accessibilityResult
        }

        guard case .failure(let error) = accessibilityResult,
              SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: error) else {
            return accessibilityResult
        }
        return copyFallback.readSelectedText()
    }

    private func readAccessibilitySelectedText() -> Result<SelectionSnapshot, SelectionLookupError> {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .failure(.readFailed)
        }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        if selectedStatus == .attributeUnsupported || selectedStatus == .noValue {
            return .failure(.unsupported)
        }
        guard selectedStatus == .success else {
            return .failure(.readFailed)
        }
        return SelectionTextValidator.validate(selectedValue as? String)
    }
}
