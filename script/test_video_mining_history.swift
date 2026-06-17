import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoMiningHistoryTests {
    @MainActor
    static func main() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-mining-history-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("history.json")
        let store = VideoMiningHistoryStore(fileURL: fileURL, limit: 2)
        let context = MiningContext(
            sentence: "星を見ています。",
            documentTitle: "Episode 1.mkv",
            coverURL: nil,
            video: VideoMiningContext(
                fileName: "Episode 1.mkv",
                cueText: "星を見ています。",
                cueStart: 65.25,
                cueEnd: 68.5,
                previousCueText: "夜になりました。",
                nextCueText: "きれいですね。",
                screenshotURL: URL(fileURLWithPath: "/tmp/shot.png"),
                audioClipURL: URL(fileURLWithPath: "/tmp/audio.m4a")
            )
        )

        let firstID = store.recordPending(
            id: "first",
            content: [
                "expression": "星",
                "reading": "ほし",
                "matched": "星",
                "glossaryFirst": "star",
                "popupSelectionText": "星"
            ],
            context: context,
            date: Date(timeIntervalSince1970: 100)
        )
        expect(firstID == "first", "pending record should return its id")
        expect(store.items.count == 1, "store should append a pending item")
        expect(store.items[0].status == .pending, "new item should be pending")
        expect(store.items[0].videoFileName == "Episode 1.mkv", "item should preserve video file")
        expect(store.items[0].subtitleText == "星を見ています。", "item should preserve subtitle text")
        expect(store.items[0].previousSubtitleText == "夜になりました。", "item should preserve previous subtitle")
        expect(store.items[0].nextSubtitleText == "きれいですね。", "item should preserve next subtitle")
        expect(store.items[0].screenshotPath == "/tmp/shot.png", "item should preserve screenshot path")
        expect(store.items[0].audioClipPath == "/tmp/audio.m4a", "item should preserve audio path")

        store.update(
            id: "first",
            status: .added,
            message: "Added to Anki.",
            date: Date(timeIntervalSince1970: 110)
        )
        expect(store.items[0].status == .added, "status update should replace pending state")
        expect(store.items[0].message == "Added to Anki.", "status update should keep result message")

        _ = store.recordPending(
            id: "second",
            content: ["expression": "月"],
            context: context,
            date: Date(timeIntervalSince1970: 120)
        )
        _ = store.recordPending(
            id: "third",
            content: ["expression": "空"],
            context: context,
            date: Date(timeIntervalSince1970: 130)
        )
        expect(store.items.map(\.id) == ["second", "third"], "store should prune to the latest limit")

        let reloaded = VideoMiningHistoryStore(fileURL: fileURL, limit: 2)
        expect(reloaded.items.map(\.id) == ["second", "third"], "store should persist pruned items")

        reloaded.delete(id: "second")
        expect(reloaded.items.map(\.id) == ["third"], "delete should remove one item")

        reloaded.clear()
        expect(reloaded.items.isEmpty, "clear should remove all items")

        let nonVideo = MiningContext(sentence: "星", documentTitle: nil, coverURL: nil)
        let skipped = reloaded.recordPending(
            id: "non-video",
            content: ["expression": "星"],
            context: nonVideo,
            date: Date(timeIntervalSince1970: 140)
        )
        expect(skipped == nil, "non-video mining should not enter video history")
        expect(reloaded.items.isEmpty, "non-video mining should leave history unchanged")

        print("Video mining history tests passed")
    }
}
