import Foundation
import Testing
@testable import AidokuRuntime

private final class AidokuNetworkFixture: @unchecked Sendable {
    struct Plan: Sendable {
        let delay: Duration
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(
            delay: Duration = .zero,
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "application/json"],
            body: Data = Data("{}".utf8)
        ) {
            self.delay = delay
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    private let lock = NSLock()
    private let plans: [String: Plan]
    private var capturedRequests: [URLRequest] = []
    private var requestStartDates: [Date] = []
    private var activeRequests = 0
    private var maximumActiveRequests = 0

    init(plans: [String: Plan]) {
        self.plans = plans
    }

    func handle(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let plan = lock.withLock { () -> Plan in
            capturedRequests.append(request)
            requestStartDates.append(Date())
            activeRequests += 1
            maximumActiveRequests = max(maximumActiveRequests, activeRequests)
            return plans[request.url?.path ?? ""] ?? Plan()
        }
        defer { lock.withLock { activeRequests -= 1 } }
        if plan.delay > .zero {
            try await Task.sleep(for: plan.delay)
        }
        guard let requestURL = request.url,
              let response = HTTPURLResponse(
            url: requestURL,
            statusCode: plan.statusCode,
            httpVersion: "HTTP/2",
            headerFields: plan.headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (plan.body, response)
    }

    var requests: [URLRequest] { lock.withLock { capturedRequests } }
    var startDates: [Date] { lock.withLock { requestStartDates } }
    var maximumActive: Int { lock.withLock { maximumActiveRequests } }
}

private final class AidokuLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ message: String) {
        lock.withLock { storage.append(message) }
    }

    var messages: [String] { lock.withLock { storage } }
}

private final class AidokuSendAllCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int32]?

    func set(_ values: [Int32]) {
        lock.withLock { storage = values }
    }

    var values: [Int32]? { lock.withLock { storage } }
}

private func responseData(_ descriptor: Int32, in store: AidokuHostStore) -> Data? {
    store.withItem(descriptor) { item in
        guard case .request(let request) = item else { return nil }
        return request.response?.data
    } ?? nil
}

private func header(_ name: String, in headers: [String: String]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}

private func fixtureURL(_ value: String) -> URL {
    // Test constants are controlled here rather than decoded from source data.
    URL(string: value)!
}

@Test func runnerHostHeadersMergeIsolatedCookiesAndPreserveSourceUserAgent() async throws {
    let fixture = AidokuNetworkFixture(plans: [
        "/first": .init(headers: [
            "Content-Type": "application/json; charset=utf-8",
            "Set-Cookie": "session=next; Path=/; Secure; HttpOnly, preference=dark; Path=/; Secure",
        ]),
    ])
    let logs = AidokuLogCapture()
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 2,
        cookies: [
            AidokuStoredCookie(
                name: "host",
                value: "one",
                domain: "example.com",
                secure: true
            ),
            AidokuStoredCookie(
                name: "domain",
                value: "shared",
                domain: ".example.com",
                secure: true
            ),
        ],
        userAgent: "WK-UA/1",
        sourceID: "multi.fixture",
        networkHandler: { try await fixture.handle($0) },
        logHandler: { logs.append($0) },
        defaultsWriter: { _ in }
    )
    let firstURL = fixtureURL("https://example.com/first?token=query-secret")
    let descriptor = store.store(.request(.init(
        method: "POST",
        url: firstURL,
        headers: [
            "cookie": "source=two",
            "user-agent": "Source-UA/7",
            "Authorization": "Bearer header-secret",
        ],
        body: Data("body-secret".utf8)
    )))

    let imageRequest = try #require(store.networkRequest(descriptor))
    let mergedCookie = try #require(header("Cookie", in: imageRequest.headers))
    #expect(mergedCookie.contains("host=one"))
    #expect(mergedCookie.contains("domain=shared"))
    #expect(mergedCookie.hasSuffix("; source=two"))
    #expect(header("User-Agent", in: imageRequest.headers) == "Source-UA/7")

    let rootRequest = store.modifiedImageRequest(AidokuImageRequest(
        url: fixtureURL("https://example.com")
    ))
    let rootCookie = try #require(header("Cookie", in: rootRequest.headers))
    #expect(rootCookie.contains("host=one"))
    #expect(rootCookie.contains("domain=shared"))

    let urlRequest = try #require(store.urlRequest(descriptor))
    #expect(urlRequest.value(forHTTPHeaderField: "Cookie") == mergedCookie)
    #expect(urlRequest.value(forHTTPHeaderField: "User-Agent") == "Source-UA/7")

    #expect(store.sendRequest(descriptor) == 0)
    let sent = try #require(fixture.requests.first)
    #expect(sent.value(forHTTPHeaderField: "Cookie") == mergedCookie)
    #expect(sent.value(forHTTPHeaderField: "User-Agent") == "Source-UA/7")

    let next = store.modifiedImageRequest(AidokuImageRequest(
        url: fixtureURL("https://example.com/next")
    ))
    let nextCookie = try #require(header("Cookie", in: next.headers))
    #expect(nextCookie.contains("host=one"))
    #expect(nextCookie.contains("session=next"))
    #expect(nextCookie.contains("preference=dark"))
    #expect(header("User-Agent", in: next.headers) == "WK-UA/1")

    let subdomain = store.modifiedImageRequest(AidokuImageRequest(
        url: fixtureURL("https://cdn.example.com/next")
    ))
    let subdomainCookie = try #require(header("Cookie", in: subdomain.headers))
    #expect(subdomainCookie.contains("domain=shared"))
    #expect(!subdomainCookie.contains("host=one"))
    #expect(!subdomainCookie.contains("session=next"))
    #expect(!subdomainCookie.contains("preference=dark"))

    let separateStore = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: "Other-UA/1",
        sourceID: "multi.other",
        defaultsWriter: { _ in }
    )
    let isolated = separateStore.modifiedImageRequest(AidokuImageRequest(
        url: fixtureURL("https://example.com/next")
    ))
    #expect(header("Cookie", in: isolated.headers) == nil)
    #expect(header("User-Agent", in: isolated.headers) == "Other-UA/1")

    store.logSourceMessage("plain source diagnostic")
    let networkLog = try #require(logs.messages.first { $0.contains("network operation=") })
    #expect(networkLog.contains("[Aidoku][multi.fixture]"))
    #expect(networkLog.contains("operation=send method=POST host=example.com status=200"))
    #expect(networkLog.contains("content_type=application/json"))
    for secret in ["query-secret", "header-secret", "body-secret", "source=two", "session=next"] {
        #expect(!networkLog.contains(secret))
    }
    #expect(logs.messages.contains("[Aidoku][multi.fixture] plain source diagnostic"))
}

