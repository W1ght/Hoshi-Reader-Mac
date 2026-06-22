import AppKit
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum ShortcutEventSignatureTests {
    static func main() {
        let first = ShortcutEventSignature(
            keyCode: 123,
            modifiers: NSEvent.ModifierFlags.shift.rawValue,
            timestamp: 42.125
        )
        let rewrapped = ShortcutEventSignature(
            keyCode: 123,
            modifiers: NSEvent.ModifierFlags.shift.rawValue,
            timestamp: 42.125
        )
        let nextPress = ShortcutEventSignature(
            keyCode: 123,
            modifiers: NSEvent.ModifierFlags.shift.rawValue,
            timestamp: 42.25
        )

        require(first == rewrapped, "rewrapped copies of one key event should share a signature")
        require(first != nextPress, "separate key presses should not be deduplicated")

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 42.125,
            windowNumber: 1,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        )!
        require(
            ShortcutEventSignature(event: event) == first,
            "NSEvent conversion should preserve the stable signature fields"
        )
        print("Shortcut event signature tests passed")
    }
}
