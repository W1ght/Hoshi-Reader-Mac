import AppKit
import Foundation
import Testing
@testable import AidokuRuntime

@Test func imageRequestsReceiveDefaultUserAgentAndPreserveSourceOverride() throws {
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 2,
        cookies: [],
        userAgent: nil,
        defaultsWriter: { _ in }
    )
    let url = try #require(URL(string: "https://example.invalid/cover.jpg"))
    let descriptor = store.store(.request(.init(method: "GET", url: url)))
    let request = try #require(store.networkRequest(descriptor))
    #expect(request.headers["User-Agent"] == "Niratan AidokuRuntime/1")

    let customDescriptor = store.store(.request(.init(
        method: "GET",
        url: url,
        headers: ["user-agent": "Source UA/7"]
    )))
    let custom = try #require(store.networkRequest(customDescriptor))
    #expect(custom.headers["user-agent"] == "Source UA/7")
    #expect(custom.headers["User-Agent"] == nil)
}

@Test func coverLoaderFallsBackToFreshDetailsAfterInvalidBrowseCover() async throws {
    let initialURL = "https://example.invalid/stale.jpg"
    let refreshedURL = "https://example.invalid/current.jpg"
    let manga = AidokuManga(key: "manga", title: "Manga", coverURL: initialURL)
    let runtime = CoverRuntimeStub(
        refreshed: AidokuManga(key: manga.key, title: manga.title, coverURL: refreshedURL)
    )
    let transport = CoverTransportStub(responses: [
        initialURL: [.init(statusCode: 200, data: Data("<html>missing</html>".utf8), contentType: "text/html")],
        refreshedURL: [.init(statusCode: 200, data: testCoverPNG(), contentType: "image/png")],
    ])
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let loader = AidokuCoverLoader(cacheDirectory: directory, transport: transport)

    let data = try await loader.data(
        sourceID: "en.fixture",
        sourceVersion: 1,
        manga: manga,
        runtime: runtime
    )

    #expect(NSImage(data: data) != nil)
    #expect(await runtime.detailCallCount() == 1)
    #expect(await transport.requestCount(for: initialURL) == 1)
    #expect(await transport.requestCount(for: refreshedURL) == 1)
}

@Test func coverLoaderDoesNotRetrySameBrokenURLFromDetails() async throws {
    let url = "https://example.invalid/soft-404.jpg"
    let manga = AidokuManga(key: "broken", title: "Broken", coverURL: url)
    let runtime = CoverRuntimeStub(refreshed: manga)
    let transport = CoverTransportStub(responses: [
        url: [.init(statusCode: 200, data: Data("not an image".utf8), contentType: "text/html")],
    ])
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let loader = AidokuCoverLoader(cacheDirectory: directory, transport: transport)

    await #expect(throws: (any Error).self) {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            manga: manga,
            runtime: runtime
        )
    }
    #expect(await runtime.detailCallCount() == 1)
    #expect(await transport.requestCount(for: url) == 1)
}

