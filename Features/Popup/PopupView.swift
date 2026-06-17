//
//  PopupView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import CHoshiDicts

struct AnkiMiningToast: Identifiable, Equatable {
    let id = UUID()
    let result: AnkiMiningResult

    static func == (lhs: AnkiMiningToast, rhs: AnkiMiningToast) -> Bool {
        lhs.id == rhs.id
    }
}

struct AnkiMiningToastView: View {
    let toast: AnkiMiningToast

    private var title: String {
        switch toast.result.status {
        case .added: return "Card Added"
        case .duplicate: return "Duplicate Found"
        case .failed: return "Add Failed"
        case .pending: return "Sent to Anki"
        }
    }

    private var iconName: String {
        switch toast.result.status {
        case .added: return "checkmark.circle.fill"
        case .duplicate: return "doc.on.doc.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .pending: return "paperplane.fill"
        }
    }

    private var tint: Color {
        switch toast.result.status {
        case .added: return .green
        case .duplicate: return .orange
        case .failed: return .red
        case .pending: return .blue
        }
    }

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                toastContent
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 420, alignment: .leading)
                    .glassEffect(.regular.tint(tint.opacity(0.16)), in: .rect(cornerRadius: 28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(tint.opacity(0.32), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.20), radius: 18, y: 8)
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
            }
            .padding(.horizontal, 18)
        } else {
            toastContent
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 420, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(tint.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.18), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
                .padding(.horizontal, 18)
        }
    }

    private var toastContent: some View {
        HStack(spacing: 13) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(toast.result.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
        }
    }
}

private struct PopupSurfaceStyle: ViewModifier {
    let useLiquidGlass: Bool

    func body(content: Content) -> some View {
        if useLiquidGlass, #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }
}

struct PopupView: View {
    @Environment(UserConfig.self) private var userConfig
    @Binding var isVisible: Bool
    let selectionData: SelectionData?
    let lookupResults: [LookupResult]
    let dictionaryStyles: [String: String]
    let screenSize: CGSize
    let isVertical: Bool
    let isFullWidth: Bool
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let coverURL: URL?
    let documentTitle: String?
    var clearSelection: Bool
    var onTextSelected: ((SelectionData) -> Int?)?
    var onTapOutside: (() -> Void)?
    var onSwipeDismiss: (() -> Void)?
    var onPause: (() -> Void)?
    var sasayakiCue: SasayakiMatch?
    var sasayakiPlayer: SasayakiPlayer?
    var wasPaused = false
    var miningContextProvider: ((String) async -> MiningContext)?
    var onMiningStarted: (([String: String], MiningContext) -> String?)?
    var onMiningFinished: ((String, AnkiMiningResult) -> Void)?

    @State private var content: String = ""
    @State private var lookupEntries: [[String: Any]] = []
    @State private var miningToast: AnkiMiningToast?
    @State private var miningToastTask: Task<Void, Never>?
    @State private var controlsHeight: CGFloat = 0
    @State private var backCount: Int = 0
    @State private var forwardCount: Int = 0
    @State private var backTrigger: Bool = false
    @State private var forwardTrigger: Bool = false

    private var opaquePopupBackground: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }

