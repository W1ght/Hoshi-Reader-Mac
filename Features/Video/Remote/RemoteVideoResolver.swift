#if HOSHI_VIDEO
import Foundation
#if canImport(YouTubeKit)
@preconcurrency import YouTubeKit
#endif

nonisolated enum RemoteVideoResolverError: LocalizedError, Equatable, Sendable {
    case unsupportedURL
    case resolutionFailed
    case invalidResponse
    case noPlayableStream
    case contentUnavailable
    case signInRequired
    case regionRestricted
    case cancelled
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            String(localized: "This link is not supported.")
        case .resolutionFailed:
            String(localized: "Unable to resolve this YouTube video. Try again.")
        case .invalidResponse:
            String(localized: "YouTube returned an invalid response.")
        case .noPlayableStream:
            String(localized: "Unable to find a playable YouTube video stream.")
        case .contentUnavailable:
            String(localized: "This video is unavailable or private.")
        case .signInRequired:
            String(localized: "This video requires sign-in or age verification.")
        case .regionRestricted:
            String(localized: "This video is not available in your region.")
        case .cancelled:
            String(localized: "YouTube video loading was cancelled.")
        case .timedOut:
            String(localized: "YouTube video loading timed out.")
        }
    }
}

protocol RemoteVideoResolving: Sendable {
    var provider: RemoteVideoProvider { get }

    func canResolve(url: URL) -> Bool

    func resolve(
        url: URL,
        preferredSubtitleLanguages: [String]
    ) async throws -> ResolvedRemoteVideoSource
}

struct RemoteVideoResolverRegistry: Sendable {
    let resolvers: [any RemoteVideoResolving]
    private let cache: RemoteVideoResolutionCache

    init(
        resolvers: [any RemoteVideoResolving],
        cache: RemoteVideoResolutionCache = .shared
    ) {
        self.resolvers = resolvers
        self.cache = cache
    }

    init(cache: RemoteVideoResolutionCache = .shared) {
#if canImport(YouTubeKit)
        self.init(
            resolvers: [YouTubeKitRemoteVideoResolver()],
            cache: cache
        )
#else
        self.init(resolvers: [], cache: cache)
#endif
    }

    func resolver(for url: URL) -> (any RemoteVideoResolving)? {
        resolvers.first { $0.canResolve(url: url) }
    }

    func resolve(
        url: URL,
        preferredSubtitleLanguages: [String] = [],
        forceRefresh: Bool = false
    ) async throws -> ResolvedRemoteVideoSource {
        let urlCacheKey = "url:\(url.absoluteString)"
        if !forceRefresh, let cached = await cache.source(for: urlCacheKey) {
            return cached
        }
        guard let resolver = resolver(for: url) else {
            throw RemoteVideoResolverError.unsupportedURL
        }
        let source = try await resolver.resolve(
            url: url,
            preferredSubtitleLanguages: preferredSubtitleLanguages
        )
        await cache.store(
            source,
            keys: [urlCacheKey, source.identity.mediaIdentity.persistenceKey]
        )
        return source
    }

    func resolve(
        identity: RemoteVideoIdentity,
        preferredSubtitleLanguages: [String] = [],
        forceRefresh: Bool = false
    ) async throws -> ResolvedRemoteVideoSource {
        let key = identity.mediaIdentity.persistenceKey
        if !forceRefresh, let cached = await cache.source(for: key) {
            return cached
        }
        let url = identity.canonicalURL ?? identity.originalURL
        let resolver = resolvers.first {
            $0.provider.id == identity.providerID && $0.canResolve(url: url)
        } ?? resolver(for: url)
        guard let resolver else {
            throw RemoteVideoResolverError.unsupportedURL
        }
        let source = try await resolver.resolve(
            url: url,
            preferredSubtitleLanguages: preferredSubtitleLanguages
        )
        await cache.store(
            source,
            keys: [
                key,
                source.identity.mediaIdentity.persistenceKey,
                "url:\(url.absoluteString)",
            ]
        )
        return source
    }
}

actor RemoteVideoResolutionCache {
    static let shared = RemoteVideoResolutionCache()

    private var sources: [String: ResolvedRemoteVideoSource] = [:]

    func source(
        for key: String,
        now: Date = Date()
    ) -> ResolvedRemoteVideoSource? {
        guard let source = sources[key] else { return nil }
        guard !source.isExpired(now: now) else {
            sources.removeValue(forKey: key)
            return nil
        }
        return source
    }

    func store(_ source: ResolvedRemoteVideoSource, keys: [String]) {
        for key in keys where !key.isEmpty {
            sources[key] = source
        }
    }
}
#endif
