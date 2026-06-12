//
//  WebViewBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum NavigationDirection {
    case forward
    case backward
}

struct HighlightData {
    let id: UUID
    let start: Int
    let offset: Int
    let text: String
}

enum WebViewCommand {
    case loadChapter(url: URL, progress: Double, fragment: String?, sasayakiCues: String? = nil, highlights: String? = nil)
    case restoreProgress(Double)
    case jumpToFragment(String)
    case clearSelection
    case navigate(NavigationDirection)
    case stepContinuous(NavigationDirection)
    case updateTextColor(String?)
    case updateSasayakiColors(textHex: String, backgroundHex: String)
    case applySasayakiCues(String, completion: (() -> Void)? = nil)
    case highlightSasayakiCue(id: String, reveal: Bool)
    case clearSasayakiCue
    case removeHighlight(String)
    case applyRegressionHighlight(String)
}

@Observable
@MainActor
class WebViewBridge {
    private(set) var chapterURL: URL?
    private(set) var progress: Double = 0
    private(set) var sasayakiCues: String?
    private(set) var highlights: String?
    var pendingCommands: [WebViewCommand] = []

    func send(_ command: WebViewCommand) {
        pendingCommands.append(command)
    }

    func updateState(url: URL, progress: Double, sasayakiCues: String? = nil, highlights: String? = nil) {
        self.chapterURL = url
        self.progress = progress
        self.sasayakiCues = sasayakiCues
        self.highlights = highlights
    }

    func updateProgress(_ progress: Double) {
        self.progress = progress
    }

    func updateHighlights(_ highlights: String?) {
        self.highlights = highlights
    }
}