@Test func coverLoaderCoalescesConcurrentRequestsAndReusesDiskCache() async throws {
    let url = "https://example.invalid/shared.png"
    let manga = AidokuManga(key: "shared", title: "Shared", coverURL: url)
    let runtime = CoverRuntimeStub(refreshed: manga)
    let image = testCoverPNG()
    let transport = CoverTransportStub(responses: [
        url: [.init(statusCode: 200, data: image, contentType: "image/png")],
    ])
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let loader = AidokuCoverLoader(cacheDirectory: directory, transport: transport)

    let results = try await withThrowingTaskGroup(of: Data.self) { group in
        for _ in 0..<20 {
            group.addTask {
                try await loader.data(
                    sourceID: "en.fixture",
                    sourceVersion: 3,
                    manga: manga,
                    runtime: runtime
                )
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
    #expect(results.count == 20)
    #expect(await transport.requestCount(for: url) == 1)

    let secondTransport = CoverTransportStub(responses: [:])
    let secondLoader = AidokuCoverLoader(cacheDirectory: directory, transport: secondTransport)
    let cached = try await secondLoader.data(
        sourceID: "en.fixture",
        sourceVersion: 3,
        manga: manga,
        runtime: runtime
    )
    #expect(NSImage(data: cached) != nil)
    #expect(await secondTransport.totalRequestCount() == 0)
}

@Test func coverPermitPoolRemovesCancelledWaitersBeforeServingFreshWork() async throws {
    let pool = AidokuAsyncPermitPool(limit: 1)
    let barrier = CoverPermitBarrier()
    let executions = CoverExecutionRecorder()
    let blocker = Task {
        try await pool.withPermit {
            await barrier.wait()
        }
    }
    #expect(await eventuallyCover { await barrier.isWaiting })

    let cancelled = (0..<32).map { index in
        Task {
            try await pool.withPermit {
                await executions.append(100 + index)
            }
        }
    }
    #expect(await eventuallyCover { await pool.waitingCount == cancelled.count })

    cancelled.forEach { $0.cancel() }
    #expect(await eventuallyCover { await pool.waitingCount == 0 })

    let fresh = Task {
        try await pool.withPermit {
            await executions.append(1)
        }
    }
    #expect(await eventuallyCover { await pool.waitingCount == 1 })
    await barrier.open()

    try await blocker.value
    try await fresh.value
    for task in cancelled {
        do {
            try await task.value
            Issue.record("Cancelled cover waiter unexpectedly ran")
        } catch is CancellationError {
            // Expected: cancelled offscreen work leaves the queue immediately.
        } catch {
            Issue.record("Cancelled cover waiter failed with unexpected error: \(error)")
        }
    }
    #expect(await executions.values == [1])
    #expect(await pool.waitingCount == 0)
}

@Test func invalidatedCoverTaskCannotRemoveItsReplacement() async throws {
    let url = "https://example.invalid/replaced.png"
    let manga = AidokuManga(key: "replacement", title: "Replacement", coverURL: url)
    let runtime = CoverRuntimeStub(refreshed: manga)
    let transport = CoverRaceTransport()
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let loader = AidokuCoverLoader(cacheDirectory: directory, transport: transport)

    let old = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            manga: manga,
            runtime: runtime
        )
    }
    #expect(await eventuallyCover { await transport.startedCount == 1 })

    try await loader.invalidateSource("en.fixture")
    let replacement = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            manga: manga,
            runtime: runtime
        )
    }
    #expect(await eventuallyCover { await transport.startedCount == 2 })

    await transport.resume(index: 0, data: testCoverPNG())
    await #expect(throws: CancellationError.self) { try await old.value }

    let coalesced = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            manga: manga,
            runtime: runtime
        )
    }
    try await Task.sleep(for: .milliseconds(25))
    #expect(await transport.startedCount == 2)

    await transport.resume(index: 1, data: testCoverPNG())
    #expect(NSImage(data: try await replacement.value) != nil)
    #expect(NSImage(data: try await coalesced.value) != nil)
    #expect(await transport.startedCount == 2)
}

@Test func sourceIconLoaderNormalizesRemoteIconsAndReusesDiskCache() async throws {
    let url = try #require(URL(string: "https://example.invalid/icons/en.fixture.png"))
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = SourceIconTransportStub(responses: [
        url.absoluteString: .init(statusCode: 200, data: testCoverPNG()),
    ])
    let loader = AidokuSourceIconLoader(cacheDirectory: directory, transport: transport)
    let data = try await loader.data(
        sourceID: "en.fixture",
        sourceVersion: 4,
        location: .remote(url, insecureTransportApproved: false)
    )

    #expect(NSImage(data: data) != nil)
    #expect(await transport.requestCount == 1)
    #expect(await transport.lastMaximumBytes == 4 * 1_024 * 1_024)
    #expect(await transport.lastInsecureTransportApproved == false)

    let cachedTransport = SourceIconTransportStub(responses: [:])
    let cachedLoader = AidokuSourceIconLoader(cacheDirectory: directory, transport: cachedTransport)
    let cached = try await cachedLoader.data(
        sourceID: "en.fixture",
        sourceVersion: 4,
        location: .remote(url, insecureTransportApproved: false)
    )
    #expect(NSImage(data: cached) != nil)
    #expect(await cachedTransport.requestCount == 0)
}

