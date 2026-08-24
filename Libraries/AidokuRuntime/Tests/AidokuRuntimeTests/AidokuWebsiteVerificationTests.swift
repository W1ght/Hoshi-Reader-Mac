import Foundation
import Testing
@testable import AidokuRuntime

private func cloudflareResponse(
    statusCode: Int,
    server: String?
) throws -> HTTPURLResponse {
    let url = try #require(URL(string: "https://example.com/api/titles"))
    return try #require(HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/2",
        headerFields: server.map { ["Server": $0] }
    ))
}

@Test func cloudflareDetectorMatchesOnlyOfficialChallengeConditions() throws {
    let challengeText = Data("<html><div id='challenge-error-text'>blocked</div></html>".utf8)
    let challengeTitle = Data("<html><h1 id='challenge-error-title'>blocked</h1></html>".utf8)

    #expect(AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 403, server: "cloudflare"),
        data: challengeText
    ))
    #expect(AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 503, server: "cloudflare-nginx"),
        data: challengeTitle
    ))
    #expect(!AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 200, server: "cloudflare"),
        data: challengeText
    ))
    #expect(!AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 403, server: "nginx"),
        data: challengeText
    ))
    #expect(!AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 403, server: "cloudflare"),
        data: Data("<html><title>Just a moment...</title></html>".utf8)
    ))
    #expect(!AidokuCloudflareChallengeDetector.shouldHandle(
        response: try cloudflareResponse(statusCode: 403, server: "cloudflare"),
        data: Data(repeating: 0, count: AidokuLimits.maximumJSONBytes + 1)
    ))
}

@Test func cloudflareRequestContextPropagatesThroughHostStore() throws {
    let request = AidokuWebsiteVerificationRequest(
        url: try #require(URL(string: "https://example.com/api/titles?page=1")),
        method: "POST",
        headers: ["User-Agent": "Bound-UA", "X-Request": "fixture"],
        body: Data("payload".utf8),
        userAgent: "Bound-UA"
    )
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: request.userAgent,
        defaultsWriter: { _ in }
    )
    store.recordWebsiteVerificationIfNeeded(
        response: try cloudflareResponse(statusCode: 403, server: "cloudflare"),
        data: Data("<main id='challenge-error-text'></main>".utf8),
        request: request
    )

    #expect(store.takeWebsiteVerificationRequest() == request)
    #expect(store.takeWebsiteVerificationRequest() == nil)
}
