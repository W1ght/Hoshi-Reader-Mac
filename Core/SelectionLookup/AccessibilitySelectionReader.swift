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

    func readSelectedText(screenBounds: CGRect? = nil) -> Result<SelectionSnapshot, SelectionLookupError> {
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
                let result = SelectionTextValidator.validate(
                    pasteboard.string(forType: .string),
                    screenBounds: screenBounds
                )
                if case .success = result {
                    return result
                }
            }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline

        return SelectionTextValidator.validate(
            pasteboard.string(forType: .string),
            screenBounds: screenBounds
        )
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
        let focusedResult = focusedElement()
        let screenBounds: CGRect?
        let accessibilityResult: Result<SelectionSnapshot, SelectionLookupError>
        switch focusedResult {
        case .success(let focusedElement):
            screenBounds = selectedTextScreenBounds(focusedElement: focusedElement)
            accessibilityResult = readAccessibilitySelectedText(
                focusedElement: focusedElement,
                screenBounds: screenBounds
            )
        case .failure(let error):
            screenBounds = nil
            accessibilityResult = .failure(error)
        }
        if case .success = accessibilityResult {
            return accessibilityResult
        }

        guard case .failure(let error) = accessibilityResult,
              SelectionLookupFallbackDecision.shouldAttemptCopyShortcut(after: error) else {
            return accessibilityResult
        }
        return copyFallback.readSelectedText(screenBounds: screenBounds)
    }

    private func focusedElement() -> Result<AXUIElement, SelectionLookupError> {
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

        return .success(unsafeDowncast(focusedValue, to: AXUIElement.self))
    }

    private func readAccessibilitySelectedText(
        focusedElement: AXUIElement,
        screenBounds: CGRect?
    ) -> Result<SelectionSnapshot, SelectionLookupError> {
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
        return SelectionTextValidator.validate(
            selectedValue as? String,
            screenBounds: screenBounds
        )
    }

    private func selectedTextScreenBounds(focusedElement: AXUIElement) -> CGRect? {
        var selectedRangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )
        guard rangeStatus == .success,
              let selectedRangeValue,
              CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsValue
        )
        guard boundsStatus == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var accessibilityBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &accessibilityBounds) else {
            return nil
        }
        return QuickLookupPanelGeometry.appKitScreenRect(
            accessibilityBounds: accessibilityBounds,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }
}