@Test func sourceIconLoaderReadsOnlyBoundedRegularInstalledIcon() async throws {
    let root = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("en.fixture", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try testCoverPNG().write(to: source.appendingPathComponent("icon.png"), options: .atomic)
    let loader = AidokuSourceIconLoader(cacheDirectory: root.appendingPathComponent("cache"))

    let data = try await loader.data(
        sourceID: "en.fixture",
        sourceVersion: 1,
        location: .installedSource(source)
    )
    #expect(NSImage(data: data) != nil)

    let unsafeSource = root.appendingPathComponent("ja.fixture", isDirectory: true)
    try FileManager.default.createDirectory(at: unsafeSource, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("outside.png")
    try testCoverPNG().write(to: target, options: .atomic)
    try FileManager.default.createSymbolicLink(
        at: unsafeSource.appendingPathComponent("icon.png"),
        withDestinationURL: target
    )
    await #expect(throws: (any Error).self) {
        try await loader.data(
            sourceID: "ja.fixture",
            sourceVersion: 1,
            location: .installedSource(unsafeSource)
        )
    }
}

@Test func sourceIconLoaderRejectsUnapprovedInsecureURLsAndHTML() async throws {
    let insecureURL = try #require(URL(string: "http://example.invalid/icon.png"))
    let htmlURL = try #require(URL(string: "https://example.invalid/icon.png"))
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = SourceIconTransportStub(responses: [
        htmlURL.absoluteString: .init(statusCode: 200, data: Data("<html>blocked</html>".utf8)),
    ])
    let loader = AidokuSourceIconLoader(cacheDirectory: directory, transport: transport)

    await #expect(throws: AidokuRuntimeError.insecureTransportRequiresConfirmation) {
        try await loader.data(
            sourceID: "en.insecure",
            sourceVersion: 1,
            location: .remote(insecureURL, insecureTransportApproved: false)
        )
    }
    #expect(await transport.requestCount == 0)

    await #expect(throws: (any Error).self) {
        try await loader.data(
            sourceID: "en.html",
            sourceVersion: 1,
            location: .remote(htmlURL, insecureTransportApproved: false)
        )
    }
    #expect(await transport.requestCount == 1)
}

@Test func invalidatedSourceIconRequestCannotPopulateReplacementCache() async throws {
    let url = try #require(URL(string: "https://example.invalid/icons/replaced.png"))
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = SourceIconRaceTransport()
    let loader = AidokuSourceIconLoader(cacheDirectory: directory, transport: transport)

    let old = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            location: .remote(url, insecureTransportApproved: false)
        )
    }
    #expect(await eventuallyCover { await transport.startedCount == 1 })
    try await loader.invalidateSource("en.fixture")
    await transport.resume(index: 0, data: testCoverPNG())
    await #expect(throws: CancellationError.self) { try await old.value }

    let replacement = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            location: .remote(url, insecureTransportApproved: false)
        )
    }
    #expect(await eventuallyCover { await transport.startedCount == 2 })
    await transport.resume(index: 1, data: testCoverPNG())
    #expect(NSImage(data: try await replacement.value) != nil)
}

@Test func sourceIconLoaderCoalescesConcurrentRequestsWithoutCouplingCancellation() async throws {
    let url = try #require(URL(string: "https://example.invalid/icons/shared.png"))
    let directory = temporaryCoverDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = SourceIconRaceTransport()
    let loader = AidokuSourceIconLoader(cacheDirectory: directory, transport: transport)

    let cancelled = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            location: .remote(url, insecureTransportApproved: false)
        )
    }
    let survivor = Task {
        try await loader.data(
            sourceID: "en.fixture",
            sourceVersion: 1,
            location: .remote(url, insecureTransportApproved: false)
        )
    }
    #expect(await eventuallyCover { await transport.startedCount == 1 })

    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await transport.startedCount == 1)

    await transport.resume(index: 0, data: testCoverPNG())
    #expect(NSImage(data: try await survivor.value) != nil)
    #expect(await transport.startedCount == 1)
}

