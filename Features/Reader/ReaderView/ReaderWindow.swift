//
//  ReaderWindow.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

private struct DismissReaderKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct OpenReaderTabKey: EnvironmentKey {
    static let defaultValue: ((Int) -> Void)? = nil
}

extension EnvironmentValues {
    var dismissReader: (() -> Void)? {
        get { self[DismissReaderKey.self] }
        set { self[DismissReaderKey.self] = newValue }
    }

    var openReaderTab: ((Int) -> Void)? {
        get { self[OpenReaderTabKey.self] }
        set { self[OpenReaderTabKey.self] = newValue }
    }
}
