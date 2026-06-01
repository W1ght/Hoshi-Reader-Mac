//
//  WebViewPreloader.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebKit

final class WebViewPreloader {
    static let shared = WebViewPreloader()

    private var dummy: WKWebView?

    func warmup() {
        DispatchQueue.main.async {
            self.dummy = WKWebView(frame: .zero)
            self.dummy?.loadHTMLString("", baseURL: nil)
        }
    }

    func close() {
        guard dummy != nil else {
            return
        }
        DispatchQueue.main.async {
            self.dummy = nil
        }
    }
}