private actor CoverRuntimeStub: AidokuCoverRuntime {
    private let refreshed: AidokuManga
    private var details = 0

    init(refreshed: AidokuManga) { self.refreshed = refreshed }

    func mangaDetails(_ manga: AidokuManga, chapters: Bool) async throws -> AidokuManga {
        details += 1
        return refreshed
    }

    func imageRequest(url value: String, context: [String: String]) async throws -> AidokuImageRequest {
        guard let url = URL(string: value) else { throw AidokuRuntimeError.unsupportedURL }
        return AidokuImageRequest(url: url, headers: ["User-Agent": "Fixture/1"])
    }

    func detailCallCount() -> Int { details }
}

private actor SourceIconTransportStub: AidokuSourceIconTransport {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
    }

    private var responses: [String: Response]
    private(set) var requestCount = 0
    private(set) var lastMaximumBytes: Int?
    private(set) var lastInsecureTransportApproved: Bool?

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        lastMaximumBytes = maximumBytes
        lastInsecureTransportApproved = insecureTransportApproved
        let key = request.url?.absoluteString ?? ""
        guard let response = responses[key],
              response.data.count <= maximumBytes,
              let url = request.url,
              let http = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/png"]
              ) else {
            throw URLError(.resourceUnavailable)
        }
        return (response.data, http)
    }
}

private actor SourceIconRaceTransport: AidokuSourceIconTransport {
    private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), any Error>] = [:]
    private(set) var startedCount = 0

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        insecureTransportApproved: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let index = startedCount
        startedCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func resume(index: Int, data: Data) {
        guard let continuation = continuations.removeValue(forKey: index),
              let url = URL(string: "https://example.invalid/icons/replaced.png"),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/png"]
              ) else { return }
        continuation.resume(returning: (data, response))
    }
}

private actor CoverTransportStub: AidokuImageTransport {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
        let contentType: String
    }

    private var responses: [String: [Response]]
    private var counts: [String: Int] = [:]

    init(responses: [String: [Response]]) { self.responses = responses }

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        usesSystemProxy: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let key = request.url?.absoluteString ?? ""
        counts[key, default: 0] += 1
        guard var queued = responses[key], !queued.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        let response = queued.removeFirst()
        responses[key] = queued
        guard response.data.count <= maximumBytes,
              let url = request.url,
              let http = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": response.contentType]
              ) else { throw AidokuRuntimeError.responseTooLarge }
        return (response.data, http)
    }

    func requestCount(for url: String) -> Int { counts[url, default: 0] }
    func totalRequestCount() -> Int { counts.values.reduce(0, +) }
}

private actor CoverRaceTransport: AidokuImageTransport {
    private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), any Error>] = [:]
    private(set) var startedCount = 0

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        usesSystemProxy: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let index = startedCount
        startedCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func resume(index: Int, data: Data) {
        guard let continuation = continuations.removeValue(forKey: index),
              let url = URL(string: "https://example.invalid/replaced.png"),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/png"]
              ) else { return }
        continuation.resume(returning: (data, response))
    }
}

private actor CoverPermitBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CoverExecutionRecorder {
    private(set) var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}

private func eventuallyCover(
    attempts: Int = 1_000,
    _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await predicate()
}

private func temporaryCoverDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Niratan-Cover-Tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func testCoverPNG() -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 4,
        pixelsHigh: 4,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 16,
        bitsPerPixel: 32
    )!
    let color = NSColor(deviceRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
    representation.setColor(color, atX: 0, y: 0)
    representation.setColor(color, atX: 1, y: 0)
    representation.setColor(color, atX: 0, y: 1)
    representation.setColor(color, atX: 1, y: 1)
    return representation.representation(using: .png, properties: [:])!
}
