import CHoshiDicts
import SwiftUI
import WebKit

struct NativeDictionaryLookupView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var query = ""
    @State private var results: [NativeDictionaryLookupResult] = []
    @State private var dictionarySummary = "未加载词典"
    @State private var errorMessage: String?
    @State private var hasSearched = false

    private var html: String {
        NativeDictionaryHTMLRenderer.html(
            query: query,
            results: results,
            customCSS: userConfig.customCSS,
            scale: userConfig.popupScale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchBar

            HStack {
                Label(dictionarySummary, systemImage: "character.book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    rebuildLookup()
                    runLookup()
                } label: {
                    Label("重新加载", systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage {
                ContentUnavailableView {
                    Label("词典查询不可用", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if !hasSearched {
                ContentUnavailableView {
                    Label("查询词典", systemImage: "character.magnify.ja")
                } description: {
                    Text("输入日语词或句子后会在这里显示词典结果。")
                }
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("没有结果", systemImage: "magnifyingglass")
                } description: {
                    Text("换一个词或检查是否已启用 term 词典。")
                }
            } else {
                NativeDictionaryResultWebView(html: html)
                    .frame(minHeight: 540)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
            }
        }
        .onAppear(perform: rebuildLookup)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("输入日语词或句子", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit(runLookup)

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button("查询", action: runLookup)
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
    }

    private func rebuildLookup() {
        do {
            let paths = try NativeDictionaryLookupStore.enabledDictionaryPaths()
            LookupEngine.shared.buildQuery(
                termPaths: paths.term,
                freqPaths: paths.frequency,
                pitchPaths: paths.pitch
            )
            dictionarySummary = "\(paths.term.count) 个词典 / \(paths.frequency.count) 个频率 / \(paths.pitch.count) 个声调"
            errorMessage = nil
        } catch {
            dictionarySummary = "未加载词典"
            errorMessage = error.localizedDescription
        }
    }

    private func runLookup() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSearched = true
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        results = LookupEngine.shared
            .lookup(trimmed, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength)
            .map(NativeDictionaryLookupResult.init)
    }
}

private struct NativeDictionaryResultWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
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
    let rules: [String]
    let trace: [String]
    let glossaries: [NativeGlossary]
    let frequencies: [NativeFrequency]
    let pitches: [NativePitch]

    init(_ result: LookupResult) {
        expression = String(result.term.expression)
        reading = String(result.term.reading)
        matched = String(result.matched)
        rules = String(result.term.rules)
            .split(separator: " ")
            .map(String.init)
        trace = result.trace.reversed().map {
            let name = String($0.name)
            let description = String($0.description)
            return description.isEmpty ? name : "\(name): \(description)"
        }
        glossaries = result.term.glossaries.map {
            NativeGlossary(
                dictionary: String($0.dict_name),
                content: String($0.glossary),
                definitionTags: String($0.definition_tags),
                termTags: String($0.term_tags)
            )
        }
        frequencies = result.term.frequencies.map { frequency in
            NativeFrequency(
                dictionary: String(frequency.dict_name),
                values: frequency.frequencies.map {
                    let display = String($0.display_value)
                    return display.isEmpty ? "\(Int($0.value))" : display
                }
            )
        }
        pitches = result.term.pitches.map { pitch in
            var positions: [String] = []
            for value in pitch.pitch_positions {
                let text = "\(Int(value))"
                if !positions.contains(text) {
                    positions.append(text)
                }
            }
            var transcriptions: [String] = []
            for value in pitch.transcriptions {
                let text = String(value)
                if !text.isEmpty, !transcriptions.contains(text) {
                    transcriptions.append(text)
                }
            }
            return NativePitch(
                dictionary: String(pitch.dict_name),
                positions: positions,
                transcriptions: transcriptions
            )
        }
    }
}

private struct NativeGlossary {
    let dictionary: String
    let content: String
    let definitionTags: String
    let termTags: String
}

private struct NativeFrequency {
    let dictionary: String
    let values: [String]
}

private struct NativePitch {
    let dictionary: String
    let positions: [String]
    let transcriptions: [String]
}

private enum NativeDictionaryHTMLRenderer {
    static func html(query: String, results: [NativeDictionaryLookupResult], customCSS: String, scale: Double) -> String {
        let entries = results.enumerated().map { index, result in
            entryHTML(index: index + 1, result: result)
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root {
          color-scheme: light dark;
          --popup-scale: \(scale);
          --accent: #3b82f6;
          --muted: color-mix(in srgb, CanvasText 55%, transparent);
          --border: color-mix(in srgb, CanvasText 14%, transparent);
        }
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          color: CanvasText;
          font: 16px -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Hiragino Kaku Gothic ProN", sans-serif;
        }
        body { padding: 18px; }
        .query {
          color: var(--muted);
          font-size: 13px;
          margin-bottom: 14px;
        }
        .entry {
          border: 1px solid var(--border);
          border-radius: 8px;
          padding: 16px;
          margin-bottom: 12px;
          background: color-mix(in srgb, Canvas 92%, CanvasText 3%);
        }
        .entry-header {
          display: flex;
          align-items: baseline;
          gap: 10px;
          border-bottom: 1px solid var(--border);
          padding-bottom: 10px;
          margin-bottom: 12px;
        }
        .number {
          color: var(--muted);
          font-weight: 700;
          min-width: 1.8em;
        }
        .expression {
          font-size: 30px;
          font-weight: 750;
          letter-spacing: 0;
        }
        .reading {
          color: var(--muted);
          font-size: 16px;
        }
        .matched {
          margin-left: auto;
          color: var(--muted);
          font-size: 12px;
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          margin: 8px 0 12px;
        }
        .chip {
          border-radius: 5px;
          padding: 2px 7px;
          font-size: 12px;
          background: color-mix(in srgb, var(--accent) 18%, transparent);
          color: color-mix(in srgb, var(--accent) 82%, CanvasText);
        }
        .dictionary {
          color: var(--muted);
          font-size: 13px;
          margin-top: 12px;
          margin-bottom: 4px;
        }
        .glossary {
          line-height: 1.65;
          font-size: 16px;
        }
        .meta {
          color: var(--muted);
          font-size: 12px;
          line-height: 1.5;
        }
        ruby rt { font-size: 55%; }
        img { max-width: 100%; height: auto; }
        \(customCSS)
        </style>
        </head>
        <body>
        <div class="query">\(escape(query))</div>
        \(entries)
        </body>
        </html>
        """
    }

    private static func entryHTML(index: Int, result: NativeDictionaryLookupResult) -> String {
        let reading = result.reading.isEmpty ? "" : #"<span class="reading">\#(escape(result.reading))</span>"#
        let matched = result.matched.isEmpty ? "" : #"<span class="matched">\#(escape(result.matched))</span>"#
        let chips = chipHTML(result.rules + result.trace)
        let frequency = result.frequencies.isEmpty ? "" : metadataHTML(
            title: "Frequency",
            rows: result.frequencies.map { "\($0.dictionary): \($0.values.joined(separator: ", "))" }
        )
        let pitch = result.pitches.isEmpty ? "" : metadataHTML(
            title: "Pitch",
            rows: result.pitches.map {
                let positions = $0.positions.isEmpty ? "-" : $0.positions.joined(separator: ", ")
                let transcriptions = $0.transcriptions.isEmpty ? "" : " / \($0.transcriptions.joined(separator: ", "))"
                return "\($0.dictionary): \(positions)\(transcriptions)"
            }
        )
        let glossaries = result.glossaries.map { glossary in
            let tags = [glossary.termTags, glossary.definitionTags]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let tagHTML = tags.isEmpty ? "" : #"<div class="meta">\#(escape(tags))</div>"#
            return """
            <div class="dictionary">\(escape(glossary.dictionary))</div>
            \(tagHTML)
            <div class="glossary">\(glossary.content)</div>
            """
        }.joined(separator: "\n")

        return """
        <section class="entry">
          <div class="entry-header">
            <span class="number">\(index).</span>
            <span class="expression">\(escape(result.expression))</span>
            \(reading)
            \(matched)
          </div>
          \(chips)
          \(frequency)
          \(pitch)
          \(glossaries)
        </section>
        """
    }

    private static func chipHTML(_ values: [String]) -> String {
        let unique = Array(NSOrderedSet(array: values.filter { !$0.isEmpty })) as? [String] ?? []
        guard !unique.isEmpty else { return "" }
        return #"<div class="chips">\#(unique.map { #"<span class="chip">\#(escape($0))</span>"# }.joined())</div>"#
    }

    private static func metadataHTML(title: String, rows: [String]) -> String {
        guard !rows.isEmpty else { return "" }
        return """
        <div class="meta"><strong>\(escape(title))</strong>: \(escape(rows.joined(separator: " | ")))</div>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
