import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum DictionaryReorderTests {
    static func main() {
        let id = UUID()
        let payload = DictionaryReorder.payload(for: id)

        expect(
            DictionaryReorder.dictionaryID(from: payload) == id,
            "dictionary drag payload should round-trip its UUID"
        )
        expect(
            DictionaryReorder.dictionaryID(from: id.uuidString) == nil,
            "unscoped text drops should not reorder dictionaries"
        )
        expect(
            DictionaryReorder.destinationOffset(sourceIndex: 0, targetIndex: 2) == 3,
            "dragging downward should insert after the target row"
        )
        expect(
            DictionaryReorder.destinationOffset(sourceIndex: 2, targetIndex: 0) == 0,
            "dragging upward should insert before the target row"
        )
        expect(
            DictionaryReorder.destinationOffset(sourceIndex: 1, targetIndex: 1) == nil,
            "dropping on the same row should not persist a redundant reorder"
        )

        print("Dictionary reorder tests passed")
    }
}
