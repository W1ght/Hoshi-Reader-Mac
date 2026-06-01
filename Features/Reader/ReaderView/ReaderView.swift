//
//  ReaderView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit

struct WebViewState: Hashable {
    var verticalWriting: Bool
    var fontSize: Int
    var selectedFont: String
    var hideFurigana: Bool
    var horizontalPadding: Int
    var verticalPadding: Int
    var avoidPageBreak: Bool
    var justifyText: Bool
    var blurImages: Bool
    var layoutAdvanced: Bool
    var lineHeight: Double
    var characterSpacing: Double
    var paragraphSpacing: Double
    var size: CGSize
}

struct ReaderLoader: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderLoaderViewModel

    init(book: BookMetadata) {
        _viewModel = State(initialValue: ReaderLoaderViewModel(book: book))
    }

    var body: some View {
        if let doc = viewModel.document, let root = viewModel.rootURL {
            ReaderView(
                book: viewModel.book,
                document: doc,
                rootURL: root,
                enableStatistics: userConfig.enableStatistics,
                autostartStatistics: userConfig.statisticsAutostartMode == .on,
                autoSyncEnabled: userConfig.enableSync && userConfig.enableAutoSync,
                syncBookData: userConfig.enableSync && userConfig.syncUploadBooks,
                syncStats: userConfig.enableSync && userConfig.statisticsEnableSync,
                statsSyncMode: userConfig.statisticsSyncMode,
                syncAudioBook: userConfig.enableSasayaki && userConfig.sasayakiEnableSync
            )
        }
    }
}

struct ReaderView: View {
    @Environment(\.dismissReader) private var dismissReader
    @Environment(\.openReaderTab) private var openReaderTab
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(UserConfig.self) private var userConfig
    @State private var viewModel: ReaderViewModel
    @State private var topSafeArea: CGFloat = AppPlatform.topSafeArea
    @State private var focusMode = false
    @State private var inactiveSince: Date?
    @State private var imageURL: URL?

    private var sepiaInverted: Bool {
        userConfig.theme == .sepia && userConfig.sepiaInvertInDark && systemColorScheme == .dark
    }

    private var readerBackgroundColor: Color {
        if sepiaInverted {
            return Color(red: 0.094, green: 0.082, blue: 0.047)
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return Color(red: 0.949, green: 0.886, blue: 0.788)
        }
        return userConfig.theme == .custom ? userConfig.customBackgroundColor : Color(.systemBackground)
    }

    private var readerTextColor: String? {
        if sepiaInverted {
            return "#F2E2C9"
        }
        if userConfig.theme == .sepia || (userConfig.theme == .system && userConfig.systemLightSepia && systemColorScheme == .light) {
            return "#332A1B"
        }
        return userConfig.theme == .custom ? UIColor(userConfig.customTextColor).hexString : nil
    }
    
    private var readerTheme: ColorScheme {
        if userConfig.theme == .custom {
            return userConfig.uiTheme.colorScheme ?? systemColorScheme
        }
        if userConfig.theme == .sepia && userConfig.sepiaInvertInDark {
            return systemColorScheme
        }
        return userConfig.theme.colorScheme ?? systemColorScheme
    }
    
    private var sasayakiTextColor: Color {
        readerTheme == .dark ? userConfig.sasayakiDarkTextColor : userConfig.sasayakiTextColor
    }
    
    private var sasayakiBackgroundColor: Color {
        readerTheme == .dark ? userConfig.sasayakiDarkBackgroundColor : userConfig.sasayakiBackgroundColor
    }
    
    private var topChromeInset: CGFloat {
        AppPlatform.usesDesktopLayout ? 8 : max(topSafeArea, 25)
    }

    private var bottomChromeInset: CGFloat {
        AppPlatform.usesDesktopLayout ? 30 : max(AppPlatform.bottomSafeArea, 16)
    }

    private var bottomControlOverlayHeight: CGFloat {
        AppPlatform.usesDesktopLayout ? 78 : 72
    }

    private var desktopInfoLeading: CGFloat {
        28
    }

    private var desktopInfoTrailing: CGFloat {
        30
    }

    private func toggleReaderChrome() {
        withAnimation(.default.speed(2)) {
            focusMode.toggle()
        }
    }