@Test func runnerSendAllCompletesConcurrentlyAndKeepsDescriptorOrder() throws {
    let fixture = AidokuNetworkFixture(plans: [
        "/slow": .init(delay: .milliseconds(180), body: Data("slow".utf8)),
        "/fast": .init(delay: .milliseconds(20), body: Data("fast".utf8)),
    ])
    let logs = AidokuLogCapture()
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 2,
        usesGlobalNetworkLimit: false,
        cookies: [],
        userAgent: nil,
        sourceID: "multi.parallel",
        networkHandler: { try await fixture.handle($0) },
        logHandler: { logs.append($0) },
        defaultsWriter: { _ in }
    )
    let slow = store.store(.request(.init(
        method: "GET",
        url: fixtureURL("https://example.com/slow")
    )))
    let fast = (0..<40).map { _ in
        store.store(.request(.init(
            method: "GET",
            url: fixtureURL("https://example.com/fast")
        )))
    }
    let missingURL = store.store(.request(.init(method: "GET")))
    let descriptors = [slow, 999_999, missingURL] + fast

    let result = AidokuSendAllCapture()
    let completion = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        result.set(store.sendRequests(descriptors))
        completion.signal()
    }
    let completed = completion.wait(timeout: .now() + 3)
    #expect(completed == .success)
    guard completed == .success else {
        store.cancel()
        return
    }
    let values = try #require(result.values)
    let lastFast = try #require(fast.last)

    #expect(values == [0, -1, -9] + Array(repeating: 0, count: fast.count))
    #expect(responseData(slow, in: store) == Data("slow".utf8))
    #expect(responseData(lastFast, in: store) == Data("fast".utf8))
    #expect(fixture.maximumActive == 2)
    #expect(logs.messages.filter { $0.contains("operation=send_all") }.count == 41)
}

@Test func runnerRateLimitIsSharedAndCancellationStopsWaiting() async throws {
    let fixture = AidokuNetworkFixture(plans: ["/rate": .init()])
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 2,
        usesGlobalNetworkLimit: false,
        cookies: [],
        userAgent: nil,
        sourceID: "multi.rate",
        networkHandler: { try await fixture.handle($0) },
        logHandler: { _ in },
        defaultsWriter: { _ in }
    )
    store.setRateLimit(permits: 1, period: 1, unit: 0)
    let descriptors = (0..<2).map { _ in
        store.store(.request(.init(
            method: "GET",
            url: fixtureURL("https://example.com/rate")
        )))
    }

    #expect(store.sendRequests(descriptors) == [0, 0])
    let starts = fixture.startDates.sorted()
    #expect(starts.count == 2)
    #expect(starts[1].timeIntervalSince(starts[0]) >= 0.8)

    let cancellationFixture = AidokuNetworkFixture(plans: ["/rate": .init()])
    let cancellationStore = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        usesGlobalNetworkLimit: false,
        cookies: [],
        userAgent: nil,
        sourceID: "multi.cancel",
        networkHandler: { try await cancellationFixture.handle($0) },
        logHandler: { _ in },
        defaultsWriter: { _ in }
    )
    cancellationStore.setRateLimit(permits: 1, period: 60, unit: 0)
    let first = cancellationStore.store(.request(.init(
        method: "GET",
        url: fixtureURL("https://example.com/rate")
    )))
    let waiting = cancellationStore.store(.request(.init(
        method: "GET",
        url: fixtureURL("https://example.com/rate")
    )))
    #expect(cancellationStore.sendRequest(first) == 0)
    let startedAt = ContinuousClock.now
    let task = Task.detached { cancellationStore.sendRequest(waiting) }
    try await Task.sleep(for: .milliseconds(100))
    cancellationStore.cancel()
    #expect(await task.value == -10)
    #expect(startedAt.duration(to: .now) < .seconds(1))
    #expect(cancellationFixture.requests.count == 1)
}
