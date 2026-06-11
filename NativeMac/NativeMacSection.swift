import SwiftUI

enum NativeMacSection: String, CaseIterable, Identifiable {
    case bookshelf
    case dictionary
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
        case .settings:
            "gearshape"
        }
    }
}
