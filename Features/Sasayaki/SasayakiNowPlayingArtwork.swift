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
import UIKit

enum SasayakiNowPlayingArtwork {
    static func make(from asset: AVAsset, fallbackCoverURL: URL?) async -> MPMediaItemArtwork? {
        let metadata = try? await asset.load(.metadata)
        let artworkItem = AVMetadataItem
            .metadataItems(from: metadata ?? [], filteredByIdentifier: .commonIdentifierArtwork)
            .first
        let artworkData = try? await artworkItem?.load(.dataValue)

        let image = artworkData.flatMap(UIImage.init(data:)) ??
            fallbackCoverURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(UIImage.init(data:))

        guard let image else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