    private func hideReaderChrome() {
        guard !focusMode else { return }
        withAnimation(.default.speed(2)) {
            focusMode = true
        }
    }

    private func handleReaderTapOutside() {
        if viewModel.popups.isEmpty {
            toggleReaderChrome()
        } else {
            viewModel.closePopups()
        }
    }

    private func openTabFromReader(_ tab: Int) {
        openReaderTab?(tab)
    }

    private func updateSasayakiColors() {
        viewModel.bridge.send(.updateSasayakiColors(
            textHex: UIColor(sasayakiTextColor).hexString,
            backgroundHex: UIColor(sasayakiBackgroundColor).hexString
        ))
    }

    private func flushAutoSyncAfterResignActive() {
        Task {
            await viewModel.flushAutoSync()
        }
    }

    private func handleReaderBecameActive() {
        let shouldResync = inactiveSince.map { Date.now.timeIntervalSince($0) >= 600 } ?? false
        inactiveSince = nil
        if shouldResync {
            Task {
                await viewModel.syncAfterForeground()
            }
        }
        viewModel.sasayakiPlayer.refreshDisplayedCue()
        guard viewModel.isTracking else {
            return
        }
        viewModel.resetTrackingBaseline()
        viewModel.isPaused = false
    }

    private func handleReaderResignedActive() {
        guard inactiveSince == nil else {
            return
        }
        inactiveSince = .now
        flushAutoSyncAfterResignActive()
        guard viewModel.isTracking else {
            return
        }
        viewModel.isPaused = true
    }

    init(
        book: BookMetadata,
        document: EPUBDocument,
        rootURL: URL,
        enableStatistics: Bool,
        autostartStatistics: Bool,
        autoSyncEnabled: Bool,
        syncBookData: Bool,
        syncStats: Bool,
        statsSyncMode: StatisticsSyncMode,
        syncAudioBook: Bool
    ) {
        _viewModel = State(initialValue: ReaderViewModel(
            book: book,
            document: document,
            rootURL: rootURL,
            enableStatistics: enableStatistics,
            autostartStatistics: autostartStatistics,
            autoSyncEnabled: autoSyncEnabled,
            syncBookData: syncBookData,
            syncStats: syncStats,
            statsSyncMode: statsSyncMode,
            syncAudioBook: syncAudioBook
        ))
    }

    private var progressString: String {
        var result: [String] = []
        if userConfig.readerShowCharacters {
            result.append("\(viewModel.currentCharacter) / \(viewModel.bookInfo.characterCount)")
        }
        if userConfig.readerShowPercentage {
            let percent = viewModel.bookInfo.characterCount > 0 ? (Double(viewModel.currentCharacter) / Double(viewModel.bookInfo.characterCount) * 100) : 0
            result.append("\(String(format: "%.2f%%", percent))")
        }
        return result.joined(separator: " ")
    }

    private var statisticsString: String {
        var result: [String] = []
        if userConfig.readerShowReadingSpeed {
            result.append("\(viewModel.sessionStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h")
        }
        if userConfig.readerShowReadingTime {
            result.append("\(Duration.seconds(viewModel.sessionStatistics.readingTime).formatted(.time(pattern: .hourMinute)))")
        }
        return result.joined(separator: " ")
    }