    init(
        userConfig: UserConfig,
        isVisible: Binding<Bool>,
        selectionData: SelectionData?,
        lookupResults: [LookupResult],
        dictionaryStyles: [String: String],
        screenSize: CGSize,
        isVertical: Bool,
        isFullWidth: Bool,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        coverURL: URL?,
        documentTitle: String?,
        clearSelection: Bool,
        onTextSelected: ((SelectionData) -> Int?)? = nil,
        onTapOutside: (() -> Void)? = nil,
        onSwipeDismiss: (() -> Void)? = nil,
        onPause: (() -> Void)? = nil,
        sasayakiCue: SasayakiMatch? = nil,
        sasayakiPlayer: SasayakiPlayer? = nil,
        wasPaused: Bool = false,
        miningContextProvider: ((String) async -> MiningContext)? = nil,
        onMiningStarted: (([String: String], MiningContext) -> String?)? = nil,
        onMiningFinished: ((String, AnkiMiningResult) -> Void)? = nil
    ) {
        _isVisible = isVisible
        self.selectionData = selectionData
        self.lookupResults = lookupResults
        self.dictionaryStyles = dictionaryStyles
        self.screenSize = screenSize
        self.isVertical = isVertical
        self.isFullWidth = isFullWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.coverURL = coverURL
        self.documentTitle = documentTitle
        self.clearSelection = clearSelection
        self.onTextSelected = onTextSelected
        self.onTapOutside = onTapOutside
        self.onSwipeDismiss = onSwipeDismiss
        self.onPause = onPause
        self.sasayakiCue = sasayakiCue
        self.sasayakiPlayer = sasayakiPlayer
        self.wasPaused = wasPaused
        self.miningContextProvider = miningContextProvider
        self.onMiningStarted = onMiningStarted
        self.onMiningFinished = onMiningFinished

        let cache = Self.buildContent(lookupResults: lookupResults, userConfig: userConfig)
        _content = State(initialValue: cache.content)
        _lookupEntries = State(initialValue: cache.lookupEntries)
    }

    private var layout: PopupLayout? {
        guard let selectionData else {
            return nil
        }

        let result = PopupLayout(
            selectionRect: selectionData.rect,
            screenSize: screenSize,
            maxWidth: CGFloat(userConfig.popupWidth),
            maxHeight: CGFloat(userConfig.popupHeight),
            isVertical: isVertical,
            isFullWidth: isFullWidth,
            topInset: topInset,
            bottomInset: bottomInset
        )

        guard result.width.isFinite,
              result.height.isFinite,
              result.position.x.isFinite,
              result.position.y.isFinite else {
            return nil
        }

        return result
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Button {
                    backTrigger.toggle()
                    backCount -= 1
                    forwardCount += 1
                } label: {
                    Image(systemName: "chevron.left")
                        .opacity(backCount > 0 ? 1 : 0.3)
                }
                .disabled(backCount == 0)

                Button {
                    forwardTrigger.toggle()
                    forwardCount -= 1
                    backCount += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .opacity(forwardCount > 0 ? 1 : 0.3)
                }
                .disabled(forwardCount == 0)
                Spacer()
                Button {
                    onSwipeDismiss?()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            Divider()
        }
    }

