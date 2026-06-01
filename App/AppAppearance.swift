//
//  AppAppearance.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

enum AppAppearance {
    static func configure() {
        configureSegmentedControl()
    }

    private static func configureSegmentedControl() {
        let segmentedControl = UISegmentedControl.appearance()
        segmentedControl.apportionsSegmentWidthsByContent = true
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .medium
            )
        ]
        segmentedControl.setTitleTextAttributes(titleAttributes, for: .normal)
        segmentedControl.setTitleTextAttributes(titleAttributes, for: .selected)
    }
}
