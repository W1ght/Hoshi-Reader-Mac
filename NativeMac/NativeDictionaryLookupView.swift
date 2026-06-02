import CHoshiDicts
import SwiftUI

struct NativeDictionaryLookupView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var query = ""
    @State private var results: [NativeDictionaryLookupResult] = []
    @State private var dictionarySummary = "未加载"
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeMigrationStatusView(
                title: "复用现有 LookupEngine",
                rows: [
                    "扫描现有 Yomitan/Hoshi 词典目录",
                    "调用 LookupEngine 查询",
                    "暂不接 PopupWebView、递归查词和制卡"
                ]
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("输入日语词或句子", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(runLookup)

                Button("查询", action: runLookup)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Label(dictionarySummary, systemImage: "character.book.closed")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rebuildLookup()
                    runLookup()
                } label: {
                    Label("重新加载词典", systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage {
                ContentUnavailableView {
                    Label("词典查询不可用", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "character.magnify.ja")
                } description: {
                    Text("输入查询词后会在这里显示结果。")
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(result.expression)
                                    .font(.title2.bold())
                                if !result.reading.isEmpty {
                                    Text(result.reading)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(result.matched)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(result.glossaries, id: \.self) { glossary in
                                Text(glossary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .onAppear(perform: rebuildLookup)
    }

    private func rebuildLookup() {
        do {
            let paths = try NativeDictionaryLookupStore.enabledDictionaryPaths()
            LookupEngine.shared.buildQuery(
                termPaths: paths.term,
                freqPaths: paths.frequency,
                pitchPaths: paths.pitch
            )
            dictionarySummary = "\(paths.term.count) term / \(paths.frequency.count) frequency / \(paths.pitch.count) pitch"
            errorMessage = nil
        } catch {
            dictionarySummary = "未加载"
            errorMessage = error.localizedDescription
        }
    }

    private func runLookup() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        results = LookupEngine.shared
            .lookup(trimmed, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength)
            .map(NativeDictionaryLookupResult.init)
    }
}

private enum NativeDictionaryLookupStore {
    static func enabledDictionaryPaths() throws -> (term: [URL], frequency: [URL], pitch: [URL]) {
        let root = try BookStorage.getAppDirectory().appendingPathComponent("Dictionaries")
        let config = BookStorage.load(DictionaryConfig.self, from: root.appendingPathComponent("config.json"))
        return (
            try paths(root: root, type: "Term", entries: config?.termDictionaries),
            try paths(root: root, type: "Frequency", entries: config?.frequencyDictionaries),
            try paths(root: root, type: "Pitch", entries: config?.pitchDictionaries)
        )
    }

    private static func paths(root: URL, type: String, entries: [DictionaryConfig.DictionaryEntry]?) throws -> [URL] {
        let directory = root.appendingPathComponent(type)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }

        let stored = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
                && BookStorage.load(DictionaryIndex.self, from: url.appendingPathComponent("index.json")) != nil
        }

        guard let entries else {
            return stored
        }

        let byName = Dictionary(uniqueKeysWithValues: stored.map { ($0.lastPathComponent, $0) })
        return entries
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .compactMap { byName[$0.fileName] }
    }
}

private struct NativeDictionaryLookupResult: Identifiable {
    let id = UUID()
    let expression: String
    let reading: String
    let matched: String
    let glossaries: [String]

    init(_ result: LookupResult) {
        expression = String(result.term.expression)
        reading = String(result.term.reading)
        matched = String(result.matched)
        glossaries = result.term.glossaries.prefix(4).map {
            let dictionary = String($0.dict_name)
            let content = String($0.glossary)
            return dictionary.isEmpty ? content : "\(dictionary): \(content)"
        }
    }
}
