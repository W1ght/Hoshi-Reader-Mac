import SwiftUI

enum NativeMacSection: String, CaseIterable, Identifiable {
    case bookshelf
    case dictionary
    #if HOSHI_VIDEO
    case video
    #endif
    case settings

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .bookshelf:
            "Bookshelf"
        case .dictionary:
            "Dictionary"
        #if HOSHI_VIDEO
        case .video:
            "Video"
        #endif
        case .settings:
            "Settings"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .bookshelf:
            "Bookshelf and sync"
        case .dictionary:
            "Dictionary search"
        #if HOSHI_VIDEO
        case .video:
            "Video learning"
        #endif
        case .settings:
            "App settings"
        }
    }

    var systemImage: String {
        switch self {
        case .bookshelf:
            "books.vertical"
        case .dictionary:
            "character.book.closed"
        #if HOSHI_VIDEO
        case .video:
            "play.rectangle"
        #endif
        case .settings:
            "gearshape"
        }
    }
}
