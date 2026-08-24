//
//  NativeReaderWheelNavigation.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

nonisolated enum NativeReaderWheelNavigation: Equatable, Sendable {
    case backward
    case forward
}

nonisolated enum NativeReaderWheelNavigationResolver {
    static func navigation(
        deltaX: Double,
        deltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        hasMomentum: Bool
    ) -> NativeReaderWheelNavigation? {
        guard !hasPreciseScrollingDeltas,
              !hasMomentum,
              deltaY != 0,
              abs(deltaY) >= abs(deltaX) else {
            return nil
        }
        return deltaY < 0 ? .forward : .backward
    }
}

nonisolated struct NativeReaderWheelNavigationAccumulator {
    static let defaultThreshold = 1.0

    private var accumulatedDeltaY = 0.0

    mutating func consume(
        deltaX: Double,
        deltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        hasMomentum: Bool,
        threshold: Double = Self.defaultThreshold
    ) -> NativeReaderWheelNavigation? {
        guard let navigation = NativeReaderWheelNavigationResolver.navigation(
            deltaX: deltaX,
            deltaY: deltaY,
            hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
            hasMomentum: hasMomentum
        ) else {
            reset()
            return nil
        }

        if accumulatedDeltaY != 0,
           accumulatedDeltaY.sign != deltaY.sign {
            accumulatedDeltaY = 0
        }
        accumulatedDeltaY += deltaY
        guard abs(accumulatedDeltaY) >= threshold else {
            return nil
        }
        accumulatedDeltaY = 0
        return navigation
    }

    mutating func reset() {
        accumulatedDeltaY = 0
    }
}

nonisolated enum NativeReaderTrackpadGesturePhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
    case none
}

nonisolated struct NativeReaderTrackpadNavigationAccumulator {
    static let defaultThreshold = 60.0

    private var accumulatedDeltaY = 0.0
    private var didNavigateInCurrentGesture = false

    mutating func consume(
        deltaX: Double,
        deltaY: Double,
        phase: NativeReaderTrackpadGesturePhase,
        hasMomentum: Bool,
        threshold: Double = Self.defaultThreshold
    ) -> NativeReaderWheelNavigation? {
        if phase == .ended || phase == .cancelled {
            reset()
            return nil
        }
        guard !hasMomentum else {
            return nil
        }
        if phase == .began {
            reset()
        }
        guard phase == .began || phase == .changed,
              !didNavigateInCurrentGesture,
              deltaY != 0,
              abs(deltaY) >= abs(deltaX) else {
            return nil
        }

        if accumulatedDeltaY != 0,
           accumulatedDeltaY.sign != deltaY.sign {
            accumulatedDeltaY = 0
        }
        accumulatedDeltaY += deltaY
        guard abs(accumulatedDeltaY) >= threshold else {
            return nil
        }
        accumulatedDeltaY = 0
        didNavigateInCurrentGesture = true
        return deltaY < 0 ? .forward : .backward
    }

    mutating func reset() {
        accumulatedDeltaY = 0
        didNavigateInCurrentGesture = false
    }
}
