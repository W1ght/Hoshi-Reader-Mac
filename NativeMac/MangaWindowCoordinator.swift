import Foundation
import Observation

struct MangaWindowOpenRequest: Identifiable, Equatable {
    let id: UUID
    let item: MangaLibraryItem
    let source: MangaLibrarySource

    init(
        id: UUID = UUID(),
        item: MangaLibraryItem,
        source: MangaLibrarySource
    ) {
        self.id = id
        self.item = item
        self.source = source
    }
}

@Observable
@MainActor
final class MangaWindowCoordinator {
    static let windowID = "manga-reader"

    private(set) var currentRequest: MangaWindowOpenRequest?
    private(set) var sessionID = UUID()
    private(set) var isWindowPresented = false

    @discardableResult
    func requestOpen(
        item: MangaLibraryItem,
        source: MangaLibrarySource
    ) -> MangaWindowOpenRequest {
        if !isWindowPresented
            || currentRequest?.item != item
            || currentRequest?.source != source {
            sessionID = UUID()
        }
        let request = MangaWindowOpenRequest(item: item, source: source)
        currentRequest = request
        return request
    }

    func windowDidAppear() {
        isWindowPresented = true
    }

    func windowDidDisappear() {
        isWindowPresented = false
        currentRequest = nil
    }
}
