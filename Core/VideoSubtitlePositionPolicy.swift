import CoreGraphics
import Foundation

nonisolated enum VideoSubtitlePositionPolicy {
    static let range: ClosedRange<Double> = 0...1
    static let defaultPosition = 0.9
    private static let legacyMaximumMagnitude = 200.0

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPosition }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func migratedLegacyPosition(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return defaultPosition }
        if value >= 0 {
            let progress = min(value / legacyMaximumMagnitude, 1)
            return defaultPosition * (1 - progress)
        }
        let progress = min(-value / legacyMaximumMagnitude, 1)
        return defaultPosition + (1 - defaultPosition) * progress
    }

    static func originY(
        viewportHeight: CGFloat,
        subtitleHeight: CGFloat,
        position: Double
    ) -> CGFloat {
        guard viewportHeight.isFinite,
              subtitleHeight.isFinite,
              viewportHeight >= 0,
              subtitleHeight >= 0 else {
            return 0
        }
        let availableTravel = max(viewportHeight - subtitleHeight, 0)
        return availableTravel * CGFloat(normalized(position))
    }
}
