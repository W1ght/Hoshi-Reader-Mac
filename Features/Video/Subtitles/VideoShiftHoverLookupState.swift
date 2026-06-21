struct VideoShiftHoverLookupState {
    private(set) var isShiftPressed = false
    private(set) var hasHoverPoint = false

    @discardableResult
    mutating func setShiftPressed(_ pressed: Bool) -> Bool {
        isShiftPressed = pressed
        return shouldSchedule
    }

    @discardableResult
    mutating func setHoverPointAvailable(_ available: Bool) -> Bool {
        hasHoverPoint = available
        return shouldSchedule
    }

    func pointerMoved() -> Bool {
        shouldSchedule
    }

    mutating func cancel() {
        isShiftPressed = false
        hasHoverPoint = false
    }

    static func normalizedDelayMilliseconds(_ value: Int) -> Int {
        min(max(value, 0), 1_000)
    }

    private var shouldSchedule: Bool {
        isShiftPressed && hasHoverPoint
    }
}
