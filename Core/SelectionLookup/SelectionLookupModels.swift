import CoreGraphics
import Foundation

struct SelectionSnapshot: Equatable {
    let text: String
}

enum SelectionLookupError: Error, Equatable {
    case permissionRequired
    case noSelection
    case unsupported
    case readFailed
}

enum SelectionTextValidator {
    static func validate(_ text: String?) -> Result<SelectionSnapshot, SelectionLookupError> {
        guard let text else { return .failure(.unsupported) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.noSelection) }
        return .success(SelectionSnapshot(text: trimmed))
    }
}

enum QuickLookupPanelGeometry {
    static func frame(
        anchor: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGRect {
        let clampedSize = CGSize(
            width: min(max(0, size.width), visibleFrame.width),
            height: min(max(0, size.height), visibleFrame.height)
        )

        var x = anchor.x + gap
        if x + clampedSize.width > visibleFrame.maxX {
            x = anchor.x - gap - clampedSize.width
        }

        var y = anchor.y - gap - clampedSize.height
        if y < visibleFrame.minY {
            y = anchor.y + gap
        }

        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - clampedSize.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - clampedSize.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: clampedSize)
    }
}
