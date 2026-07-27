import Foundation
import Observation

enum MangaWindowContent {
    case local(MangaLibraryItem, MangaLibrarySource)
    case remote(MangaReadingSession, any MangaPageContentProvider)
    case remoteRequest(MangaRemoteReadingRequest)
}

struct MangaWindowOpenRequest: Identifiable {
    let id: UUID
    let title: String
    let content: MangaWindowContent

    init(
        id: UUID = UUID(),
        item: MangaLibraryItem,
        source: MangaLibrarySource
    ) {
        self.id = id
        title = item.displayTitle
        content = .local(item, source)
    }

    init(
        id: UUID = UUID(),
        session: MangaReadingSession,
        pageProvider: any MangaPageContentProvider
    ) {
        self.id = id
        title = session.title
        content = .remote(session, pageProvider)
    }

    init(
        id: UUID = UUID(),
        request: MangaRemoteReadingRequest
    ) {
        self.id = id
        title = request.title
        content = .remoteRequest(request)
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
        let isSameLocalRequest: Bool
        if let currentRequest,
           case .local(let currentItem, let currentSource) =
               currentRequest.content {
            isSameLocalRequest = currentItem == item && currentSource == source
        } else {
            isSameLocalRequest = false
        }
        if !isWindowPresented || !isSameLocalRequest {
            sessionID = UUID()
        }
        let request = MangaWindowOpenRequest(item: item, source: source)
        currentRequest = request
        return request
    }

    @discardableResult
    func requestOpen(
        session: MangaReadingSession,
        pageProvider: any MangaPageContentProvider
    ) -> MangaWindowOpenRequest {
        sessionID = UUID()
        let request = MangaWindowOpenRequest(
            session: session,
            pageProvider: pageProvider
        )
        currentRequest = request
        return request
    }

    @discardableResult
    func requestOpen(
        request remoteRequest: MangaRemoteReadingRequest
    ) -> MangaWindowOpenRequest {
        sessionID = UUID()
        let request = MangaWindowOpenRequest(request: remoteRequest)
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