    private func readerInfoChromeContentWidth(title: String?, showTitle: Bool, showProgress: Bool) -> CGFloat {
        let titleWidth: CGFloat = if showTitle, let title {
            title.size(withAttributes: [
                .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .semibold)
            ]).width
        } else {
            0
        }
        let progressWidth: CGFloat = if showProgress {
            progressString.size(withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium)
            ]).width + 4
        } else {
            0
        }

        return min(max(max(titleWidth, progressWidth), 74), 260)
    }

    private func dismissCurrentReader() {
        if viewModel.isTracking {
            viewModel.stopTracking()
        }
        dismissReader?()
    }

    private func navigateBackward() {
        viewModel.closePopups()
        if userConfig.continuousMode {
            viewModel.bridge.send(.stepContinuous(.backward))
            return
        }
        viewModel.bridge.send(.navigate(.backward))
        if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
            viewModel.startTracking()
        }
    }

    private func navigateForward() {
        viewModel.closePopups()
        if userConfig.continuousMode {
            viewModel.bridge.send(.stepContinuous(.forward))
            return
        }
        viewModel.bridge.send(.navigate(.forward))
        if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
            viewModel.startTracking()
        }
    }

    private func toggleStatisticsTracking() {
        guard userConfig.enableStatistics else {
            return
        }
        if viewModel.isTracking {
            viewModel.stopTracking()
        } else {
            viewModel.startTracking()
        }
    }

    private func toggleSasayakiPlayback() {
        guard userConfig.enableSasayaki,
              viewModel.sasayakiPlayer.hasAudio else {
            return
        }
        viewModel.wasPaused = false
        viewModel.sasayakiPlayer.togglePlayback()
    }

    private func playPreviousSasayakiCue() {
        guard userConfig.enableSasayaki,
              viewModel.sasayakiPlayer.hasAudio else {
            return
        }
        viewModel.sasayakiPlayer.prevCue()
    }

    private func playNextSasayakiCue() {
        guard userConfig.enableSasayaki,
              viewModel.sasayakiPlayer.hasAudio else {
            return
        }
        viewModel.sasayakiPlayer.nextCue()
    }

    private func replaySasayakiCue() {
        guard userConfig.enableSasayaki,
              viewModel.sasayakiPlayer.hasAudio,
              let popup = currentSasayakiPopup() else {
            return
        }

        Task { @MainActor in
            await WordAudioPlayer.shared.stop()
            viewModel.sasayakiPlayer.playCue(from: popup.cue, stop: true)
        }
    }

    private func jumpToSasayakiCue() {
        guard userConfig.enableSasayaki,
              viewModel.sasayakiPlayer.hasAudio,
              let popup = currentSasayakiPopup() else {
            return
        }

        Task { @MainActor in
            await WordAudioPlayer.shared.stop()
            viewModel.sasayakiPlayer.playCue(from: popup.cue, stop: false)
            dismissPopup(at: popup.index)
        }
    }

    private func currentSasayakiPopup() -> (index: Int, cue: SasayakiMatch)? {
        guard let index = viewModel.popups.lastIndex(where: { $0.showPopup && $0.sasayakiCue != nil }),
              let cue = viewModel.popups[index].sasayakiCue else {
            return nil
        }
        return (index, cue)
    }

    private func dismissPopup(at index: Int) {
        guard viewModel.popups.indices.contains(index) else {
            return
        }
        if index == 0 {
            viewModel.clearSelection()
            viewModel.closePopups()
        } else if viewModel.popups.indices.contains(index - 1) {
            viewModel.popups[index - 1].clearSelection.toggle()
            viewModel.closeChildPopups(parent: index - 1)
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        if AppPlatform.usesDesktopLayout {
            VStack {
                Button("Previous Page") {
                    navigateBackward()
                }
                .keyboardShortcut(
                    userConfig.readerPreviousPageShortcut.keyEquivalent,
                    modifiers: userConfig.readerPreviousPageShortcut.eventModifiers
                )

                Button("Next Page") {
                    navigateForward()
                }
                .keyboardShortcut(
                    userConfig.readerNextPageShortcut.keyEquivalent,
                    modifiers: userConfig.readerNextPageShortcut.eventModifiers
                )

                Button("Previous Sasayaki Cue") {
                    playPreviousSasayakiCue()
                }
                .keyboardShortcut(
                    userConfig.sasayakiPreviousCueShortcut.keyEquivalent,
                    modifiers: userConfig.sasayakiPreviousCueShortcut.eventModifiers
                )

                Button("Toggle Sasayaki Playback") {
                    toggleSasayakiPlayback()
                }
                .keyboardShortcut(
                    userConfig.sasayakiPlayPauseShortcut.keyEquivalent,
                    modifiers: userConfig.sasayakiPlayPauseShortcut.eventModifiers
                )

                Button("Next Sasayaki Cue") {
                    playNextSasayakiCue()
                }
                .keyboardShortcut(
                    userConfig.sasayakiNextCueShortcut.keyEquivalent,
                    modifiers: userConfig.sasayakiNextCueShortcut.eventModifiers
                )

                Button("Replay Sasayaki Cue") {
                    replaySasayakiCue()
                }
                .keyboardShortcut(
                    userConfig.sasayakiReplayCueShortcut.keyEquivalent,
                    modifiers: userConfig.sasayakiReplayCueShortcut.eventModifiers
                )

                Button("Jump to Sasayaki Cue") {
                    jumpToSasayakiCue()
                }
                .keyboardShortcut(
                    userConfig.sasayakiJumpCueShortcut.keyEquivalent,
                    modifiers: userConfig.sasayakiJumpCueShortcut.eventModifiers
                )

                Button("Close Reader") {
                    dismissCurrentReader()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Close Reader Window") {
                    dismissCurrentReader()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Toggle Focus Mode") {
                    withAnimation(.default.speed(2)) {
                        focusMode.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [])
            }
            .labelsHidden()
            .frame(width: 0, height: 0)
            .opacity(0.001)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var readerInfoOverlay: some View {
        if AppPlatform.usesDesktopLayout {
            let showTitle = userConfig.readerShowTitle && viewModel.document.title != nil
            let showProgress = userConfig.readerShowProgressTop && !progressString.isEmpty

            if showTitle || showProgress {
                let contentWidth = readerInfoChromeContentWidth(
                    title: viewModel.document.title,
                    showTitle: showTitle,
                    showProgress: showProgress
                )
                VStack(alignment: .trailing, spacing: 3) {
                    if userConfig.readerShowTitle, let title = viewModel.document.title {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor.opacity(0.68)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: contentWidth, alignment: .trailing)
                    }
                    if showProgress {
                        Text(progressString)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor.opacity(0.86)) : AnyShapeStyle(.secondary))
                            .monospacedDigit()
                            .tracking(-0.4)
                            .frame(width: contentWidth, alignment: .trailing)
                    }
                }
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(readerBackgroundColor.opacity(0.88))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                .allowsHitTesting(false)
            }
        } else {
            VStack {
                if userConfig.readerShowTitle, let title = viewModel.document.title {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor.opacity(0.5)) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
                if userConfig.readerShowProgressTop && !progressString.isEmpty {
                    Text(progressString)
                        .font(.caption)
                        .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        .tracking(-0.4)
                    }
            }
        }
    }

    @ViewBuilder
    private var topChromeOverlay: some View {
        if !focusMode {
            ZStack(alignment: .top) {
                readerInfoOverlay
                    .frame(maxWidth: .infinity, alignment: AppPlatform.usesDesktopLayout ? .topTrailing : .top)

                if AppPlatform.usesDesktopLayout {
                    readerTabOverlay
                }
            }
            .padding(.top, topChromeInset)
            .padding(.horizontal, AppPlatform.usesDesktopLayout ? desktopInfoTrailing : 15)
        }
    }

    private var readerTabOverlay: some View {
        HStack(spacing: 0) {
            readerTabButton(title: "Books", tab: 0, isCurrent: false)
            Divider()
                .frame(height: 16)
                .padding(.vertical, 6)
            readerTabButton(title: "Dictionary", tab: 1, isCurrent: false)
            Divider()
                .frame(height: 16)
                .padding(.vertical, 6)
            readerTabButton(title: "Settings", tab: 2, isCurrent: false)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
        .background {
            Capsule()
                .fill(readerBackgroundColor.opacity(0.92))
        }
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func readerTabButton(title: LocalizedStringKey, tab: Int, isCurrent: Bool) -> some View {
        Button {
            openTabFromReader(tab)
        } label: {
            Text(title)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background {
                    if isCurrent {
                        Capsule()
                            .fill(.primary.opacity(0.10))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bottomInfoOverlay: some View {
        let showStats = userConfig.enableStatistics && !statisticsString.isEmpty && !focusMode
        let showProgress = !focusMode && !userConfig.readerShowProgressTop && !progressString.isEmpty
        if showStats || showProgress {
            VStack(spacing: 2) {
                if showStats {
                    Text(statisticsString)
                        .font(.caption)
                        .monospacedDigit()
                        .tracking(-0.4)
                }
                if showProgress {
                    Text(progressString)
                        .font(.caption)
                        .monospacedDigit()
                        .tracking(-0.4)
                }
            }
            .foregroundStyle(userConfig.theme == .custom ? AnyShapeStyle(userConfig.customInfoColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .conditionalGlassEffect()
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var bottomReaderControls: some View {
        HStack {
            CircleButton(systemName: "chevron.left")
                .onTapGesture {
                    dismissCurrentReader()
                }
                .opacity(focusMode ? 0 : 1)

            Spacer()

            bottomUtilityControls

            Menu {
                Button {
                    viewModel.activeSheet = .appearance
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }

                Button {
                    viewModel.activeSheet = .chapters
                } label: {
                    Label("Chapters", systemImage: "list.bullet")
                }

                Button {
                    viewModel.activeSheet = .highlights
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }

                if userConfig.enableStatistics {
                    Button {
                        viewModel.activeSheet = .statistics
                    } label: {
                        Label("Statistics", systemImage: "chart.xyaxis.line")
                    }
                }

                if userConfig.enableSasayaki && viewModel.sasayakiPlayer.hasMatch {
                    Button {
                        viewModel.activeSheet = .sasayaki
                    } label: {
                        Label("Sasayaki", systemImage: "waveform")
                    }
                }
            } label: {
                CircleButton(systemName: "slider.horizontal.3")
            }
            .tint(.primary)
            .opacity(focusMode ? 0 : 1)
        }
        .padding(.horizontal, AppPlatform.usesDesktopLayout ? 32 : 20)
        .frame(height: bottomControlOverlayHeight, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleReaderChrome()
        }
    }

    @ViewBuilder
    private var bottomUtilityControls: some View {
        HStack(spacing: 4) {
            if let character = viewModel.backTarget {
                Button {
                    viewModel.navigateBackwards()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text(character.formatted(.number.grouping(.never)))
                    }
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .conditionalGlassEffect()
                }
                .buttonStyle(.plain)
            }

            if userConfig.enableStatistics && userConfig.readerShowStatisticsToggle {
                Button {
                    toggleStatisticsTracking()
                } label: {
                    CircleButton(systemName: viewModel.isTracking ? "timer" : "chart.xyaxis.line", fontSize: 16)
                }
                .buttonStyle(.plain)
            }

            if userConfig.enableSasayaki && userConfig.readerShowSasayakiToggle && viewModel.sasayakiPlayer.hasAudio {
                Button {
                    toggleSasayakiPlayback()
                } label: {
                    CircleButton(systemName: viewModel.sasayakiPlayer.isPlaying || viewModel.wasPaused ? "pause.fill" : "waveform", fontSize: 16)
                }
                .buttonStyle(.plain)
            }

            if let character = viewModel.forwardTarget {
                Button {
                    viewModel.navigateForwards()
                } label: {
                    HStack(spacing: 3) {
                        Text(character.formatted(.number.grouping(.never)))
                        Image(systemName: "arrow.uturn.right.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .conditionalGlassEffect()
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(focusMode ? 0 : 1)
    }

    private var bottomChromeOverlay: some View {
        ZStack {
            bottomReaderControls
            bottomInfoOverlay
        }
        .frame(height: bottomControlOverlayHeight, alignment: .center)
        .padding(.bottom, bottomChromeInset)
        .allowsHitTesting(!focusMode)
    }

    var body: some View {
        // on ipad on first load, the geometry reader includes the safearea at the top
        // if you tab out and tab back in, the area recalculates causing the reader to be misaligned
        GeometryReader { geometry in
            ZStack {
                    let viewSize = CGSize(width: geometry.size.width.rounded(), height: geometry.size.height.rounded())
                    if userConfig.continuousMode {
                        ScrollReaderWebView(
                        userConfig: userConfig,
                        viewportWidth: Int(viewSize.width),
                        bridge: viewModel.bridge,
                        textColor: readerTextColor,
                        sasayakiTextColor: sasayakiTextColor,
                        sasayakiBackgroundColor: sasayakiBackgroundColor,
                        onNextChapter: viewModel.nextChapter,
                        onPreviousChapter: viewModel.previousChapter,
                        onSaveBookmark: viewModel.saveBookmark,
                        onInternalLink: viewModel.jumpToLink,
                        onInternalJump: viewModel.syncProgressAfterLinkJump,
                        onTextSelected: {
                            hideReaderChrome()
                            viewModel.closePopups()
                            return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                        },
                        onTapOutside: handleReaderTapOutside,
                        onScroll: {
                            hideReaderChrome()
                            viewModel.closePopups()
                            if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                viewModel.startTracking()
                            }
                        },
                        onProgressChanged: {
                            viewModel.updateProgress($0)
                            viewModel.clearForwardHistory()
                        },
                        onRestoreCompleted: {
                            viewModel.handleRestoreCompleted()
                        },
                        onHighlightCreated: viewModel.addHighlight,
                        onImageTapped: { imageURL = $0 }
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            justifyText: userConfig.justifyText,
                            blurImages: userConfig.blurImages,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            paragraphSpacing: userConfig.paragraphSpacing,
                            size: viewSize,
                        ))
                        .frame(width: viewSize.width, height: viewSize.height)
                        .clipped()
                    } else {
                        ReaderWebView(
                        userConfig: userConfig,
                        viewSize: viewSize,
                        bridge: viewModel.bridge,
                        textColor: readerTextColor,
                        sasayakiTextColor: sasayakiTextColor,
                        sasayakiBackgroundColor: sasayakiBackgroundColor,
                        onNextChapter: viewModel.nextChapter,
                        onPreviousChapter: viewModel.previousChapter,
                        onSaveBookmark: viewModel.saveBookmark,
                        onInternalLink: viewModel.jumpToLink,
                        onInternalJump: viewModel.syncProgressAfterLinkJump,
                        onTextSelected: {
                            hideReaderChrome()
                            viewModel.closePopups()
                            return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: userConfig.verticalWriting, isFullWidth: userConfig.popupFullWidth, autoPause: userConfig.sasayakiAutoPause)
                        },
                        onTapOutside: handleReaderTapOutside,
                        onPageTurn: {
                            hideReaderChrome()
                            viewModel.clearForwardHistory()
                            viewModel.closePopups()
                            if userConfig.statisticsAutostartMode == .pageturn && !viewModel.isTracking {
                                viewModel.startTracking()
                            }
                        },
                        onRestoreCompleted: {
                            viewModel.handleRestoreCompleted()
                        },
                        onHighlightCreated: viewModel.addHighlight,
                        onImageTapped: { imageURL = $0 }
                        )
                        .id(WebViewState(
                            verticalWriting: userConfig.verticalWriting,
                            fontSize: userConfig.fontSize,
                            selectedFont: userConfig.selectedFont,
                            hideFurigana: userConfig.readerHideFurigana,
                            horizontalPadding: userConfig.horizontalPadding,
                            verticalPadding: userConfig.verticalPadding,
                            avoidPageBreak: userConfig.avoidPageBreak,
                            justifyText: userConfig.justifyText,
                            blurImages: userConfig.blurImages,
                            layoutAdvanced: userConfig.layoutAdvanced,
                            lineHeight: userConfig.lineHeight,
                            characterSpacing: userConfig.characterSpacing,
                            paragraphSpacing: userConfig.paragraphSpacing,
                            size: viewSize,
                        ))
                        .frame(width: viewSize.width, height: viewSize.height)
                        .clipped()
                    }

                    ForEach($viewModel.popups) { $popup in
                        let popupId = popup.id
                        PopupView(
                        userConfig: userConfig,
                        isVisible: $popup.showPopup,
                        selectionData: popup.currentSelection,
                        lookupResults: popup.lookupResults,
                        dictionaryStyles: popup.dictionaryStyles,
                        screenSize: geometry.size,
                        isVertical: popup.isVertical,
                        isFullWidth: popup.isFullWidth,
                        coverURL: viewModel.coverURL,
                        documentTitle: viewModel.document.title,
                        clearSelection: popup.clearSelection,
                        onTextSelected: {
                            if let index = viewModel.popups.firstIndex(where: { $0.id == popupId }) {
                                viewModel.closeChildPopups(parent: index)
                            }
                            return viewModel.handleTextSelection($0, maxResults: userConfig.maxResults, scanLength: userConfig.scanLength, isVertical: false, isFullWidth: false, autoPause: userConfig.sasayakiAutoPause)
                        },
                        onTapOutside: {
                            if let index = viewModel.popups.firstIndex(where: { $0.id == popupId }) {
                                viewModel.closeChildPopups(parent: index)
                            }
                        },
                        onSwipeDismiss: {
                            guard let index = viewModel.popups.firstIndex(where: { $0.id == popupId }),
                                  viewModel.popups.indices.contains(index) else {
                                return
                            }
                            dismissPopup(at: index)
                        },
                        onPause: {
                            viewModel.wasPaused = false
                        },
                        sasayakiCue: popup.sasayakiCue,
                        sasayakiPlayer: viewModel.sasayakiPlayer,
                        wasPaused: viewModel.wasPaused
                        )
                        .zIndex(Double(100 + (viewModel.popups.firstIndex(where: { $0.id == popupId }) ?? 0)))
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.secondary)
                    }
            }
        }
        .background(readerBackgroundColor.ignoresSafeArea())
        .overlay(alignment: .top) {
            topChromeOverlay
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            bottomChromeOverlay
        }
        .overlay {
            if viewModel.isSyncing {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())

                    ProgressView()
                        .controlSize(.regular)
                        .tint(.secondary)
                }
            }
        }
        .overlay {
            if let url = imageURL {
                FullscreenImageView(url: url, backgroundColor: readerBackgroundColor) {
                    imageURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $viewModel.activeSheet) { item in
            switch item {
            case .appearance:
                AppearanceView(userConfig: userConfig, showDismiss: true)
                    .presentationDetents([.medium])
                    .preferredColorScheme(readerTheme)
            case .chapters:
                ChapterListView(displayTitle: viewModel.book.displayTitle, document: viewModel.document, bookInfo: viewModel.bookInfo, currentIndex: viewModel.index, currentCharacter: viewModel.currentCharacter, coverURL: viewModel.coverURL) { spineIndex, fragment in
                    viewModel.jumpToChapter(index: spineIndex, fragment: fragment)
                    viewModel.activeSheet = nil
                    viewModel.clearSelection()
                    viewModel.closePopups()
                } onJumpToCharacter: { count in
                    viewModel.jumpToCharacter(count)
                    viewModel.activeSheet = nil
                    viewModel.clearSelection()
                    viewModel.closePopups()
                }
            case .highlights:
                HighlightListView(
                    document: viewModel.document,
                    bookInfo: viewModel.bookInfo,
                    highlights: viewModel.highlights,
                    onJump: { highlight in
                        viewModel.jumpToCharacter(highlight.character)
                        viewModel.activeSheet = nil
                        viewModel.clearSelection()
                        viewModel.closePopups()
                    },
                    onDelete: { highlight in
                        viewModel.removeHighlight(highlight)
                    }
                )
                .presentationDetents([.medium, .large])
            case .statistics:
                StatisticsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            case .sasayaki:
                SasayakiSheet(player: viewModel.sasayakiPlayer, onImportAudio: { url in
                    try viewModel.importSasayakiAudio(from: url)
                }) {
                    viewModel.activeSheet = nil
                }
                .presentationDetents([.medium])
            }
        }
        .task(id: viewModel.isTracking) {
            guard viewModel.isTracking, !viewModel.isPaused else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !viewModel.isPaused {
                    viewModel.updateStats()
                }
            }
        }
        .task {
            await viewModel.syncOnOpen()
        }
        .onAppear {
            if AppPlatform.usesDesktopLayout {
                XboxControllerManager.shared.configure(userConfig: userConfig)
            }
        }
        .onChange(of: readerTextColor) { _, hex in viewModel.bridge.send(.updateTextColor(hex)) }
        .onChange(of: sasayakiTextColor) { _, _ in updateSasayakiColors() }
        .onChange(of: sasayakiBackgroundColor) { _, _ in updateSasayakiColors() }
        .onChange(of: userConfig.sasayakiAutoScroll) { _, _ in viewModel.sasayakiPlayer.updatePlaybackActivity() }
        .overlay {
            keyboardShortcuts
        }
        .background {
            if AppPlatform.usesDesktopLayout {
                NavigationPopGestureDisabler()
                    .frame(width: 0, height: 0)
                ReaderWindowChromeSync(
                    focusMode: focusMode,
                    backgroundColor: UIColor(readerBackgroundColor)
                )
                .frame(width: 0, height: 0)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                handleReaderBecameActive()
            case .inactive, .background:
                handleReaderResignedActive()
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: XboxControllerManager.actionNotification)) { notification in
            guard AppPlatform.usesDesktopLayout,
                  let rawAction = notification.userInfo?["action"] as? String,
                  let action = XboxControllerAction(rawValue: rawAction) else {
                return
            }

            switch action {
            case .previousPage:
                navigateBackward()
            case .nextPage:
                navigateForward()
            case .previousSasayakiCue:
                playPreviousSasayakiCue()
            case .playPauseSasayaki:
                toggleSasayakiPlayback()
            case .nextSasayakiCue:
                playNextSasayakiCue()
            case .replaySasayakiCue:
                replaySasayakiCue()
            case .jumpSasayakiCue:
                jumpToSasayakiCue()
            case .toggleStatistics:
                toggleStatisticsTracking()
            }
        }
        .onDisappear {
            viewModel.sasayakiPlayer.teardown()
            Task {
                await viewModel.flushAutoSync()
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarBackButtonHidden(AppPlatform.usesDesktopLayout)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBarHidden(focusMode)
        .persistentSystemOverlays(focusMode ? .hidden : .automatic)
        .preferredColorScheme(readerTheme)
    }
}

private struct CircleButton: View {
    let systemName: String
    let interactive: Bool
    let fontSize: CGFloat

    init(systemName: String, interactive: Bool = true, fontSize: CGFloat = 20) {
        self.systemName = systemName
        self.interactive = interactive
        self.fontSize = fontSize
    }

    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(interactive ? .regular.interactive() : .regular)
                .padding(8)
                .contentShape(Circle())
        } else {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .padding(8)
        }
    }
}

private struct NavigationPopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            context.coordinator.update(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(from: uiViewController)
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.restore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var navigationController: UINavigationController?
        private var previousEnabled: Bool?

        func update(from controller: UIViewController) {
            guard let navigationController = controller.navigationController,
                  navigationController !== self.navigationController else {
                return
            }

            restore()
            self.navigationController = navigationController
            previousEnabled = navigationController.interactivePopGestureRecognizer?.isEnabled
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }

        func restore() {
            if let previousEnabled {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = previousEnabled
            }
            navigationController = nil
            previousEnabled = nil
        }
    }
}

private struct ReaderWindowChromeSync: UIViewControllerRepresentable {
    var focusMode: Bool
    var backgroundColor: UIColor

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.update(from: controller, focusMode: focusMode, backgroundColor: backgroundColor)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(from: uiViewController, focusMode: focusMode, backgroundColor: backgroundColor)
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.restore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: UIWindow?
        private var originalTitleVisibility: UITitlebarTitleVisibility?
        private var originalToolbarStyle: UITitlebarToolbarStyle?
        private var originalSeparatorStyle: UITitlebarSeparatorStyle?
        private var originalToolbar: NSToolbar?
        private var originalAutoHidesToolbarInFullScreen: Bool?

        func update(from controller: UIViewController, focusMode: Bool, backgroundColor: UIColor) {
            guard let window = controller.view.window else {
                return
            }

            if self.window !== window {
                restore()
                self.window = window
                if let titlebar = window.windowScene?.titlebar {
                    originalTitleVisibility = titlebar.titleVisibility
                    originalToolbarStyle = titlebar.toolbarStyle
                    originalSeparatorStyle = titlebar.separatorStyle
                    originalToolbar = titlebar.toolbar
                    originalAutoHidesToolbarInFullScreen = titlebar.autoHidesToolbarInFullScreen
                }
            }

            window.backgroundColor = backgroundColor
            window.rootViewController?.view.backgroundColor = backgroundColor

            guard let titlebar = window.windowScene?.titlebar else {
                return
            }

            titlebar.separatorStyle = .none
            titlebar.autoHidesToolbarInFullScreen = true
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }

        func restore() {
            guard let window else {
                return
            }
            if let titlebar = window.windowScene?.titlebar {
                if let originalTitleVisibility {
                    titlebar.titleVisibility = originalTitleVisibility
                }
                if let originalToolbarStyle {
                    titlebar.toolbarStyle = originalToolbarStyle
                }
                if let originalSeparatorStyle {
                    titlebar.separatorStyle = originalSeparatorStyle
                }
                titlebar.toolbar = originalToolbar
                if let originalAutoHidesToolbarInFullScreen {
                    titlebar.autoHidesToolbarInFullScreen = originalAutoHidesToolbarInFullScreen
                }
            }
            self.window = nil
            originalTitleVisibility = nil
            originalToolbarStyle = nil
            originalSeparatorStyle = nil
            originalToolbar = nil
            originalAutoHidesToolbarInFullScreen = nil
        }
    }
}
