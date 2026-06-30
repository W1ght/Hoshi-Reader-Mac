//
//  PopupModels.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CHoshiDicts
import CoreGraphics
import Foundation

enum PopupViewPlacement {
    case anchored
    case panelSurface
}

struct PopupLayout {
    let selectionRect: CGRect
    let screenSize: CGSize
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let isVertical: Bool
    let isFullWidth: Bool
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    private let popupPadding: CGFloat = 4
    private let screenBorderPadding: CGFloat = 6

    private var spaceLeft: CGFloat {
        selectionRect.minX - popupPadding
    }

    private var spaceRight: CGFloat {
        screenSize.width - selectionRect.maxX - popupPadding
    }

    private var showOnRight: Bool {
        spaceRight >= spaceLeft || spaceRight >= maxWidth
    }

    private var spaceAbove: CGFloat {
        selectionRect.minY - topInset - popupPadding
    }

    private var spaceBelow: CGFloat {
        screenSize.height - bottomInset - selectionRect.maxY - popupPadding
    }

    private var showBelow: Bool {
        spaceBelow >= spaceAbove || spaceBelow >= maxHeight
    }

    var width: CGFloat {
        if isFullWidth {
            return screenSize.width - screenBorderPadding * 2
        }

        if isVertical {
            return min(max(spaceLeft, spaceRight) - screenBorderPadding, maxWidth)
        }

        return min(screenSize.width - screenBorderPadding * 2, maxWidth)
    }

    var height: CGFloat {
        if isVertical || isFullWidth {
            return maxHeight
        }

        let availableHeight = showBelow ? spaceBelow : spaceAbove
        return min(max(0, availableHeight - screenBorderPadding), maxHeight)
    }

    var position: CGPoint {
        var x: CGFloat
        var y: CGFloat

        if isFullWidth {
            x = width / 2 + screenBorderPadding
            y = screenSize.height - height / 2 - screenBorderPadding
        } else {
            if isVertical {
                if showOnRight {
                    x = selectionRect.maxX + popupPadding + (width / 2)
                } else {
                    x = selectionRect.minX - popupPadding - (width / 2)
                }
                x = max(width / 2, min(x, screenSize.width - width / 2))

                y = selectionRect.minY + (height / 2)
                y = max(height / 2 + screenBorderPadding + topInset, min(y, screenSize.height - bottomInset - height / 2 - screenBorderPadding))
            } else {
                x = selectionRect.minX + (width / 2)
                x = max(width / 2 + screenBorderPadding, min(x, screenSize.width - width / 2 - screenBorderPadding))

                if showBelow {
                    y = selectionRect.maxY + popupPadding + (height / 2)
                } else {
                    y = selectionRect.minY - popupPadding - (height / 2)
                }
                y = max(height / 2 + topInset + screenBorderPadding, min(y, screenSize.height - bottomInset - height / 2 - screenBorderPadding))
            }
        }
        return CGPoint(x: x, y: y)
    }
}

struct SelectionData {
    let text: String
    let sentence: String
    let rect: CGRect
    var normalizedOffset: Int?
    var miningContext: MiningContextSelection? = nil

    mutating func applyLookupMatch(_ matchedText: String) -> Int {
        miningContext?.setCurrentTargetUTF16Length(matchedText.utf16.count)
        return matchedText.count
    }
}

struct PopupItem: Identifiable {
    let id: UUID = UUID()
    var showPopup: Bool
    var currentSelection: SelectionData?
    var lookupResults: [LookupResult] = []
    var dictionaryStyles: [String: String] = [:]
    var isVertical: Bool
    var isFullWidth: Bool
    var clearSelection: Bool
    var sasayakiCue: SasayakiMatch? = nil
}
