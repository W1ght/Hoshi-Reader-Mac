import ApplicationServices
import Foundation

protocol AccessibilitySelectionReading {
    var isTrusted: Bool { get }
    func requestAccess()
    func readSelectedText() -> Result<SelectionSnapshot, SelectionLookupError>
}

struct AccessibilitySelectionReader: AccessibilitySelectionReading {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText() -> Result<SelectionSnapshot, SelectionLookupError> {
        guard isTrusted else { return .failure(.permissionRequired) }

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
