//
//  WordAudioPlayer.swift
//  Hoshi Reader
//
//  Copyright © 2026 HuangAntimony.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AVFoundation
import OSLog

actor WordAudioPlayer {
    static let shared = WordAudioPlayer()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HoshiReader", category: "WordAudioPlayer")
    
    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var id: UUID?
    private var otherAudioActive = false
    
    private init() {}
    
    func setOtherAudioActive(_ active: Bool) {
        otherAudioActive = active
    }
    
    func stop(id: UUID? = nil) {
        if let id, id != self.id {
            return
        }
        cleanupPlayback()
    }
    
    func play(urlString: String, requestedMode: AudioPlaybackMode, id: UUID) {
        guard let url = URL(string: urlString) else {
            logger.error("Invalid word audio URL: \(urlString, privacy: .public)")
            return
        }

        logger.info("Playing word audio: \(urlString, privacy: .public)")
        
        stopPlayer()
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: categoryOptions(for: requestedMode))
            if !otherAudioActive {
                try session.setActive(true, options: [])
            }
        } catch {
            logger.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.id = id
        
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.cleanupPlayback()
            }
        }
        
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.logPlaybackFailure(item)
                await self.cleanupPlayback()
            }
        }
        
        player.play()
    }

    private func logPlaybackFailure(_ item: AVPlayerItem) {
        let message = item.error?.localizedDescription ?? "unknown error"
        logger.error("Word audio playback failed: \(message, privacy: .public)")
    }
    
    private func cleanupPlayback() {
        stopPlayer()
        if !otherAudioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
    
    private func stopPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        id = nil
        
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
    }
    
    private func categoryOptions(for mode: AudioPlaybackMode) -> AVAudioSession.CategoryOptions {
        switch mode {
        case .interrupt:
            return []
        case .duck:
            return [.mixWithOthers, .duckOthers]
        case .mix:
            return [.mixWithOthers]
        }
    }
}
