import Foundation
import Observation

struct ReaderWindowOpenRequest: Identifiable, Equatable {
    let id: UUID
    let book: BookMetadata

    init(id: UUID = UUID(), book: BookMetadata) {
        self.id = id
        self.book = book
    }
}

@Observable
@MainActor
final class ReaderWindowCoordinator {
    static let windowID = "reader"

    private(set) var pendingRequest: ReaderWindowOpenRequest?
    private(set) var currentRequest: ReaderWindowOpenRequest?
    private(set) var sessionID = UUID()
    private(set) var isWindowPresented = false

    var currentBook: BookMetadata? {
        currentRequest?.book
    }

    @discardableResult
    func requestOpen(_ book: BookMetadata) -> ReaderWindowOpenRequest {
        if !isWindowPresented || currentBook != book {
            sessionID = UUID()
        }
        let request = ReaderWindowOpenRequest(book: book)
        pendingRequest = request
        currentRequest = request
        return request
    }

    func consume(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
    }

    func windowDidAppear() {
        isWindowPresented = true
    }

    func windowDidDisappear() {
        isWindowPresented = false
        pendingRequest = nil
        currentRequest = nil
    }
}

extension Notification.Name {
    static let readerWindowWillClose = Notification.Name("ReaderWindowWillClose")
    static let readerWindowProgressDidChange = Notification.Name("ReaderWindowProgressDidChange")
}
