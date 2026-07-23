import CoreGraphics
import Foundation
import SwiftUI

nonisolated enum VideoSubtitleEdgeStyle: String, CaseIterable, Codable {
    case off
    case softShadow
    case clearOutline
    case highContrast

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .softShadow: "Soft Shadow"
        case .clearOutline: "Clear Outline"
        case .highContrast: "High Contrast"
        }
    }
}

nonisolated struct VideoSubtitleEdgePreference: Equatable {
    let style: VideoSubtitleEdgeStyle
    let strength: Double
}

nonisolated enum VideoSubtitleEdgePreferenceResolver {
    static func normalizedStrength(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    static func resolve(
        edgeStyleRawValue: String?,
        edgeStrength: Double?,
        legacyShadowRadius: Double?
    ) -> VideoSubtitleEdgePreference {
        if let edgeStyleRawValue {
            return VideoSubtitleEdgePreference(
                style: VideoSubtitleEdgeStyle(rawValue: edgeStyleRawValue) ?? .highContrast,
                strength: normalizedStrength(edgeStrength)
            )
        }
        if let legacyShadowRadius {
            return VideoSubtitleEdgePreference(
                style: .softShadow,
                strength: normalizedStrength(legacyShadowRadius / 10)
            )
        }
        return VideoSubtitleEdgePreference(style: .highContrast, strength: 0.5)
    }
}

nonisolated struct VideoSubtitleEdgeRecipe: Equatable {
    let shadowRadius: CGFloat
    let shadowPassCount: Int
    let outlineWidth: CGFloat

    static let none = VideoSubtitleEdgeRecipe(
        shadowRadius: 0,
        shadowPassCount: 0,
        outlineWidth: 0
    )

    var layoutAllowance: CGFloat {
        ceil(max(shadowRadius * 2, outlineWidth * 2))
    }

    static func make(
        style: VideoSubtitleEdgeStyle,
        strength: Double,
        fontSize: CGFloat
    ) -> VideoSubtitleEdgeRecipe {
        let normalized = CGFloat(VideoSubtitleEdgePreferenceResolver.normalizedStrength(strength))
        guard style != .off, normalized > 0 else { return .none }
        let scale = min(max(fontSize / 36, 0.5), 2)
        let shadowRadius = min(8, 6 * normalized * scale)
        let clearOutlineWidth = min(4, 2.5 * normalized * scale)

        switch style {
        case .off:
            return .none
        case .softShadow:
            return VideoSubtitleEdgeRecipe(
                shadowRadius: shadowRadius,
                shadowPassCount: 1,
                outlineWidth: 0
            )
        case .clearOutline:
            return VideoSubtitleEdgeRecipe(
                shadowRadius: 0,
                shadowPassCount: 0,
                outlineWidth: clearOutlineWidth
            )
        case .highContrast:
            return VideoSubtitleEdgeRecipe(
                shadowRadius: 0,
                shadowPassCount: 0,
                outlineWidth: min(2.5, clearOutlineWidth * 1.5)
            )
        }
    }
}
