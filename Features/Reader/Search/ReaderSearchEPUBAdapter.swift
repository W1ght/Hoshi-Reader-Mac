import EPUBKit
import Foundation

extension ReaderSearchDocument {
    init(epubDocument document: EPUBDocument, bookInfo: BookInfo) {
        var chapters: [ReaderSearchChapter] = []
        var htmlByPath: [String: String] = [:]

        for (index, spineItem) in document.spine.items.enumerated() {
            guard let item = document.manifest.items[spineItem.idref] else { continue }
            let info = bookInfo.chapterInfo[item.path]
            let path = item.path
            chapters.append(
                ReaderSearchChapter(
                    index: index,
                    path: path,
                    currentTotal: info?.currentTotal ?? 0,
                    characterCount: info?.chapterCount ?? 0
                )
            )
            let url = document.contentDirectory.appendingPathComponent(path)
            htmlByPath[path] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        self.init(
            chapters: chapters,
            htmlByPath: htmlByPath,
            labels: Self.chapterLabels(from: document)
        )
    }

    private static func chapterLabels(from document: EPUBDocument) -> [Int: String] {
        let pathToSpine = Dictionary(
            uniqueKeysWithValues: document.spine.items.enumerated().compactMap { index, spineItem in
                document.manifest.items[spineItem.idref].map { ($0.path, index) }
            }
        )
        var labels: [Int: String] = [:]

        func walk(_ items: [EPUBTableOfContents], topLabel: String?) {
            for item in items {
                let label = topLabel ?? item.label
                let path = item.item?.components(separatedBy: "#").first
                if let path,
                   let index = pathToSpine[path],
                   labels[index] == nil {
                    labels[index] = label
                }
                walk(item.subTable ?? [], topLabel: label)
            }
        }

        walk(document.tableOfContents.subTable ?? [], topLabel: nil)
        return labels
    }
}
