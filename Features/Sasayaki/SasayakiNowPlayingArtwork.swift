//
//  SasayakiNowPlayingArtwork.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum SasayakiNowPlayingArtwork {
    static func make(from asset: AVAsset, fallbackCoverURL: URL?) async -> MPMediaItemArtwork? {
        let metadata = try? await asset.load(.metadata)
        let artworkItem = AVMetadataItem
            .metadataItems(from: metadata ?? [], filteredByIdentifier: .commonIdentifierArtwork)
            .first
        let artworkData = try? await artworkItem?.load(.dataValue)

        #if canImport(UIKit)
        let image = artworkData.flatMap(UIImage.init(data:)) ??
            fallbackCoverURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(UIImage.init(data:))

        guard let image else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #elseif canImport(AppKit)
        let image = artworkData.flatMap(NSImage.init(data:)) ??
            fallbackCoverURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(NSImage.init(data:))

        guard let image else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        return nil
        #endif
    }
}
