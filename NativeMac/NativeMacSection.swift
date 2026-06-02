import SwiftUI

enum NativeMacSection: String, CaseIterable, Identifiable {
    case bookshelf
    case dictionary
    case reader
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .bookshelf:
            "书架"
        case .dictionary:
            "词典"
        case .reader:
            "阅读器"
        case .settings:
            "设置"
        }
    }

    var detail: String {
        switch self {
        case .bookshelf:
            "Library and book sync"
        case .dictionary:
            "Search and popup renderer"
        case .reader:
            "Deferred high-risk surface"
        case .settings:
            "Native settings shell"
        }
    }

    var systemImage: String {
        switch self {
        case .bookshelf:
            "books.vertical"
        case .dictionary:
            "character.book.closed"
        case .reader:
            "book.pages"
        case .settings:
            "gearshape"
        }
    }
}
