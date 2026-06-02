//
//  UserConfig.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum DictionaryUpdateInterval: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var timeInterval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        }
    }
}

enum SyncMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case manual = "Manual"
}

enum AudioPlaybackMode: String, CaseIterable, Codable {
    case interrupt = "interrupt"
    case duck = "duck"
    case mix = "mix"
}

enum CollapseMode: String, CaseIterable, Codable {
    case expandAll = "Expand All"
    case collapseAll = "Collapse All"
    case custom = "Custom"
}

enum Themes: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"
    case custom = "Custom"

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .sepia: .light
        default: nil
        }
    }
}

struct ReaderKeyboardShortcut: Codable, Equatable, Identifiable {
    var key: String
    var modifiers: Int = 0

    var id: String { "\(modifiers)-\(key)" }

    var eventModifiers: EventModifiers {
        EventModifiers(rawValue: modifiers)
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "leftArrow": .leftArrow
        case "rightArrow": .rightArrow
        case "upArrow": .upArrow
        case "downArrow": .downArrow
        case "pageUp": .pageUp
        case "pageDown": .pageDown
        case "space": .space
        default:
            KeyEquivalent(Character(key.lowercased()))
        }
    }

    var label: String {
        let modifierLabels: [(EventModifiers, String)] = [
            (.command, "⌘"),
            (.shift, "⇧"),
            (.option, "⌥"),
            (.control, "⌃")
        ]
        let prefix = modifierLabels
            .filter { eventModifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return prefix + keyLabel
    }

    private var keyLabel: String {
        switch key {
        case "leftArrow": "←"
        case "rightArrow": "→"
        case "upArrow": "↑"
        case "downArrow": "↓"
        case "pageUp": "Page Up"
        case "pageDown": "Page Down"
        case "space": "Space"
        default: key.uppercased()
        }
    }

    static let leftArrow = ReaderKeyboardShortcut(key: "leftArrow")
    static let rightArrow = ReaderKeyboardShortcut(key: "rightArrow")
    static let bracketLeft = ReaderKeyboardShortcut(key: "[")
    static let bracketRight = ReaderKeyboardShortcut(key: "]")
    static let j = ReaderKeyboardShortcut(key: "j")
    static let p = ReaderKeyboardShortcut(key: "p")
    static let r = ReaderKeyboardShortcut(key: "r")
}

struct XboxControllerBinding: Codable, Equatable, Identifiable {
    var input: String

    var id: String { input }

    var label: String {
        switch input {
        case "buttonA": "A / Cross / B"
        case "buttonB": "B / Circle / A"
        case "buttonX": "X / Square / Y"
        case "buttonY": "Y / Triangle / X"
        case "dpadUp": "D-Pad ↑"
        case "dpadDown": "D-Pad ↓"
        case "dpadLeft": "D-Pad ←"
        case "dpadRight": "D-Pad →"
        case "leftShoulder": "LB / L1 / L"
        case "rightShoulder": "RB / R1 / R"
        case "leftTrigger": "LT / L2 / ZL"
        case "rightTrigger": "RT / R2 / ZR"
        case "leftThumbstickButton": "L3"
        case "rightThumbstickButton": "R3"
        case "buttonMenu": "Menu / Options / +"
        case "buttonOptions": "View / Share / -"
        case "buttonHome": "Home / PS"
        case "buttonShare": "Share / Create / Capture"
        case "playStationTouchpad": "Touchpad"
        case "xboxPaddle1": "Paddle 1"
        case "xboxPaddle2": "Paddle 2"
        case "xboxPaddle3": "Paddle 3"
        case "xboxPaddle4": "Paddle 4"
        case "leftThumbstickUp": "Left Stick ↑"
        case "leftThumbstickDown": "Left Stick ↓"
        case "leftThumbstickLeft": "Left Stick ←"
        case "leftThumbstickRight": "Left Stick →"
        case "rightThumbstickUp": "Right Stick ↑"
        case "rightThumbstickDown": "Right Stick ↓"
        case "rightThumbstickLeft": "Right Stick ←"
        case "rightThumbstickRight": "Right Stick →"
        default: input
        }
    }

