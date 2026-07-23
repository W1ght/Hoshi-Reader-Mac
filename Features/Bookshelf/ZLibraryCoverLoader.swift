//
//  ZLibraryCoverLoader.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum ZLibraryCoverError: Error {
    case noCover
    case invalidImage
    case network
}

actor ZLibraryCoverLoader {
    static let shared = ZLibraryCoverLoader()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let session: URLSession

    private init() {
        memoryCache.countLimit = 160
        memoryCache.totalCostLimit = 48 * 1_024 * 1_024

        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "zlibrary-covers"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 404 || response.statusCode == 410 {
                    throw ZLibraryCoverError.noCover
                }
                guard (200..<300).contains(response.statusCode) else {
                    throw ZLibraryCoverError.network
                }
            }
            guard !data.isEmpty, data.count <= 8 * 1_024 * 1_024 else {
                throw ZLibraryCoverError.invalidImage
            }
            memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ZLibraryCoverError {
            throw error
        } catch {
            throw ZLibraryCoverError.network
        }
    }
}