    @ViewBuilder
    private func sasayakiControls(for cue: SasayakiMatch, player: SasayakiPlayer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button {
                    Task { @MainActor in
                        await WordAudioPlayer.shared.stop()
                        player.playCue(from: cue, stop: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button {
                    Task { @MainActor in
                        await WordAudioPlayer.shared.stop()
                        if wasPaused {
                            onPause?()
                        } else {
                            player.togglePlayback()
                        }
                    }
                } label: {
                    Image(systemName: player.isPlaying || wasPaused ? "pause.fill" : "play.fill")
                }

                Button {
                    Task { @MainActor in
                        await WordAudioPlayer.shared.stop()
                        player.playCue(from: cue, stop: false)
                        onSwipeDismiss?()
                    }
                } label: {
                    Image(systemName: "forward.frame")
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            Divider()
        }
    }

    private func popupContent(selectionData: SelectionData, layout: PopupLayout) -> some View {
        let showsActionBar = userConfig.popupActionBar
        let activeControlsHeight = showsActionBar || (sasayakiCue != nil && sasayakiPlayer?.hasAudio == true) ? controlsHeight : 0

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showsActionBar {
                    actionBar
                }
                if let cue = sasayakiCue, let player = sasayakiPlayer, player.hasAudio {
                    sasayakiControls(for: cue, player: player)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                controlsHeight = $0
            }

            PopupWebView(
                content: content,
                position: CGPoint(x: layout.position.x - layout.width / 2, y: layout.position.y - layout.height / 2 + activeControlsHeight),
                scale: CGFloat(userConfig.popupScale),
                clearSelection: clearSelection,
                hoverLookupDelayMs: userConfig.desktopLookupHoverDelayMs,
                dictionaryStyles: dictionaryStyles,
                lookupEntries: lookupEntries,
                scanNonJapaneseText: userConfig.scanNonJapaneseText,
                scanLength: userConfig.scanLength,
                backTrigger: backTrigger,
                forwardTrigger: forwardTrigger,
                onMine: { content in
                    let result = await mineEntry(content: content, sentence: selectionData.sentence)
                    showMiningToast(for: result)
                    return result
                },
                onTextSelected: onTextSelected,
                onTapOutside: onTapOutside,
                onSwipeDismiss: onSwipeDismiss,
                onRedirect: { query in
                    let results = LookupEngine.shared.lookup(
                        query,
                        maxResults: userConfig.maxResults,
                        scanLength: userConfig.scanLength
                    )
                    let entries = Self.buildLookupEntries(lookupResults: results)
                    if !entries.isEmpty {
                        backCount += 1
                        forwardCount = 0
                    }
                    return entries
                }
            )
        }
        .frame(width: layout.width, height: layout.height)
    }

    var body: some View {
        if #available(iOS 26, macOS 26, *), !userConfig.popupDisableTransparency {
            GlassEffectContainer(spacing: 18) {
                ZStack(alignment: .top) {
                    if isVisible, let selectionData, let layout, !content.isEmpty {
                        popupContent(selectionData: selectionData, layout: layout)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                            .position(layout.position)
                    }
                    topToast
                }
            }
            .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
        } else {
            ZStack(alignment: .top) {
                if isVisible, let selectionData, let layout, !content.isEmpty {
                    popupContent(selectionData: selectionData, layout: layout)
                        .background(
                            userConfig.popupDisableTransparency ? opaquePopupBackground : AnyShapeStyle(.ultraThinMaterial),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        .position(layout.position)
                }
                topToast
            }
            .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
        }
    }

    @ViewBuilder
    private var topToast: some View {
        if let miningToast {
            AnkiMiningToastView(toast: miningToast)
                .padding(.top, max(18, topInset + 18))
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1000)
                .allowsHitTesting(false)
        }
    }

    private func mineEntry(content: [String: String], sentence: String) async -> AnkiMiningResult {
        var sasayakiAudioData: Data?
        if AnkiManager.shared.needsSasayakiAudio, let cue = sasayakiCue, let player = sasayakiPlayer, player.hasAudio {
            sasayakiAudioData = await player.cueSentenceAudio(cue, sentence: sentence)
        }

        let context = if let miningContextProvider {
            await miningContextProvider(sentence)
        } else {
            MiningContext(
                sentence: sentence,
                documentTitle: documentTitle,
                coverURL: coverURL,
                sasayakiAudioData: sasayakiAudioData
            )
        }
        let historyID = onMiningStarted?(content, context)
        let result = await mineAnkiEntry(content: content, context: context)
        if let historyID {
            onMiningFinished?(historyID, result)
        }
        return result
    }

    private func showMiningToast(for result: AnkiMiningResult) {
        withAnimation(.default.speed(1.4)) {
            miningToast = AnkiMiningToast(result: result)
        }
        miningToastTask?.cancel()
        miningToastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.default.speed(1.4)) {
                    miningToast = nil
                }
            }
        }
    }

    private static func buildLookupEntries(lookupResults: [LookupResult]) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        for result in lookupResults {
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.reversed().map {
                [
                    "name": String($0.name),
                    "description": String($0.description),
                ]
            }

            var glossaries: [[String: Any]] = []
            for glossary in result.term.glossaries {
                glossaries.append([
                    "dictionary": String(glossary.dict_name),
                    "content": String(glossary.glossary),
                    "definitionTags": String(glossary.definition_tags),
                    "termTags": String(glossary.term_tags),
                ])
            }

            var frequencies: [[String: Any]] = []
            for frequency in result.term.frequencies {
                var frequencyTags: [[String: Any]] = []
                for frequencyTag in frequency.frequencies {
                    frequencyTags.append([
                        "value": Int(frequencyTag.value),
                        "displayValue": String(frequencyTag.display_value),
                    ])
                }
                frequencies.append([
                    "dictionary": String(frequency.dict_name),
                    "frequencies": frequencyTags,
                ])
            }

            var pitches: [[String: Any]] = []
            for pitchEntry in result.term.pitches {
                var pitchPositions: [Int] = []
                var transcriptions: [String] = []
                for element in pitchEntry.pitch_positions {
                    let position = Int(element)
                    if !pitchPositions.contains(position) {
                        pitchPositions.append(position)
                    }
                }
                for element in pitchEntry.transcriptions {
                    let transcription = String(element)
                    if !transcriptions.contains(transcription) {
                        transcriptions.append(transcription)
                    }
                }
                pitches.append([
                    "dictionary": String(pitchEntry.dict_name),
                    "pitchPositions": pitchPositions,
                    "transcriptions": transcriptions
                ])
            }

            let rules = String(result.term.rules).split(separator: " ").map { String($0) }

            entries.append([
                "expression": expression,
                "reading": reading,
                "matched": matched,
                "deinflectionTrace": deinflectionTrace,
                "glossaries": glossaries,
                "frequencies": frequencies,
                "pitches": pitches,
                "rules": rules,
            ])
        }
        return entries
    }

    private static func buildContent(lookupResults: [LookupResult], userConfig: UserConfig) -> (content: String, lookupEntries: [[String: Any]]) {
        let entries = buildLookupEntries(lookupResults: lookupResults)

        let collapsedDictionaries = userConfig.collapseMode == .custom
        ? ((try? JSONEncoder().encode(DictionaryManager.shared.collapsedDictionaries))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]") : "[]"
        let audioSources = (try? JSONEncoder().encode(userConfig.enabledAudioSources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let scaledCSS = userConfig.customCSS.replacingOccurrences(of: #"(-?(?:\d+(?:\.\d+)?|\.\d+))px"#, with: "calc($1px * var(--popup-scale))", options: .regularExpression)
        let customCSS = (try? JSONSerialization.data(withJSONObject: scaledCSS, options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        let content = """
        <script>
            window.collapseMode = "\(userConfig.collapseMode.rawValue)";
            window.expandFirstDictionary = \(userConfig.expandFirstDictionary);
            window.collapsedDictionaries = \(collapsedDictionaries);
            window.compactGlossaries = \(userConfig.compactGlossaries);
            window.showExpressionTags = \(userConfig.showExpressionTags);
            window.harmonicFrequency = \(userConfig.harmonicFrequency);
            window.deduplicatePitchAccents = \(userConfig.deduplicatePitchAccents);
            window.compactPitchAccents = \(userConfig.compactPitchAccents);
            window.audioSources = \(audioSources);
            window.audioEnableAutoplay = \(userConfig.audioEnableAutoplay);
            window.audioPlaybackMode = "\(userConfig.audioPlaybackMode.rawValue)";
            window.needsAudio = \(AnkiManager.shared.needsAudio);
            window.allowDupes = \(AnkiManager.shared.allowDupes);
            window.useAnkiConnect = \(AnkiManager.shared.useAnkiConnect);
            window.embedMedia = \(AnkiManager.shared.embedMedia);
            window.compactGlossariesAnki = \(AnkiManager.shared.compactGlossaries);
            window.customCSS = \(customCSS);
            window.swipeThreshold = \(userConfig.popupSwipeToDismiss ? userConfig.popupSwipeThreshold : 0);
        </script>
        <div id="entries-container"></div>
        """

        return (content, entries)
    }
}
