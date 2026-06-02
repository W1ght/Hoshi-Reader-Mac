import SwiftUI

struct NativeSettingsHomeView: View {
    @State private var selection: NativeSettingsCategory? = .appearance

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            List(selection: $selection) {
                ForEach(NativeSettingsCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage)
                        .tag(category)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 210)
            .frame(minHeight: 620)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 16) {
                Label(selected.title, systemImage: selected.systemImage)
                    .font(.title2.bold())

                selectedView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 720, minHeight: 620, alignment: .topLeading)
        }
    }

    private var selected: NativeSettingsCategory {
        selection ?? .appearance
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selected {
        case .appearance:
            NativeAppearanceSettingsPane()
        case .dictionary:
            NativeDictionarySettingsPane()
        case .anki:
            NativeAnkiSettingsPane()
        case .audio:
            NativeAudioSettingsPane()
        case .sasayaki:
            NativeSasayakiSettingsPane()
        case .statistics:
            StatisticsSettingsView()
                .padding(.top, -12)
        case .shortcuts:
            NativeShortcutSettingsPane()
        case .sync:
            NativeSyncSettingsPane()
        }
    }
}

private enum NativeSettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case dictionary
    case anki
    case audio
    case sasayaki
    case statistics
    case shortcuts
    case sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .dictionary: "词典"
        case .anki: "Anki"
        case .audio: "音频"
        case .sasayaki: "Sasayaki"
        case .statistics: "统计"
        case .shortcuts: "快捷键"
        case .sync: "同步"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette"
        case .dictionary: "character.book.closed"
        case .anki: "rectangle.stack.badge.plus"
        case .audio: "speaker.wave.2"
        case .sasayaki: "waveform"
        case .statistics: "chart.xyaxis.line"
        case .shortcuts: "keyboard"
        case .sync: "cloud"
        }
    }
}

private struct NativeAppearanceSettingsPane: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSection("主题") {
                Picker("外观", selection: $userConfig.theme) {
                    Text("System").tag(Themes.system)
                    Text("Light").tag(Themes.light)
                    Text("Dark").tag(Themes.dark)
                    Text("Sepia").tag(Themes.sepia)
                    Text("Custom").tag(Themes.custom)
                }
                .pickerStyle(.segmented)

                if userConfig.theme == .system {
                    Toggle("Use Sepia as Light Theme", isOn: $userConfig.systemLightSepia)
                }
                if userConfig.theme == .sepia {
                    Toggle("Invert in System Dark Theme", isOn: $userConfig.sepiaInvertInDark)
                }
                if userConfig.theme == .custom {
                    ColorPicker("Background Color", selection: $userConfig.customBackgroundColor)
                    ColorPicker("Text Color", selection: $userConfig.customTextColor)
                    ColorPicker("Info Color", selection: $userConfig.customInfoColor)
                }
            }

            NativeSettingsSection("文本") {
                NativeSegmentedBoolRow(
                    title: "Text Orientation",
                    falseTitle: "Horizontal",
                    trueTitle: "Vertical",
                    value: $userConfig.verticalWriting
                )
                NativeStepperRow(title: "Font Size", value: $userConfig.fontSize, range: 16...40)
                Toggle("Hide Furigana", isOn: $userConfig.readerHideFurigana)
            }

            NativeSettingsSection("布局") {
                NativeSegmentedBoolRow(
                    title: "Mode",
                    falseTitle: "Paginated",
                    trueTitle: "Continuous",
                    value: $userConfig.continuousMode
                )
                Toggle("Mouse Wheel Page Turn", isOn: $userConfig.readerWheelPageTurnEnabled)
                NativeStepperRow(title: "Horizontal Padding", value: $userConfig.horizontalPadding, range: 0...80, suffix: "%")
                NativeStepperRow(title: "Vertical Padding", value: $userConfig.verticalPadding, range: 0...50, suffix: "%")
                Toggle("Avoid Page Break", isOn: $userConfig.avoidPageBreak)
                Toggle("Justify Text", isOn: $userConfig.justifyText)
                Toggle("Blur Images", isOn: $userConfig.blurImages)
            }

            NativeSettingsSection("显示") {
                Toggle("Show Title", isOn: $userConfig.readerShowTitle)
                Toggle("Show Character Count", isOn: $userConfig.readerShowCharacters)
                Toggle("Show Percentage", isOn: $userConfig.readerShowPercentage)
                if userConfig.readerShowCharacters || userConfig.readerShowPercentage {
                    NativeSegmentedBoolRow(
                        title: "Progress Position",
                        falseTitle: "Bottom",
                        trueTitle: "Top",
                        value: $userConfig.readerShowProgressTop
                    )
                }
                Toggle("Show Statistics Toggle", isOn: $userConfig.readerShowStatisticsToggle)
                Toggle("Show Reading Speed", isOn: $userConfig.readerShowReadingSpeed)
                Toggle("Show Reading Time", isOn: $userConfig.readerShowReadingTime)
            }

            NativeSettingsSection("弹窗") {
                NativeStepperRow(title: "Width", value: $userConfig.popupWidth, range: 100...700)
                NativeStepperRow(title: "Height", value: $userConfig.popupHeight, range: 100...500)
                NativeDoubleSliderRow(title: "Scale", value: $userConfig.popupScale, range: 0.8...1.5, step: 0.05)
                Toggle("Show Action Bar", isOn: $userConfig.popupActionBar)
                Toggle("Disable Transparency", isOn: $userConfig.popupDisableTransparency)
                Toggle("Full-width", isOn: $userConfig.popupFullWidth)
            }
        }
    }
}