    static let buttonA = XboxControllerBinding(input: "buttonA")
    static let buttonB = XboxControllerBinding(input: "buttonB")
    static let buttonX = XboxControllerBinding(input: "buttonX")
    static let buttonY = XboxControllerBinding(input: "buttonY")
    static let dpadLeft = XboxControllerBinding(input: "dpadLeft")
    static let dpadRight = XboxControllerBinding(input: "dpadRight")
    static let leftShoulder = XboxControllerBinding(input: "leftShoulder")
    static let rightShoulder = XboxControllerBinding(input: "rightShoulder")
}

@Observable
class UserConfig {
    var bookshelfSortOption: SortOption {
        didSet { UserDefaults.standard.set(bookshelfSortOption.rawValue, forKey: "bookshelfSortOption") }
    }

    var bookshelfShowReading: Bool {
        didSet { UserDefaults.standard.set(bookshelfShowReading, forKey: "bookshelfShowReading") }
    }

    var autoUpdateDictionaries: Bool {
        didSet { UserDefaults.standard.set(autoUpdateDictionaries, forKey: "autoUpdateDictionaries") }
    }

    var dictionaryUpdateInterval: DictionaryUpdateInterval {
        didSet { UserDefaults.standard.set(dictionaryUpdateInterval.rawValue, forKey: "dictionaryUpdateInterval") }
    }

    var dictionaryTabDefault: Bool {
        didSet { UserDefaults.standard.set(dictionaryTabDefault, forKey: "dictionaryTabDefault") }
    }

    var scanNonJapaneseText: Bool {
        didSet { UserDefaults.standard.set(scanNonJapaneseText, forKey: "scanNonJapaneseText") }
    }

    var maxResults: Int {
        didSet { UserDefaults.standard.set(maxResults, forKey: "maxResults") }
    }

    var scanLength: Int {
        didSet { UserDefaults.standard.set(scanLength, forKey: "scanLength") }
    }

    var collapseMode: CollapseMode {
        didSet { UserDefaults.standard.set(collapseMode.rawValue, forKey: "collapseMode") }
    }

    var expandFirstDictionary: Bool {
        didSet { UserDefaults.standard.set(expandFirstDictionary, forKey: "expandFirstDictionary") }
    }

    var compactGlossaries: Bool {
        didSet { UserDefaults.standard.set(compactGlossaries, forKey: "compactGlossaries") }
    }

    var showExpressionTags: Bool {
        didSet { UserDefaults.standard.set(showExpressionTags, forKey: "showExpressionTags") }
    }

    var harmonicFrequency: Bool {
        didSet { UserDefaults.standard.set(harmonicFrequency, forKey: "harmonicFrequency") }
    }

    var deduplicatePitchAccents: Bool {
        didSet { UserDefaults.standard.set(deduplicatePitchAccents, forKey: "deduplicatePitchAccents") }
    }

    var desktopLookupHoverDelayMs: Int {
        didSet { UserDefaults.standard.set(desktopLookupHoverDelayMs, forKey: "desktopLookupHoverDelayMs") }
    }

    var compactPitchAccents: Bool {
        didSet { UserDefaults.standard.set(compactPitchAccents, forKey: "compactPitchAccents") }
    }

    var enableSync: Bool {
        didSet { UserDefaults.standard.set(enableSync, forKey: "enableSync") }
    }

    var syncMode: SyncMode {
        didSet { UserDefaults.standard.set(syncMode.rawValue, forKey: "syncMode") }
    }

    var enableAutoSync: Bool {
        didSet { UserDefaults.standard.set(enableAutoSync, forKey: "enableAutoSync") }
    }

    var googleClientId: String {
        didSet { UserDefaults.standard.set(googleClientId, forKey: "googleClientId") }
    }

    var syncUploadBooks: Bool {
        didSet { UserDefaults.standard.set(syncUploadBooks, forKey: "syncUploadBooks") }
    }

