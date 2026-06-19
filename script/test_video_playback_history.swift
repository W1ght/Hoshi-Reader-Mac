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

        store.save(position: 1, duration: 0, for: url)
        expect(store.position(for: url), nil, "unknown duration should not be persisted")

        print("Video playback history tests passed")
    }
}