private struct NativeDictionarySettingsPane: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSection("查询") {
                Toggle("Default to Dictionary Tab", isOn: $userConfig.dictionaryTabDefault)
                Toggle("Scan Non-Japanese Text", isOn: $userConfig.scanNonJapaneseText)
                NativeStepperRow(title: "Max Results", value: $userConfig.maxResults, range: 1...50)
                NativeStepperRow(title: "Scan Length", value: $userConfig.scanLength, range: 1...64)
            }

            NativeSettingsSection("折叠词典") {
                Picker("Mode", selection: $userConfig.collapseMode) {
                    Text("Expand All").tag(CollapseMode.expandAll)
                    Text("Collapse All").tag(CollapseMode.collapseAll)
                    Text("Custom").tag(CollapseMode.custom)
                }
                if userConfig.collapseMode != .expandAll {
                    Toggle("Expand First Dictionary", isOn: $userConfig.expandFirstDictionary)
                }
            }

            NativeSettingsSection("显示") {
                Toggle("Compact Glossaries", isOn: $userConfig.compactGlossaries)
                Toggle("Show Expression Tags", isOn: $userConfig.showExpressionTags)
                Toggle("Harmonic Frequency", isOn: $userConfig.harmonicFrequency)
                Toggle("Deduplicate Pitch Accents", isOn: $userConfig.deduplicatePitchAccents)
                Toggle("Compact Pitch Accents", isOn: $userConfig.compactPitchAccents)
                NativeSliderIntRow(title: "Mac Hover Delay", value: $userConfig.desktopLookupHoverDelayMs, range: 0...250, step: 5, suffix: " ms")
            }
        }
    }
}

private struct NativeAnkiSettingsPane: View {
    var body: some View {
        NativeSettingsForm {
            NativeSettingsSection("AnkiConnect") {
                LabeledContent("连接方式", value: "http://127.0.0.1:8765")
                Text("Mac 制卡主路径仍是 AnkiConnect。完整 deck/model/field 表单会在下一步把 AnkiManager 接入 native target。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NativeAudioSettingsPane: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSection("词典音频") {
                Toggle("Enable Local Audio", isOn: $userConfig.enableLocalAudio)
                Toggle("Autoplay Audio", isOn: $userConfig.audioEnableAutoplay)
                Picker("Background Audio", selection: $userConfig.audioPlaybackMode) {
                    Text("Interrupt").tag(AudioPlaybackMode.interrupt)
                    Text("Lower Volume").tag(AudioPlaybackMode.duck)
                    Text("Keep Volume").tag(AudioPlaybackMode.mix)
                }
            }
        }
    }
}

private struct NativeSasayakiSettingsPane: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSection("有声书") {
                Toggle("Enable Sasayaki", isOn: $userConfig.enableSasayaki)
                Toggle("Sync Audiobook Progress", isOn: $userConfig.sasayakiEnableSync)
                Toggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                Toggle("Auto-Scroll", isOn: $userConfig.sasayakiAutoScroll)
                Toggle("Auto-Pause on Lookup", isOn: $userConfig.sasayakiAutoPause)
                Toggle("Show Skip (±15s) Controls", isOn: $userConfig.sasayakiSkipControls)
                ColorPicker("Light Text Color", selection: $userConfig.sasayakiTextColor)
                ColorPicker("Light Background Color", selection: $userConfig.sasayakiBackgroundColor)
                ColorPicker("Dark Text Color", selection: $userConfig.sasayakiDarkTextColor)
                ColorPicker("Dark Background Color", selection: $userConfig.sasayakiDarkBackgroundColor)
            }
        }
    }
}

private struct NativeShortcutSettingsPane: View {
    var body: some View {
        NativeSettingsForm {
            NativeSettingsSection("快捷键捕获") {
                Text("当前先保留 native 快捷键捕获探针；完整快捷键/手柄绑定表单下一步从现有页面迁移。")
                    .foregroundStyle(.secondary)
                NativeShortcutCaptureProbeView()
            }
        }
    }
}

private struct NativeSyncSettingsPane: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSection("Google Drive") {
                Toggle("Enable Sync", isOn: $userConfig.enableSync)
                Toggle("Sync Book Data", isOn: $userConfig.syncUploadBooks)
                Toggle("Sync Statistics", isOn: $userConfig.statisticsEnableSync)
                Text("OAuth 登录、远端书籍刷新和冲突处理仍保留在 Catalyst 主路径，native 迁移时必须保护阅读进度。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NativeSettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
    }
}

private struct NativeSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct NativeSegmentedBoolRow: View {
    let title: String
    let falseTitle: String
    let trueTitle: String
    @Binding var value: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: $value) {
                Text(falseTitle).tag(false)
                Text(trueTitle).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }
}

private struct NativeStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)\(suffix)")
                .fontWeight(.semibold)
                .monospacedDigit()
            Stepper(title, value: $value, in: range)
                .labelsHidden()
        }
    }
}

private struct NativeSliderIntRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)\(suffix)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
    }
}

private struct NativeDoubleSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
