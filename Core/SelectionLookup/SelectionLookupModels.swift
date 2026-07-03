import CoreGraphics
import Foundation

struct SelectionSnapshot: Equatable {
    let text: String
    var screenBounds: CGRect? = nil
}

enum SelectionLookupError: Error, Equatable {
    case permissionRequired
    case noSelection
    case unsupported
    case readFailed
}

enum SelectionTextValidator {
    static func validate(
        _ text: String?,
        screenBounds: CGRect? = nil
    ) -> Result<SelectionSnapshot, SelectionLookupError> {
        guard let text else { return .failure(.unsupported) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.noSelection) }
        return .success(SelectionSnapshot(text: trimmed, screenBounds: screenBounds))
    }
}

enum SelectionLookupFallbackDecision {
    static func shouldAttemptCopyShortcut(after error: SelectionLookupError) -> Bool {
        switch error {
        case .permissionRequired:
            false
        case .noSelection, .unsupported, .readFailed:
            true
        }
    }
}

enum AccessibilitySelectionTreeSearch {
    static func firstSelectedText<Node>(
        from root: Node,
        maxDepth: Int = 8,
        maxVisited: Int = 300,
        selectedText: (Node) -> Result<SelectionSnapshot, SelectionLookupError>,
        children: (Node) -> [Node]
    ) -> Result<SelectionSnapshot, SelectionLookupError> {
        var firstError: SelectionLookupError?
        var visitedCount = 0

        func visit(_ node: Node, depth: Int) -> SelectionSnapshot? {
            guard visitedCount < maxVisited else { return nil }
            visitedCount += 1

            switch selectedText(node) {
            case .success(let snapshot):
                return snapshot
            case .failure(let error):
                if firstError == nil {
                    firstError = error
                }
            }

            guard depth < maxDepth else { return nil }
            for child in children(node) {
                if let snapshot = visit(child, depth: depth + 1) {
                    return snapshot
                }
            }
            return nil
        }

        if let snapshot = visit(root, depth: 0) {
            return .success(snapshot)
        }
        return .failure(firstError ?? .unsupported)
    }
}

enum QuickLookupPanelGeometry {
    static func screenRect(parentFrame: CGRect, localRect: CGRect) -> CGRect {
        CGRect(
            x: parentFrame.minX + localRect.minX,
            y: parentFrame.maxY - localRect.maxY,
            width: max(localRect.width, 1),
            height: max(localRect.height, 1)
        )
    }

    static func screenAnchor(parentFrame: CGRect, localRect: CGRect) -> CGPoint {
        let rect = screenRect(parentFrame: parentFrame, localRect: localRect)
        return CGPoint(x: rect.maxX, y: rect.midY)
    }

    static func appKitScreenRect(accessibilityBounds: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: accessibilityBounds.minX,
            y: screenFrame.maxY - accessibilityBounds.maxY,
            width: max(accessibilityBounds.width, 1),
            height: max(accessibilityBounds.height, 1)
        )
    }

    static func appKitScreenRect(
        accessibilityBounds: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        guard accessibilityBounds.width.isFinite,
              accessibilityBounds.height.isFinite,
              accessibilityBounds.width > 0,
              accessibilityBounds.height > 0 else {
            return nil
        }

        let frames = screenFrames.isEmpty ? [CGRect(origin: .zero, size: .zero)] : screenFrames
        for frame in frames {
            let rect = appKitScreenRect(accessibilityBounds: accessibilityBounds, screenFrame: frame)
            if frame.intersects(rect) || frame.contains(CGPoint(x: rect.midX, y: rect.midY)) {
                return rect
            }
        }
        return frames.first.map {
            appKitScreenRect(accessibilityBounds: accessibilityBounds, screenFrame: $0)
        }
    }

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

    static func frame(
        anchorRect: CGRect,
        size: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGRect {
        let clampedWidth = min(max(0, size.width), visibleFrame.width)
        let requestedHeight = min(max(0, size.height), visibleFrame.height)
        let availableBelow = max(0, anchorRect.minY - gap - visibleFrame.minY)
        let availableAbove = max(0, visibleFrame.maxY - anchorRect.maxY - gap)
        let fitsBelow = requestedHeight <= availableBelow
        let fitsAbove = requestedHeight <= availableAbove
        let placeBelow: Bool
        if fitsBelow {
            placeBelow = true
        } else if fitsAbove {
            placeBelow = false
        } else {
            placeBelow = availableBelow >= availableAbove
        }

        let clampedHeight = min(requestedHeight, placeBelow ? availableBelow : availableAbove)
        let clampedSize = CGSize(width: clampedWidth, height: clampedHeight)
        var x = anchorRect.midX - clampedSize.width / 2
        let y = placeBelow
            ? anchorRect.minY - gap - clampedSize.height
            : anchorRect.maxY + gap

        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - clampedSize.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: clampedSize)
    }
}
