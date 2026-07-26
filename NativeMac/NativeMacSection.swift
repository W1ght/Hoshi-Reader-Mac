import SwiftUI

enum NativeMacSection: String, CaseIterable, Identifiable {
    case bookshelf
    case manga
    case dictionary
    case video
    case settings

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .bookshelf:
            "Bookshelf"
        case .manga:
            "Manga"
        case .dictionary:
            "Dictionary"
        case .video:
            "Video"
        case .settings:
            "Settings"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .bookshelf:
            "Bookshelf and sync"
        case .manga:
            "Local manga library"
        case .dictionary:
            "Dictionary search"
        case .video:
            "Video learning"
        case .settings:
            "App settings"
        }
    }

    var systemImage: String {
        switch self {
        case .bookshelf:
            "books.vertical"
        case .manga:
            "book.pages"
        case .dictionary:
            "character.book.closed"
        case .video:
            "play.rectangle"
        case .settings:
            "gearshape"
        }
    }
}
