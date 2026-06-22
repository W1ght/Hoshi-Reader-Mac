import AppKit
import Foundation

struct ShortcutEventSignature: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags.RawValue
    private let timestampMicroseconds: Int64

    init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags.RawValue,
        timestamp: TimeInterval
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        timestampMicroseconds = Int64((timestamp * 1_000_000).rounded())
    }

    init(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .rawValue,
            timestamp: event.timestamp
        )
    }
}
