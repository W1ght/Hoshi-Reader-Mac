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
    
    var body: some View {
        Group {
            if let image {
                content(Image(decorative: image, scale: 1))
            } else {
                placeholder()
            }
        }
        .task(id: CoverImageKey(url: url, maxPixelSize: maxPixelSize)) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ThumbnailDecoder.shared.thumbnail(url: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else {
                return
            }
            image = loaded
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
