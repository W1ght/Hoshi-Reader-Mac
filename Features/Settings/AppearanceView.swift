//
//  AppearanceView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AppearanceView: View {
    let userConfig: UserConfig
    let showDismiss: Bool
    @Environment(\.dismiss) var dismiss
    @State private var isImportingFont = false
    @State private var importedFonts: [String] = []
    @State private var downloadingFont: String? = nil
    @State private var showingDeleteConfirmation = false
    @State private var fontToDelete: String? = nil

    var body: some View {
        @Bindable var userConfig = userConfig
        let fontSelection = Binding<String>(
            get: { userConfig.selectedFont },
            set: { newFont in
                guard downloadingFont == nil else { return }

                guard FontManager.downloadableFonts.contains(newFont),
                      !FontManager.shared.hasDownloadedFont(name: newFont) else {
                    userConfig.selectedFont = newFont
                    return
                }

                let previousFont = userConfig.selectedFont
                downloadingFont = newFont

                Task {
                    let success = await FontManager.downloadFont(newFont)
                    downloadingFont = nil
                    userConfig.selectedFont = success ? newFont : previousFont
                }
            }
        )
        Group {
        #if os(macOS) && !targetEnvironment(macCatalyst)
            nativeAppearanceContent(fontSelection: fontSelection)
        #else
            NavigationStack {
            List {
                Section("Theme") {
                    #if os(macOS) && !targetEnvironment(macCatalyst)
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.theme,
                        values: Themes.allCases,
                        minSegmentWidth: 62,
                        fillsWidth: true
                    ) { mode in
                        textForTheme(mode)
                    }
                    #else
                    Picker("Appearance", selection: $userConfig.theme) {
                        ForEach(Themes.allCases, id: \.self) { mode in
                            textForTheme(mode).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    #endif
                    if userConfig.theme == .system {
                        Toggle("Use Sepia as Light Theme", isOn: $userConfig.systemLightSepia)
                    }
                    if userConfig.theme == .sepia {
                        Toggle("Invert in System Dark Theme", isOn: $userConfig.sepiaInvertInDark)
                    }
                    if userConfig.theme == .custom {
                        Picker("Interface", selection: $userConfig.uiTheme) {
                            Text("System").tag(Themes.system)
                            Text("Light").tag(Themes.light)
                            Text("Dark").tag(Themes.dark)
                        }
                        ColorPicker("Background Color", selection: $userConfig.customBackgroundColor)
                        ColorPicker("Text Color", selection: $userConfig.customTextColor)
                        ColorPicker("Info Color", selection: $userConfig.customInfoColor)
                    }
                }

                Section("Text") {
                    HStack {
                        Text("Text Orientation")
                        Spacer()
                        #if os(macOS) && !targetEnvironment(macCatalyst)
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.verticalWriting,
                            values: [true, false],
                            minSegmentWidth: 74
                        ) { isVertical in
                            Text(isVertical ? "Vertical" : "Horizontal")
                        }
                        #else
                        Picker("", selection: $userConfig.verticalWriting) {
                            Text("Vertical").tag(true)
                            Text("Horizontal").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        #endif
                    }

                    HStack {
                        Picker("Font", selection: fontSelection) {
                            ForEach(FontManager.defaultFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(FontManager.downloadableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(importedFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .disabled(downloadingFont != nil)

                        if !FontManager.shared.isDefaultFont(name: userConfig.selectedFont) {
                            Button {
                                fontToDelete = userConfig.selectedFont
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("", isPresented: $showingDeleteConfirmation, titleVisibility: .hidden) {
                                Button("Delete", role: .destructive) {
                                    if let fontName = fontToDelete {
                                        try? FontManager.shared.deleteFont(name: fontName)
                                        userConfig.selectedFont = FontManager.defaultFonts[0]
                                        importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                                    }
                                }
                            } message: {
                                if let fontName = fontToDelete {
                                    Text("Delete \"\(fontName)\"?")
                                }
                            }
                        }

                        if downloadingFont != nil {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Button {
                        isImportingFont = true
                    } label: {
                        Text("Import Font")
                    }
                    .fileImporter(
                        isPresented: $isImportingFont,
                        allowedContentTypes: [.font],
                        onCompletion: { result in
                            if case .success(let url) = result {
                                FontManager.shared.importFont(from: url)
                                importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                            }
                        }
                    )

                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(userConfig.fontSize)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.fontSize, in: 16...40)
                            .labelsHidden()
                    }

                    Toggle("Hide Furigana", isOn: $userConfig.readerHideFurigana)
                }

                Section("Layout") {
                    HStack {
                        Text("Mode")
                        Spacer()
                        #if os(macOS) && !targetEnvironment(macCatalyst)
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.continuousMode,
                            values: [false, true],
                            minSegmentWidth: 78
                        ) { isContinuous in
                            Text(isContinuous ? "Continuous" : "Paginated")
                        }
                        #else
                        Picker("", selection: $userConfig.continuousMode) {
                            Text("Paginated").tag(false)
                            Text("Continuous").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        #endif
                    }

                    Toggle("Mouse Wheel Page Turn", isOn: $userConfig.readerWheelPageTurnEnabled)

                    if userConfig.continuousMode {
                        VStack {
                            HStack {
                                Text("Chapter Swipe Distance")
                                Spacer()
                                Text("\(userConfig.chapterSwipeDistance)")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: .init(
                                get: { Double(userConfig.chapterSwipeDistance) },
                                set: { userConfig.chapterSwipeDistance = Int($0) }
                            ), in: 10...60, step: 5)
                        }
                    }

                    HStack {
                        Text("Horizontal Padding")
                        Spacer()
                        Text("\(userConfig.horizontalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.horizontalPadding, in: 0...80, step: 1)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Vertical Padding")
                        Spacer()
                        Text("\(userConfig.verticalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.verticalPadding, in: 0...50, step: 1)
                            .labelsHidden()
                    }

                    Toggle("Avoid Page Break", isOn: $userConfig.avoidPageBreak)

                    Toggle("Justify Text", isOn: $userConfig.justifyText)

                    Toggle("Blur Images", isOn: $userConfig.blurImages)

                    Toggle("Advanced", isOn: $userConfig.layoutAdvanced)
                    if userConfig.layoutAdvanced {
                        VStack {
                            HStack {
                                Text("Line Height")
                                Spacer()
                                Text("\(userConfig.lineHeight, specifier: "%.2f")")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $userConfig.lineHeight, in: 1.0...2.5, step: 0.05)
                        }
                        VStack {
                            HStack {
                                Text("Character Spacing")
                                Spacer()
                                Text("\(Int(userConfig.characterSpacing))%")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $userConfig.characterSpacing, in: -10...10, step: 1)
                        }
                        VStack {
                            HStack {
                                Text("Paragraph Spacing")
                                Spacer()
                                Text("\(userConfig.paragraphSpacing, specifier: "%.1f")em")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: $userConfig.paragraphSpacing, in: 0...3, step: 0.1)
                        }
                    }
                }

                Section("Display") {
                    Toggle("Show Title", isOn: $userConfig.readerShowTitle)
                    Toggle("Show Character Count", isOn: $userConfig.readerShowCharacters)
                    Toggle("Show Percentage", isOn: $userConfig.readerShowPercentage)

                    if userConfig.readerShowCharacters || userConfig.readerShowPercentage {
                        HStack {
                            Text("Progress Position")
                            Spacer()
                            #if os(macOS) && !targetEnvironment(macCatalyst)
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.readerShowProgressTop,
                                values: [true, false],
                                minSegmentWidth: 54
                            ) { isTop in
                                Text(isTop ? "Top" : "Bottom")
                            }
                            #else
                            Picker("", selection: $userConfig.readerShowProgressTop) {
                                Text("Top").tag(true)
                                Text("Bottom").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            #endif
                        }
                    }

                    if userConfig.enableStatistics {
                        Toggle("Show Statistics Toggle", isOn: $userConfig.readerShowStatisticsToggle)
                        Toggle("Show Reading Speed", isOn: $userConfig.readerShowReadingSpeed)
                        Toggle("Show Reading Time", isOn: $userConfig.readerShowReadingTime)
                    }

                    if userConfig.enableSasayaki {
                        Toggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                    }
                }

                Section("Popup") {
                    VStack {
                        HStack {
                            Text("Width")
                            Spacer()
                            Text("\(userConfig.popupWidth)")
                                .fontWeight(.semibold)
                        }
                        Slider(value: .init(
                            get: { Double(userConfig.popupWidth) },
                            set: { userConfig.popupWidth = Int($0) }
                        ), in: 100...700, step: 10)

                        HStack {
                            Text("Height")
                            Spacer()
                            Text("\(userConfig.popupHeight)")
                                .fontWeight(.semibold)
                        }
                        Slider(value: .init(
                            get: { Double(userConfig.popupHeight) },
                            set: { userConfig.popupHeight = Int($0) }
                        ), in: 100...500, step: 10)

                        HStack {
                            Text("Scale")
                            Spacer()
                            Text("\(userConfig.popupScale, specifier: "%.2f")")
                                .fontWeight(.semibold)
                        }
                        Slider(value: Bindable(userConfig).popupScale, in: 0.8...1.5, step: 0.05)
                    }
                    Toggle("Show Action Bar", isOn: Bindable(userConfig).popupActionBar)
                    Toggle("Disable Transparency", isOn: Bindable(userConfig).popupDisableTransparency)
                    Toggle("Full-width", isOn: Bindable(userConfig).popupFullWidth)
                    Toggle("Swipe to Dismiss", isOn: Bindable(userConfig).popupSwipeToDismiss)
                    if userConfig.popupSwipeToDismiss {
                        VStack {
                            HStack {
                                Text("Swipe Threshold")
                                Spacer()
                                Text("\(userConfig.popupSwipeThreshold)")
                                    .fontWeight(.semibold)
                            }
                            Slider(value: .init(
                                get: { Double(userConfig.popupSwipeThreshold) },
                                set: { userConfig.popupSwipeThreshold = Int($0) }
                            ), in: 20...80, step: 5)
                        }
                    }
                }
            }
            }
            .navigationTitle("Appearance")
            .inlineNavigationTitleIfAvailable()
        #endif
        }
        .toolbar {
            if showDismiss {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .inlineNavigationTitleIfAvailable()
        .onAppear {
            importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
        }
    }

    #if os(macOS) && !targetEnvironment(macCatalyst)
    @ViewBuilder
    private func nativeAppearanceContent(fontSelection: Binding<String>) -> some View {
        @Bindable var userConfig = userConfig

        NativeSettingsForm {
            NativeSettingsSectionCard("Theme") {
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.theme,
                        values: Themes.allCases,
                        minSegmentWidth: 62,
                        fillsWidth: true
                    ) { mode in
                        textForTheme(mode)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if userConfig.theme == .system {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Use Sepia as Light Theme", isOn: $userConfig.systemLightSepia)
                    }
                    if userConfig.theme == .sepia {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Invert in System Dark Theme", isOn: $userConfig.sepiaInvertInDark)
                    }
                    if userConfig.theme == .custom {
                        NativeSettingsSeparator()
                        NativeSettingsRow("Interface") {
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.uiTheme,
                                values: [Themes.system, .light, .dark],
                                minSegmentWidth: 58
                            ) { mode in
                                textForTheme(mode)
                            }
                        }
                        NativeSettingsSeparator()
                        NativeSettingsRow("Background Color") {
                            ColorPicker("", selection: $userConfig.customBackgroundColor)
                                .labelsHidden()
                        }
                        NativeSettingsSeparator()
                        NativeSettingsRow("Text Color") {
                            ColorPicker("", selection: $userConfig.customTextColor)
                                .labelsHidden()
                        }
                        NativeSettingsSeparator()
                        NativeSettingsRow("Info Color") {
                            ColorPicker("", selection: $userConfig.customInfoColor)
                                .labelsHidden()
                        }
                    }
                }

            NativeSettingsSectionCard("Text") {
                    NativeSettingsRow("Text Orientation") {
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.verticalWriting,
                            values: [true, false],
                            minSegmentWidth: 74
                        ) { isVertical in
                            Text(isVertical ? "Vertical" : "Horizontal")
                        }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow("Font") {
                        Picker("", selection: fontSelection) {
                            ForEach(FontManager.defaultFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(FontManager.downloadableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                            ForEach(importedFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()
                        .disabled(downloadingFont != nil)

                        if !FontManager.shared.isDefaultFont(name: userConfig.selectedFont) {
                            Button {
                                fontToDelete = userConfig.selectedFont
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("", isPresented: $showingDeleteConfirmation, titleVisibility: .hidden) {
                                Button("Delete", role: .destructive) {
                                    if let fontName = fontToDelete {
                                        try? FontManager.shared.deleteFont(name: fontName)
                                        userConfig.selectedFont = FontManager.defaultFonts[0]
                                        importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                                    }
                                }
                            } message: {
                                if let fontName = fontToDelete {
                                    Text("Delete \"\(fontName)\"?")
                                }
                            }
                        }

                        if downloadingFont != nil {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        Button("Import Font") {
                            isImportingFont = true
                        }
                        .fileImporter(
                            isPresented: $isImportingFont,
                            allowedContentTypes: [.font],
                            onCompletion: { result in
                                if case .success(let url) = result {
                                    FontManager.shared.importFont(from: url)
                                    importedFonts = (try? FontManager.shared.storedFonts())?.map { $0.deletingPathExtension().lastPathComponent } ?? []
                                }
                            }
                        )
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow("Font Size") {
                        Text("\(userConfig.fontSize)")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.fontSize, in: 16...40)
                            .labelsHidden()
                    }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Hide Furigana", isOn: $userConfig.readerHideFurigana)
                }

            NativeSettingsSectionCard("Layout") {
                    NativeSettingsRow("Mode") {
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.continuousMode,
                            values: [false, true],
                            minSegmentWidth: 78
                        ) { isContinuous in
                            Text(isContinuous ? "Continuous" : "Paginated")
                        }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Mouse Wheel Page Turn", isOn: $userConfig.readerWheelPageTurnEnabled)

                    if userConfig.continuousMode {
                        NativeSettingsSeparator()
                        NativeSettingsSliderRow(
                            title: "Chapter Swipe Distance",
                            value: "\(userConfig.chapterSwipeDistance)"
                        ) {
                            Slider(value: .init(
                                get: { Double(userConfig.chapterSwipeDistance) },
                                set: { userConfig.chapterSwipeDistance = Int($0) }
                            ), in: 10...60, step: 5)
                        }
                    }

                    NativeSettingsSeparator()
                    NativeSettingsRow("Horizontal Padding") {
                        Text("\(userConfig.horizontalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.horizontalPadding, in: 0...80, step: 1)
                            .labelsHidden()
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow("Vertical Padding") {
                        Text("\(userConfig.verticalPadding)%")
                            .fontWeight(.semibold)
                        Stepper("", value: $userConfig.verticalPadding, in: 0...50, step: 1)
                            .labelsHidden()
                    }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Avoid Page Break", isOn: $userConfig.avoidPageBreak)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Justify Text", isOn: $userConfig.justifyText)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Blur Images", isOn: $userConfig.blurImages)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Advanced", isOn: $userConfig.layoutAdvanced)

                    if userConfig.layoutAdvanced {
                        NativeSettingsSeparator()
                        NativeSettingsSliderRow(
                            title: "Line Height",
                            value: String(format: "%.2f", userConfig.lineHeight)
                        ) {
                            Slider(value: $userConfig.lineHeight, in: 1.0...2.5, step: 0.05)
                        }
                        NativeSettingsSeparator()
                        NativeSettingsSliderRow(
                            title: "Character Spacing",
                            value: "\(Int(userConfig.characterSpacing))%"
                        ) {
                            Slider(value: $userConfig.characterSpacing, in: -10...10, step: 1)
                        }
                        NativeSettingsSeparator()
                        NativeSettingsSliderRow(
                            title: "Paragraph Spacing",
                            value: "\(String(format: "%.1f", userConfig.paragraphSpacing))em"
                        ) {
                            Slider(value: $userConfig.paragraphSpacing, in: 0...3, step: 0.1)
                        }
                    }
                }

            NativeSettingsSectionCard("Display") {
                    NativeSettingsToggle("Show Title", isOn: $userConfig.readerShowTitle)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Show Character Count", isOn: $userConfig.readerShowCharacters)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Show Percentage", isOn: $userConfig.readerShowPercentage)

                    if userConfig.readerShowCharacters || userConfig.readerShowPercentage {
                        NativeSettingsSeparator()
                        NativeSettingsRow("Progress Position") {
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.readerShowProgressTop,
                                values: [true, false],
                                minSegmentWidth: 54
                            ) { isTop in
                                Text(isTop ? "Top" : "Bottom")
                            }
                        }
                    }

                    if userConfig.enableStatistics {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Show Statistics Toggle", isOn: $userConfig.readerShowStatisticsToggle)
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Show Reading Speed", isOn: $userConfig.readerShowReadingSpeed)
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Show Reading Time", isOn: $userConfig.readerShowReadingTime)
                    }

                    if userConfig.enableSasayaki {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                    }
                }

            NativeSettingsSectionCard("Popup") {
                    NativeSettingsSliderRow(title: "Width", value: "\(userConfig.popupWidth)") {
                        Slider(value: .init(
                            get: { Double(userConfig.popupWidth) },
                            set: { userConfig.popupWidth = Int($0) }
                        ), in: 100...700, step: 10)
                    }
                    NativeSettingsSeparator()
                    NativeSettingsSliderRow(title: "Height", value: "\(userConfig.popupHeight)") {
                        Slider(value: .init(
                            get: { Double(userConfig.popupHeight) },
                            set: { userConfig.popupHeight = Int($0) }
                        ), in: 100...500, step: 10)
                    }
                    NativeSettingsSeparator()
                    NativeSettingsSliderRow(title: "Scale", value: String(format: "%.2f", userConfig.popupScale)) {
                        Slider(value: Bindable(userConfig).popupScale, in: 0.8...1.5, step: 0.05)
                    }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Show Action Bar", isOn: Bindable(userConfig).popupActionBar)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Disable Transparency", isOn: Bindable(userConfig).popupDisableTransparency)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Full-width", isOn: Bindable(userConfig).popupFullWidth)
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Swipe to Dismiss", isOn: Bindable(userConfig).popupSwipeToDismiss)

                    if userConfig.popupSwipeToDismiss {
                        NativeSettingsSeparator()
                        NativeSettingsSliderRow(title: "Swipe Threshold", value: "\(userConfig.popupSwipeThreshold)") {
                            Slider(value: .init(
                                get: { Double(userConfig.popupSwipeThreshold) },
                                set: { userConfig.popupSwipeThreshold = Int($0) }
                            ), in: 20...80, step: 5)
                        }
                    }
                }
            }
    }

    #endif

    private func textForTheme(_ theme: Themes) -> Text {
        switch theme {
        case .system:
            Text("System")
        case .light:
            Text("Light")
        case .dark:
            Text("Dark")
        case .sepia:
            Text("Sepia")
        case .custom:
            Text("Custom")
        }
    }
}