    var theme: Themes {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    var uiTheme: Themes {
        didSet { UserDefaults.standard.set(uiTheme.rawValue, forKey: "uiTheme") }
    }

    var systemLightSepia: Bool {
        didSet { UserDefaults.standard.set(systemLightSepia, forKey: "systemLightSepia") }
    }

    var sepiaInvertInDark: Bool {
        didSet { UserDefaults.standard.set(sepiaInvertInDark, forKey: "sepiaInvertInDark") }
    }

    var customBackgroundColor: Color {
        didSet { Self.saveColor(customBackgroundColor, key: "customBackgroundColor") }
    }

    var customTextColor: Color {
        didSet { Self.saveColor(customTextColor, key: "customTextColor") }
    }

    var customInfoColor: Color {
        didSet { Self.saveColor(customInfoColor, key: "customInfoColor") }
    }

    var verticalWriting: Bool {
        didSet { UserDefaults.standard.set(verticalWriting, forKey: "verticalWriting") }
    }

    var selectedFont: String {
        didSet { UserDefaults.standard.set(selectedFont, forKey: "selectedFont") }
    }

    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    var readerHideFurigana: Bool {
        didSet { UserDefaults.standard.set(readerHideFurigana, forKey: "readerHideFurigana") }
    }

    var continuousMode: Bool {
        didSet { UserDefaults.standard.set(continuousMode, forKey: "continuousMode") }
    }

    var readerWheelPageTurnEnabled: Bool {
        didSet { UserDefaults.standard.set(readerWheelPageTurnEnabled, forKey: "readerWheelPageTurnEnabled") }
    }

    var chapterSwipeDistance: Int {
        didSet { UserDefaults.standard.set(chapterSwipeDistance, forKey: "chapterSwipeDistance") }
    }

    var horizontalPadding: Int {
        didSet { UserDefaults.standard.set(horizontalPadding, forKey: "layoutHorizontalPadding") }
    }

    var verticalPadding: Int {
        didSet { UserDefaults.standard.set(verticalPadding, forKey: "layoutVerticalPadding") }
    }

    var avoidPageBreak: Bool {
        didSet { UserDefaults.standard.set(avoidPageBreak, forKey: "avoidPageBreak") }
    }

    var justifyText: Bool {
        didSet { UserDefaults.standard.set(justifyText, forKey: "justifyText") }
    }

    var blurImages: Bool {
        didSet { UserDefaults.standard.set(blurImages, forKey: "blurImages") }
    }

    var layoutAdvanced: Bool {
        didSet { UserDefaults.standard.set(layoutAdvanced, forKey: "layoutAdvanced") }
    }

    var lineHeight: Double {
        didSet { UserDefaults.standard.set(lineHeight, forKey: "lineHeight") }
    }

    var characterSpacing: Double {
        didSet { UserDefaults.standard.set(characterSpacing, forKey: "characterSpacing") }
    }

    var paragraphSpacing: Double {
        didSet { UserDefaults.standard.set(paragraphSpacing, forKey: "paragraphSpacing") }
    }

    var readerShowTitle: Bool {
        didSet { UserDefaults.standard.set(readerShowTitle, forKey: "readerShowTitle") }
    }

    var readerShowCharacters: Bool {
        didSet { UserDefaults.standard.set(readerShowCharacters, forKey: "readerShowCharacters") }
    }

    var readerShowPercentage: Bool {
        didSet { UserDefaults.standard.set(readerShowPercentage, forKey: "readerShowPercentage") }
    }

    var readerShowProgressTop: Bool {
        didSet { UserDefaults.standard.set(readerShowProgressTop, forKey: "readerShowProgressTop") }
    }

    var readerShowStatisticsToggle: Bool {
        didSet { UserDefaults.standard.set(readerShowStatisticsToggle, forKey: "readerShowStatisticsToggle") }
    }

    var readerShowReadingSpeed: Bool {
        didSet { UserDefaults.standard.set(readerShowReadingSpeed, forKey: "readerShowReadingSpeed") }
    }

    var readerShowReadingTime: Bool {
        didSet { UserDefaults.standard.set(readerShowReadingTime, forKey: "readerShowReadingTime") }
    }

    var readerShowSasayakiToggle: Bool {
        didSet { UserDefaults.standard.set(readerShowSasayakiToggle, forKey: "readerShowSasayakiToggle") }
    }

    var readerPreviousPageShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(readerPreviousPageShortcut, key: "readerPreviousPageShortcut") }
    }

    var readerNextPageShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(readerNextPageShortcut, key: "readerNextPageShortcut") }
    }

    var sasayakiPreviousCueShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(sasayakiPreviousCueShortcut, key: "sasayakiPreviousCueShortcut") }
    }

    var sasayakiPlayPauseShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(sasayakiPlayPauseShortcut, key: "sasayakiPlayPauseShortcut") }
    }

    var sasayakiNextCueShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(sasayakiNextCueShortcut, key: "sasayakiNextCueShortcut") }
    }

    var sasayakiReplayCueShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(sasayakiReplayCueShortcut, key: "sasayakiReplayCueShortcut") }
    }

    var sasayakiJumpCueShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(sasayakiJumpCueShortcut, key: "sasayakiJumpCueShortcut") }
    }

    var dictionaryPreviousEntryShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(dictionaryPreviousEntryShortcut, key: "dictionaryPreviousEntryShortcut") }
    }

    var dictionaryNextEntryShortcut: ReaderKeyboardShortcut {
        didSet { Self.saveShortcut(dictionaryNextEntryShortcut, key: "dictionaryNextEntryShortcut") }
    }

    var dictionaryEntryJumpCount: Int {
        didSet { UserDefaults.standard.set(dictionaryEntryJumpCount, forKey: "dictionaryEntryJumpCount") }
    }

    var readerPreviousPageControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(readerPreviousPageControllerBinding, key: "readerPreviousPageControllerBinding") }
    }

    var readerNextPageControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(readerNextPageControllerBinding, key: "readerNextPageControllerBinding") }
    }

    var sasayakiPreviousCueControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(sasayakiPreviousCueControllerBinding, key: "sasayakiPreviousCueControllerBinding") }
    }

    var sasayakiPlayPauseControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(sasayakiPlayPauseControllerBinding, key: "sasayakiPlayPauseControllerBinding") }
    }

    var sasayakiNextCueControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(sasayakiNextCueControllerBinding, key: "sasayakiNextCueControllerBinding") }
    }

    var sasayakiReplayCueControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(sasayakiReplayCueControllerBinding, key: "sasayakiReplayCueControllerBinding") }
    }

    var sasayakiJumpCueControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(sasayakiJumpCueControllerBinding, key: "sasayakiJumpCueControllerBinding") }
    }

    var statisticsToggleControllerBinding: XboxControllerBinding {
        didSet { Self.saveControllerBinding(statisticsToggleControllerBinding, key: "statisticsToggleControllerBinding") }
    }

    var popupWidth: Int {
        didSet { UserDefaults.standard.set(popupWidth, forKey: "popupWidth") }
    }

    var popupHeight: Int {
        didSet { UserDefaults.standard.set(popupHeight, forKey: "popupHeight") }
    }
    var popupScale: Double {
        didSet { UserDefaults.standard.set(popupScale, forKey: "popupScale") }
    }

    var popupActionBar: Bool {
        didSet { UserDefaults.standard.set(popupActionBar, forKey: "popupActionBar") }
    }

    var popupDisableTransparency: Bool {
        didSet { UserDefaults.standard.set(popupDisableTransparency, forKey: "popupDisableTransparency") }
    }

    var popupFullWidth: Bool {
        didSet { UserDefaults.standard.set(popupFullWidth, forKey: "popupFullWidth") }
    }

    var popupSwipeToDismiss: Bool {
        didSet { UserDefaults.standard.set(popupSwipeToDismiss, forKey: "popupSwipeToDismiss") }
    }

    var popupSwipeThreshold: Int {
        didSet { UserDefaults.standard.set(popupSwipeThreshold, forKey: "popupSwipeThreshold") }
    }

    var audioSources: [AudioSource] {
        didSet {
            if let data = try? JSONEncoder().encode(audioSources) {
                UserDefaults.standard.set(data, forKey: "audioSources")
            }
        }
    }

    var enableLocalAudio: Bool {
        didSet {
            UserDefaults.standard.set(enableLocalAudio, forKey: "enableLocalAudio")
            syncLocalAudioSource()
        }
    }

    var audioEnableAutoplay: Bool {
        didSet { UserDefaults.standard.set(audioEnableAutoplay, forKey: "audioEnableAutoplay") }
    }

    var audioPlaybackMode: AudioPlaybackMode {
        didSet { UserDefaults.standard.set(audioPlaybackMode.rawValue, forKey: "audioPlaybackMode") }
    }

    var enabledAudioSources: [String] {
        audioSources.filter { $0.isEnabled }.map { $0.url }
    }

    static let localAudioSource = AudioSource(
        name: "Local",
        url: LocalAudioEndpoint.url,
        isEnabled: true
    )

    private static let legacyLocalAudioURLs = [
        "http://localhost:8765/localaudio/get/?term={term}&reading={reading}"
    ]

    static let defaultAudioSource = AudioSource(
        name: "Default",
        url: "https://hoshi-reader.manhhaoo-do.workers.dev/?term={term}&reading={reading}",
        isEnabled: true,
        isDefault: true
    )

    var customCSS: String {
        didSet { UserDefaults.standard.set(customCSS, forKey: "customCSS") }
    }

    var enableStatistics: Bool {
        didSet { UserDefaults.standard.set(enableStatistics, forKey: "enableStatistics") }
    }

    var statisticsEnableSync: Bool {
        didSet { UserDefaults.standard.set(statisticsEnableSync, forKey: "statisticsEnableSync") }
    }

    var statisticsSyncMode: StatisticsSyncMode {
        didSet { UserDefaults.standard.set(statisticsSyncMode.rawValue, forKey: "statisticsSyncMode") }
    }

    var statisticsAutostartMode: StatisticsAutostartMode {
        didSet { UserDefaults.standard.set(statisticsAutostartMode.rawValue, forKey: "statisticsAutostartMode") }
    }

    var enableSasayaki: Bool {
        didSet { UserDefaults.standard.set(enableSasayaki, forKey: "enableSasayaki") }
    }

    var sasayakiAutoScroll: Bool {
        didSet { UserDefaults.standard.set(sasayakiAutoScroll, forKey: "sasayakiAutoScroll") }
    }

    var sasayakiAutoPause: Bool {
        didSet { UserDefaults.standard.set(sasayakiAutoPause, forKey: "sasayakiAutoPause") }
    }

    var sasayakiSkipControls: Bool {
        didSet { UserDefaults.standard.set(sasayakiSkipControls, forKey: "sasayakiSkipControls") }
    }

    var sasayakiEnableSync: Bool {
        didSet { UserDefaults.standard.set(sasayakiEnableSync, forKey: "sasayakiEnableSync") }
    }

    var sasayakiTextColor: Color {
        didSet { Self.saveColor(sasayakiTextColor, key: "sasayakiTextColor") }
    }

    var sasayakiBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiBackgroundColor, key: "sasayakiBackgroundColor") }
    }

    var sasayakiDarkTextColor: Color {
        didSet { Self.saveColor(sasayakiDarkTextColor, key: "sasayakiDarkTextColor") }
    }

    var sasayakiDarkBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiDarkBackgroundColor, key: "sasayakiDarkBackgroundColor") }
    }

    init() {
        let defaults = UserDefaults.standard

        self.bookshelfSortOption = defaults.string(forKey: "bookshelfSortOption")
            .flatMap(SortOption.init) ?? .recent
        self.bookshelfShowReading = defaults.object(forKey: "bookshelfShowReading") as? Bool ?? false

        self.autoUpdateDictionaries = defaults.object(forKey: "autoUpdateDictionaries") as? Bool ?? true
        self.dictionaryUpdateInterval = defaults.string(forKey: "dictionaryUpdateInterval")
            .flatMap(DictionaryUpdateInterval.init) ?? .weekly
        self.dictionaryTabDefault = defaults.object(forKey: "dictionaryTabDefault") as? Bool ?? false
        self.scanNonJapaneseText = defaults.object(forKey: "scanNonJapaneseText") as? Bool ?? true
        self.maxResults = defaults.object(forKey: "maxResults") as? Int ?? 16
        self.scanLength = defaults.object(forKey: "scanLength") as? Int ?? 16
        let legacyCollapseDictionaries = defaults.object(forKey: "collapseDictionaries") as? Bool ?? false
        self.collapseMode = defaults.string(forKey: "collapseMode")
            .flatMap(CollapseMode.init) ?? (legacyCollapseDictionaries ? .collapseAll : .expandAll)
        self.expandFirstDictionary = defaults.object(forKey: "expandFirstDictionary") as? Bool ?? false
        self.compactGlossaries = defaults.object(forKey: "compactGlossaries") as? Bool ?? true
        self.showExpressionTags = defaults.object(forKey: "showExpressionTags") as? Bool ?? false
        self.harmonicFrequency = defaults.object(forKey: "harmonicFrequency") as? Bool ?? false
        self.deduplicatePitchAccents = defaults.object(forKey: "deduplicatePitchAccents") as? Bool ?? false
        self.desktopLookupHoverDelayMs = defaults.object(forKey: "desktopLookupHoverDelayMs") as? Int ?? 45
        self.compactPitchAccents = defaults.object(forKey: "compactPitchAccents") as? Bool ?? true

        self.enableSync = defaults.object(forKey: "enableSync") as? Bool ?? false
        self.syncMode = defaults.string(forKey: "syncMode")
            .flatMap(SyncMode.init) ?? .auto
        self.enableAutoSync = defaults.object(forKey: "enableAutoSync") as? Bool ?? false
        self.googleClientId = defaults.object(forKey: "googleClientId") as? String ?? ""
        self.syncUploadBooks = defaults.object(forKey: "syncUploadBooks") as? Bool ?? true

        self.theme = defaults.string(forKey: "theme")
            .flatMap(Themes.init) ?? .system
        self.uiTheme = defaults.string(forKey: "uiTheme")
            .flatMap(Themes.init) ?? .system
        self.systemLightSepia = defaults.object(forKey: "systemLightSepia") as? Bool ?? false
        self.sepiaInvertInDark = defaults.object(forKey: "sepiaInvertInDark") as? Bool ?? false
        self.customBackgroundColor = UserConfig.loadColor(key: "customBackgroundColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.customTextColor = UserConfig.loadColor(key: "customTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.customInfoColor = UserConfig.loadColor(key: "customInfoColor") ?? Color(.sRGB, red: 0.6, green: 0.6, blue: 0.6)

        self.verticalWriting = defaults.object(forKey: "verticalWriting") as? Bool ?? true
        self.selectedFont = defaults.string(forKey: "selectedFont") ?? "Hiragino Mincho ProN"
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.readerHideFurigana = defaults.object(forKey: "readerHideFurigana") as? Bool ?? false

        self.continuousMode = defaults.object(forKey: "continuousMode") as? Bool ?? false
        self.readerWheelPageTurnEnabled = defaults.object(forKey: "readerWheelPageTurnEnabled") as? Bool ?? true
        self.chapterSwipeDistance = defaults.object(forKey: "chapterSwipeDistance") as? Int ?? 20
        self.horizontalPadding = defaults.object(forKey: "layoutHorizontalPadding") as? Int ?? 5
        self.verticalPadding = defaults.object(forKey: "layoutVerticalPadding") as? Int ?? 0
        self.avoidPageBreak = defaults.object(forKey: "avoidPageBreak") as? Bool ?? false
        self.justifyText = defaults.object(forKey: "justifyText") as? Bool ?? false
        self.blurImages = defaults.object(forKey: "blurImages") as? Bool ?? false
        self.layoutAdvanced = defaults.object(forKey: "layoutAdvanced") as? Bool ?? false
        self.lineHeight = defaults.object(forKey: "lineHeight") as? Double ?? 1.65
        self.characterSpacing = defaults.object(forKey: "characterSpacing") as? Double ?? 0
        self.paragraphSpacing = defaults.object(forKey: "paragraphSpacing") as? Double ?? 0

        self.readerShowTitle = defaults.object(forKey: "readerShowTitle") as? Bool ?? true
        self.readerShowCharacters = defaults.object(forKey: "readerShowCharacters") as? Bool ?? true
        self.readerShowPercentage = defaults.object(forKey: "readerShowPercentage") as? Bool ?? true
        self.readerShowProgressTop = defaults.object(forKey: "readerShowProgressTop") as? Bool ?? true
        self.readerShowStatisticsToggle = defaults.object(forKey: "readerShowStatisticsToggle") as? Bool ?? false
        self.readerShowReadingSpeed = defaults.object(forKey: "readerShowReadingSpeed") as? Bool ?? false
        self.readerShowReadingTime = defaults.object(forKey: "readerShowReadingTime") as? Bool ?? false
        self.readerShowSasayakiToggle = defaults.object(forKey: "readerShowSasayakiToggle") as? Bool ?? false
        self.readerPreviousPageShortcut = Self.loadShortcut(key: "readerPreviousPageShortcut") ?? .leftArrow
        self.readerNextPageShortcut = Self.loadShortcut(key: "readerNextPageShortcut") ?? .rightArrow
        self.sasayakiPreviousCueShortcut = Self.loadShortcut(key: "sasayakiPreviousCueShortcut") ?? .bracketLeft
        self.sasayakiPlayPauseShortcut = Self.loadShortcut(key: "sasayakiPlayPauseShortcut") ?? .p
        self.sasayakiNextCueShortcut = Self.loadShortcut(key: "sasayakiNextCueShortcut") ?? .bracketRight
        self.sasayakiReplayCueShortcut = Self.loadShortcut(key: "sasayakiReplayCueShortcut") ?? .r
        self.sasayakiJumpCueShortcut = Self.loadShortcut(key: "sasayakiJumpCueShortcut") ?? .j
        self.dictionaryPreviousEntryShortcut = Self.loadShortcut(key: "dictionaryPreviousEntryShortcut")
            ?? ReaderKeyboardShortcut(key: "pageUp", modifiers: EventModifiers.option.rawValue)
        self.dictionaryNextEntryShortcut = Self.loadShortcut(key: "dictionaryNextEntryShortcut")
            ?? ReaderKeyboardShortcut(key: "pageDown", modifiers: EventModifiers.option.rawValue)
        self.dictionaryEntryJumpCount = min(max(defaults.object(forKey: "dictionaryEntryJumpCount") as? Int ?? 1, 1), 10)
        self.readerPreviousPageControllerBinding = Self.loadControllerBinding(key: "readerPreviousPageControllerBinding") ?? .dpadLeft
        self.readerNextPageControllerBinding = Self.loadControllerBinding(key: "readerNextPageControllerBinding") ?? .dpadRight
        self.sasayakiPreviousCueControllerBinding = Self.loadControllerBinding(key: "sasayakiPreviousCueControllerBinding") ?? .leftShoulder
        self.sasayakiPlayPauseControllerBinding = Self.loadControllerBinding(key: "sasayakiPlayPauseControllerBinding") ?? .buttonA
        self.sasayakiNextCueControllerBinding = Self.loadControllerBinding(key: "sasayakiNextCueControllerBinding") ?? .rightShoulder
        self.sasayakiReplayCueControllerBinding = Self.loadControllerBinding(key: "sasayakiReplayCueControllerBinding") ?? .buttonX
        self.sasayakiJumpCueControllerBinding = Self.loadControllerBinding(key: "sasayakiJumpCueControllerBinding") ?? .buttonB
        self.statisticsToggleControllerBinding = Self.loadControllerBinding(key: "statisticsToggleControllerBinding") ?? .buttonY

        self.popupWidth = defaults.object(forKey: "popupWidth") as? Int ?? 320
        self.popupHeight = defaults.object(forKey: "popupHeight") as? Int ?? 250
        self.popupScale = defaults.object(forKey: "popupScale") as? Double ?? 1.0
        self.popupActionBar = defaults.object(forKey: "popupActionBar") as? Bool ?? false
        self.popupDisableTransparency = defaults.object(forKey: "popupDisableTransparency") as? Bool ?? false
        self.popupFullWidth = defaults.object(forKey: "popupFullWidth") as? Bool ?? false
        self.popupSwipeToDismiss = defaults.object(forKey: "popupSwipeToDismiss") as? Bool ?? false
        self.popupSwipeThreshold = defaults.object(forKey: "popupSwipeThreshold") as? Int ?? 40

        if let data = defaults.data(forKey: "audioSources"),
           let sources = try? JSONDecoder().decode([AudioSource].self, from: data) {
            self.audioSources = sources
        } else {
            self.audioSources = [UserConfig.defaultAudioSource]
        }
        self.enableLocalAudio = defaults.object(forKey: "enableLocalAudio") as? Bool ?? false
        self.audioEnableAutoplay = defaults.object(forKey: "audioEnableAutoplay") as? Bool ?? false
        self.audioPlaybackMode = defaults.string(forKey: "audioPlaybackMode")
            .flatMap(AudioPlaybackMode.init) ?? .interrupt
        self.customCSS = defaults.string(forKey: "customCSS") ?? ""

        self.enableStatistics = defaults.object(forKey: "enableStatistics") as? Bool ?? false
        self.statisticsEnableSync = defaults.object(forKey: "statisticsEnableSync") as? Bool ?? false
        self.statisticsSyncMode = defaults.string(forKey: "statisticsSyncMode")
            .flatMap(StatisticsSyncMode.init) ?? .merge
        self.statisticsAutostartMode = defaults.string(forKey: "statisticsAutostartMode")
            .flatMap(StatisticsAutostartMode.init) ?? .off

        self.enableSasayaki = defaults.object(forKey: "enableSasayaki") as? Bool ?? false
        self.sasayakiAutoScroll = defaults.object(forKey: "sasayakiAutoScroll") as? Bool ?? true
        self.sasayakiAutoPause = defaults.object(forKey: "sasayakiAutoPause") as? Bool ?? true
        self.sasayakiSkipControls = defaults.object(forKey: "sasayakiSkipControls") as? Bool ?? false
        self.sasayakiEnableSync = defaults.object(forKey: "sasayakiEnableSync") as? Bool ?? false
        self.sasayakiTextColor = UserConfig.loadColor(key: "sasayakiTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.sasayakiBackgroundColor = UserConfig.loadColor(key: "sasayakiBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
        self.sasayakiDarkTextColor = UserConfig.loadColor(key: "sasayakiDarkTextColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.sasayakiDarkBackgroundColor = UserConfig.loadColor(key: "sasayakiDarkBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
        syncLocalAudioSource()
    }

    private func syncLocalAudioSource() {
        audioSources.removeAll {
            $0.url == LocalAudioEndpoint.url || Self.legacyLocalAudioURLs.contains($0.url)
        }
        if enableLocalAudio {
            audioSources.insert(UserConfig.localAudioSource, at: 0)
        }
    }

    private static func saveColor(_ color: Color, key: String) {
        let resolved = color.resolve(in: EnvironmentValues())
        UserDefaults.standard.set(
            ColorHexCodec.hexString(
                red: CGFloat(resolved.red),
                green: CGFloat(resolved.green),
                blue: CGFloat(resolved.blue),
                alpha: CGFloat(resolved.opacity)
            ),
            forKey: key
        )
    }

    private static func loadColor(key: String) -> Color? {
        let defaults = UserDefaults.standard
        if let hexString = defaults.string(forKey: key) {
            return ColorHexCodec.components(hexString: hexString).map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
            }
        }

        guard let colorData = defaults.data(forKey: key) else { return nil }
#if canImport(UIKit)
        if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            let color = Color(uiColor)
            saveColor(color, key: key)
            return color
        }
#endif
        return nil
    }

    private static func saveShortcut(_ shortcut: ReaderKeyboardShortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadShortcut(key: String) -> ReaderKeyboardShortcut? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let shortcut = try? JSONDecoder().decode(ReaderKeyboardShortcut.self, from: data) {
            return shortcut
        }

        // Migrate the earlier preset-only storage format.
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }
        switch rawValue {
        case "leftArrow": return .leftArrow
        case "rightArrow": return .rightArrow
        case "bracketLeft": return .bracketLeft
        case "bracketRight": return .bracketRight
        case "p": return .p
        default: return nil
        }
    }

    private static func saveControllerBinding(_ binding: XboxControllerBinding, key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadControllerBinding(key: String) -> XboxControllerBinding? {
        if let data = UserDefaults.standard.data(forKey: key),
           let binding = try? JSONDecoder().decode(XboxControllerBinding.self, from: data) {
            return binding
        }
        return nil
    }
}
