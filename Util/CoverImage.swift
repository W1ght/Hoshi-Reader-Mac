//
//  CoverImage.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import ImageIO

struct CoverImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: Int
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: CGImage?
    @State private var imageKey: CoverImageKey?
    
    var body: some View {
        let key = CoverImageKey(url: url, maxPixelSize: maxPixelSize)
        let displayedImage = (imageKey == key ? image : nil)
            ?? CoverImageMemoryCache.shared.image(for: key)

        Group {
            if let displayedImage {
                content(Image(decorative: displayedImage, scale: 1))
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            guard let url else {
                image = nil
                imageKey = key
                return
            }
            if let cached = CoverImageMemoryCache.shared.image(for: key) {
                image = cached
                imageKey = key
                return
            }
            image = nil
            imageKey = key
            let loaded = await ThumbnailDecoder.shared.thumbnail(url: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else {
                return
            }
            if let loaded {
                CoverImageMemoryCache.shared.insert(loaded, for: key)
            }
            image = loaded
            imageKey = key
        }
    }
}

enum CoverThumbnailCache {
    static func preheat(
        urls: some Sequence<URL>,
        maxPixelSize: Int,
        limit: Int = 32
    ) async {
        for url in urls.prefix(limit) {
            guard !Task.isCancelled else { return }
            let key = CoverImageKey(url: url, maxPixelSize: maxPixelSize)
            if CoverImageMemoryCache.shared.image(for: key) != nil {
                continue
            }
            if let loaded = await ThumbnailDecoder.shared.thumbnail(
                url: url,
                maxPixelSize: maxPixelSize
            ) {
                CoverImageMemoryCache.shared.insert(loaded, for: key)
            }
        }
    }
}

private struct CoverImageKey: Hashable {
    let path: String?
    let maxPixelSize: Int
    
    init(url: URL?, maxPixelSize: Int) {
        self.path = url?.path(percentEncoded: false)
        self.maxPixelSize = maxPixelSize
    }
}

private final class CoverImageMemoryCache: @unchecked Sendable {
    static let shared = CoverImageMemoryCache()

    private let cache = NSCache<NSString, CGImageBox>()

    private init() {
        cache.countLimit = 256
    }

    func image(for key: CoverImageKey) -> CGImage? {
        cache.object(forKey: key.cacheKey)?.image
    }

    func insert(_ image: CGImage, for key: CoverImageKey) {
        cache.setObject(CGImageBox(image), forKey: key.cacheKey)
    }
}

private final class CGImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private extension CoverImageKey {
    var cacheKey: NSString {
        "\(path ?? "<nil>")#\(maxPixelSize)" as NSString
    }
}

private actor ThumbnailDecoder {
    static let shared = ThumbnailDecoder()

    func thumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }
}
