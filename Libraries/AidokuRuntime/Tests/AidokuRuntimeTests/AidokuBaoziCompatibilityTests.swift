import AppKit
import Foundation
import SwiftSoup
import Testing
@testable import AidokuRuntime

@Test func optionalDownloadedBaoziSourceOpensRepresentativeChapter() async throws {
    guard let packagePath = ProcessInfo.processInfo.environment[
        "AIDOKU_LIVE_BAOZI_PACKAGE"
    ] else { return }

    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Niratan-Baozi-Live-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    let installed = try await AidokuPackageInstaller(
        rootDirectory: temporary
    ).install(
        archiveURL: URL(fileURLWithPath: packagePath),
        expectedSourceID: "zh.baozimanhua"
    )
    let runtime = try AidokuSourceRuntime(configuration: .init(
        sourceDirectory: installed.directory
    ))
    let browse = try await runtime.search(query: nil, page: 1)
    let manga = try #require(browse.entries.first(where: {
        $0.key == "wuliandianfeng-pikapi"
    }))

    let clock = ContinuousClock()
    let detailStart = clock.now
    let details = try await runtime.mangaDetails(manga, chapters: true)
    let detailDuration = detailStart.duration(to: clock.now)
    FileHandle.standardError.write(Data(
        "BAOZI-LIVE details=\(detailDuration) chapters=\(details.chapters?.count ?? 0)\n".utf8
    ))
    let chapter = try #require(details.chapters?.first(where: { !$0.locked }))

    let legacyURL = try #require(URL(string:
        "https://appcn.baozimh.com/baozimhapp/comic/chapter/\(details.key)/0_\(chapter.key).html"
    ))
    let hostStore = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: nil,
        defaultsWriter: { _ in }
    )
    let requestID = hostStore.store(.request(.init(
        method: "GET",
        url: legacyURL,
        headers: [
            "Origin": "https://www.baozimh.com",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://appcn.baozimh.com",
        ]
    )))
    #expect(hostStore.sendRequest(requestID) == 0)
    let networkResponse = hostStore.withItem(requestID) { item in
        if case .request(let request) = item { return request.response }
        return nil
    } ?? nil
    let chapterResponse = try #require(networkResponse)
    let html = try #require(String(data: chapterResponse.data, encoding: .utf8))
    let document = try SwiftSoup.parse(html, chapterResponse.url.absoluteString)
    #expect(try AidokuHTMLSelectorResolver.elements(
        in: document,
        query: "img.comic-contain__item"
    ).count > 0, Comment(
        rawValue: "final URL \(chapterResponse.url.absoluteString), bytes \(chapterResponse.data.count)"
    ))

    let pages = try await runtime.pages(manga: details, chapter: chapter)

    #expect(detailDuration < AidokuLimits.metadataTimeout)
    #expect((details.chapters?.count ?? 0) > 3_000)
    #expect(!pages.isEmpty)

    let firstPage = try #require(pages.first)
    guard case .url(let value, let context) = firstPage.content else {
        Issue.record("Expected Baozi to return URL image pages")
        return
    }
    let imageRequest = try await runtime.imageRequest(url: value, context: context)
    var request = URLRequest(url: imageRequest.url)
    imageRequest.headers.forEach {
        request.setValue($0.value, forHTTPHeaderField: $0.key)
    }
    let (data, response) = try await AidokuHTTPClient.data(
        for: request,
        maximumBytes: AidokuLimits.maximumImageBytes
    )
    #expect((200..<300).contains(response.statusCode))
    #expect(NSImage(data: data) != nil)
}
