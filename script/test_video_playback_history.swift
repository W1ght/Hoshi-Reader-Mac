import Foundation

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message): expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoPlaybackHistoryTests {
    static func main() {
        let suiteName = "moe.shishamo.hoshi.tests.video-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = VideoPlaybackHistoryStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/Show 01.mkv")

        store.save(position: 42.5, duration: 100, for: url)
        expect(store.position(for: url), 42.5, "saved position should be restored")

        store.save(position: 98, duration: 100, for: url)
        expect(store.position(for: url), nil, "near-end position should be cleared")
        expect(store.playbackState(for: url)?.isFinished, true, "near-end state should be retained as watched")

        store.save(position: 1, duration: 0, for: url)
        expect(store.position(for: url), nil, "unknown duration should not be persisted")

        let stateURL = URL(fileURLWithPath: "/tmp/Hoshi Movie.mkv")
        let completedURL = URL(fileURLWithPath: "/tmp/Completed.mkv")
        let legacyURL = URL(fileURLWithPath: "/tmp/Legacy.mkv")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.savePlaybackState(position: 45, duration: 100, updatedAt: date, for: stateURL)
        let state = store.playbackState(for: stateURL)
        expect(state?.position, 45, "new playback state should preserve position")
        expect(state?.duration, 100, "new playback state should preserve duration")
        expect(state?.updatedAt, date, "new playback state should preserve updatedAt")
        expect(
            state?.resumeOptions,
            .empty,
            "playback states without custom options should expose empty resume options"
        )
        expect(
            store.position(for: stateURL),
            45,
            "legacy position API should read the new state"
        )

        let audioTrack = VideoTrack(
            id: 2,
            type: .audio,
            title: "Japanese Audio",
            language: "jpn",
            codec: "aac",
            ffIndex: 1,
            externalFilename: nil,
            isImage: false,
            isSelected: true
        )
        let resumeOptions = VideoPlaybackResumeOptions(
            speed: 1.5,
            subtitleDelay: 0.35,
            audioDelay: -0.25,
            audioSelection: .embedded(VideoAudioTrackIdentity(track: audioTrack))
        )
        store.savePlaybackState(
            position: 55,
            duration: 100,
            updatedAt: date,
            resumeOptions: resumeOptions,
            for: stateURL
        )
        expect(
            store.playbackState(for: stateURL)?.resumeOptions,
            resumeOptions,
            "playback state should round-trip per-video resume options"
        )
        expect(
            try! JSONDecoder().decode(
                VideoPlaybackState.self,
                from: Data(
                    """
                    {"position":12,"duration":100,"updatedAt":\(date.timeIntervalSinceReferenceDate),"isFinished":false}
                    """.utf8
                )
            ).resumeOptions,
            .empty,
            "legacy encoded playback states should decode with empty resume options"
        )

        store.savePlaybackState(position: 99, duration: 100, updatedAt: date, for: completedURL)
        expect(
            store.position(for: completedURL),
            nil,
            "finished playback state should not restore from the end"
        )
        expect(
            store.playbackState(for: completedURL)?.isFinished,
            true,
            "near-complete playback state should be retained as watched"
        )

        store.clearProgress(for: completedURL)
        expect(store.playbackState(for: completedURL), nil, "clearing progress should remove playback state")

        let manuallyWatchedURL = URL(fileURLWithPath: "/tmp/Watched.mkv")
        store.markWatched(duration: 100, updatedAt: date, for: manuallyWatchedURL)
        let watchedState = store.playbackState(for: manuallyWatchedURL)
        expect(watchedState?.isFinished, true, "mark watched should save a finished state")
        expect(watchedState?.progress, 1, "mark watched should report complete progress")
        expect(store.position(for: manuallyWatchedURL), nil, "mark watched should not create a restore position")

        defaults.set(
            [legacyURL.standardizedFileURL.path: 37],
            forKey: "videoPlaybackPositions"
        )
        let legacyState = store.playbackState(for: legacyURL)
        expect(
            legacyState?.position,
            37,
            "new playback state API should read legacy position values"
        )
        expect(
            legacyState?.duration,
            nil,
            "legacy position values should not invent a duration"
        )
        let stateSnapshot = store.playbackStates(for: [stateURL, legacyURL, url])
        expect(
            stateSnapshot[stateURL.standardizedFileURL.path],
            store.playbackState(for: stateURL),
            "batch playback state API should match single state lookup"
        )
        expect(
            stateSnapshot[legacyURL.standardizedFileURL.path],
            legacyState,
            "batch playback state API should preserve legacy position compatibility"
        )

        let originalTrack = VideoTrack(
            id: 4,
            type: .subtitle,
            title: "Japanese",
            language: "jpn",
            codec: "ass",
            ffIndex: 7,
            externalFilename: nil,
            isImage: false,
            isSelected: true
        )
        let embedded = VideoSubtitleSelection.embedded(
            VideoSubtitleTrackIdentity(track: originalTrack)
        )
        store.save(subtitleSelection: embedded, for: url)
        expect(
            store.subtitleSelection(for: url),
            embedded,
            "embedded subtitle selection should round-trip"
        )

        let renumberedTrack = VideoTrack(
            id: 9,
            type: .subtitle,
            title: "Japanese",
            language: "jpn",
            codec: "ass",
            ffIndex: 7,
            externalFilename: nil,
            isImage: false,
            isSelected: false
        )
        expect(
            embedded.matchingTrackID(in: [renumberedTrack]),
            9,
            "embedded subtitle selection should survive mpv track ID changes"
        )
        let reusedTransientID = VideoTrack(
            id: originalTrack.id,
            type: .subtitle,
            title: "English",
            language: "eng",
            codec: "ass",
            ffIndex: 8,
            externalFilename: nil,
            isImage: false,
            isSelected: false
        )
        expect(
            embedded.matchingTrackID(in: [reusedTransientID]),
            nil,
            "a stable FFmpeg identity must not fall back to a reused transient mpv track ID"
        )

        let subtitleURL = URL(fileURLWithPath: "/tmp/Show 01.ja.srt")
        let external = VideoSubtitleSelection.external(
            path: subtitleURL.standardizedFileURL.path
        )
        store.save(subtitleSelection: external, for: url)
        expect(
            store.subtitleSelection(for: url),
            external,
            "external subtitle selection should round-trip"
        )

        store.save(subtitleSelection: .off, for: url)
        expect(
            store.subtitleSelection(for: url),
            .off,
            "disabled subtitles should be remembered explicitly"
        )

        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .off,
                tracks: [],
                isLoaded: false
            ),
            .off,
            "off selection should restore without waiting for tracks"
        )

        let existingSubtitleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-subtitle-\(UUID().uuidString).srt")
        FileManager.default.createFile(
            atPath: existingSubtitleURL.path,
            contents: Data()
        )
        defer { try? FileManager.default.removeItem(at: existingSubtitleURL) }
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .external(path: existingSubtitleURL.path),
                tracks: [],
                isLoaded: false
            ),
            .external(existingSubtitleURL.standardizedFileURL),
            "existing external subtitle should restore before tracks load"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .external(path: existingSubtitleURL.path + ".missing"),
                tracks: [],
                isLoaded: false
            ),
            .unavailable,
            "missing external subtitle should fall back safely"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [],
                isLoaded: false
            ),
            .waitingForTracks,
            "embedded subtitle should wait for mpv track metadata"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [renumberedTrack],
                isLoaded: false
            ),
            .waitingForTracks,
            "embedded subtitle must ignore stale track callbacks until the selected episode is loaded"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [renumberedTrack],
                isLoaded: true
            ),
            .embeddedTrack(9),
            "embedded subtitle should resolve to the current mpv track ID"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [VideoTrack(
                    id: 1,
                    type: .video,
                    title: "Video",
                    language: nil,
                    codec: "h264",
                    ffIndex: 0,
                    externalFilename: nil,
                    isImage: false,
                    isSelected: true
                )],
                isLoaded: true
            ),
            .unavailable,
            "missing embedded subtitle should fall back after tracks finish loading"
        )

        print("Video playback history tests passed")
    }
}
