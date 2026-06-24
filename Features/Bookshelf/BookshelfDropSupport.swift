//
//  BookshelfDropSupport.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit
import SwiftUI

enum BookshelfFileDropDecoder {
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.pasteboardItems?.compactMap { item in
            guard let data = item.data(forType: .fileURL) else { return nil }
            return URL(dataRepresentation: data, relativeTo: nil)
        } ?? []
    }
}

struct BookshelfFileDropTarget<Content: View>: NSViewRepresentable {
    private let onDrop: ([URL]) -> Bool
    private let content: Content

    init(
        onDrop: @escaping ([URL]) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.onDrop = onDrop
        self.content = content()
    }

    func makeNSView(context: Context) -> BookshelfFileDropHostingView {
        BookshelfFileDropHostingView(
            rootView: AnyView(content),
            onDrop: onDrop
        )
    }

    func updateNSView(_ nsView: BookshelfFileDropHostingView, context: Context) {
        nsView.rootView = AnyView(content)
        nsView.onDrop = onDrop
    }
}

final class BookshelfFileDropHostingView: NSHostingView<AnyView> {
    var onDrop: ([URL]) -> Bool

    init(rootView: AnyView, onDrop: @escaping ([URL]) -> Bool) {
        self.onDrop = onDrop
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard).contains { $0.pathExtension.lowercased() == "epub" } ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard).contains { $0.pathExtension.lowercased() == "epub" } ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop(BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard))
    }
}
