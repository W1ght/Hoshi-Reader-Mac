//
//  BookshelfDropSupport.swift
//  Niratan
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
    private let accepts: ([URL]) -> Bool
    private let onDrop: ([URL]) -> Bool
    private let content: Content

    init(
        accepts: @escaping ([URL]) -> Bool = {
            $0.contains { $0.pathExtension.lowercased() == "epub" }
        },
        onDrop: @escaping ([URL]) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.accepts = accepts
        self.onDrop = onDrop
        self.content = content()
    }

    func makeNSView(context: Context) -> BookshelfFileDropHostingView {
        BookshelfFileDropHostingView(
            rootView: AnyView(content),
            accepts: accepts,
            onDrop: onDrop
        )
    }

    func updateNSView(_ nsView: BookshelfFileDropHostingView, context: Context) {
        nsView.rootView = AnyView(content)
        nsView.accepts = accepts
        nsView.onDrop = onDrop
    }
}

final class BookshelfFileDropHostingView: NSHostingView<AnyView> {
    var accepts: ([URL]) -> Bool
    var onDrop: ([URL]) -> Bool

    init(
        rootView: AnyView,
        accepts: @escaping ([URL]) -> Bool,
        onDrop: @escaping ([URL]) -> Bool
    ) {
        self.accepts = accepts
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
        accepts(BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard)) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard)) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop(BookshelfFileDropDecoder.fileURLs(from: sender.draggingPasteboard))
    }
}
