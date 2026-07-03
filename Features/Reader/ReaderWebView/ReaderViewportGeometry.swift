//
//  ReaderViewportGeometry.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreGraphics

enum ReaderViewportGeometry {
    static func selectionRect(
        fromViewportRect rect: CGRect,
        adjustedContentInset: CGPoint = .zero,
        scrollBoundsOrigin: CGPoint = .zero,
        subtractVerticalScrollOffset: Bool = true
    ) -> CGRect {
        CGRect(
            x: rect.origin.x + adjustedContentInset.x,
            y: rect.origin.y + adjustedContentInset.y - (subtractVerticalScrollOffset ? scrollBoundsOrigin.y : 0),
            width: rect.width,
            height: rect.height
        )
    }
}
