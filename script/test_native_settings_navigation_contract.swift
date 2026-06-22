import Foundation

private enum NativeSettingsNavigationContractTests {
    static func read(_ relativePath: String) -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent(relativePath)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Unable to read \(relativePath)")
        }
        return source
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func run() {
        let root = read("NativeMac/NativeMacRootView.swift")
        let settings = read("NativeMac/NativeReuseViews.swift")
        let dictionary = read("Features/Settings/DictionaryView.swift")
        let audio = read("Features/Settings/AudioView.swift")
        let profiles = read("Features/Settings/ProfilesView.swift")
        let advanced = read("Features/Settings/AdvancedView.swift")

        require(
            root.contains(".id(selectedSection)"),
            "Changing the main sidebar section must reset any detail navigation destination"
        )
        require(
            !dictionary.contains("DictionarySettingsView()"),
            "Dictionary preferences must be shown inline instead of pushing a nested Settings destination"
        )
        require(
            dictionary.contains("DictionaryBehaviorSettingsSections()"),
            "The dictionary page must keep lookup and display preferences inline"
        )
        require(
            dictionary.contains("dictionaryManager.recommendedDictionaries.map")
                && !dictionary.contains("following dictionaries (33 MB):"),
            "Recommended dictionary confirmation must follow the active Profile language"
        )
        require(
            settings.contains("struct NativeSettingsReorderRow")
                && settings.contains("registerForDraggedTypes([.string])")
                && settings.contains("override func performDragOperation")
                && settings.contains("draggingPasteboard.string(forType: .string)")
                && settings.contains("NSHostingView<AnyView>")
                && !settings.contains("NSHostingView<Content>"),
            "Settings reorder rows must cross the macOS 26 SwiftUI drop boundary with a narrow AppKit destination"
        )
        require(
            dictionary.contains("NativeSettingsReorderRow(")
                && dictionary.contains(".onDrag {")
                && dictionary.contains("NSItemProvider(")
                && dictionary.contains("object: DictionaryReorder.payload")
                && !dictionary.contains(".onDrop(of: [.plainText]")
                && dictionary.contains("dictionaryManager.moveDictionary"),
            "Dictionary rows must keep full-row SwiftUI drag previews while AppKit commits the drop on macOS 26"
        )
        require(
            dictionary.contains("dictionaryReorderHandle()")
                && dictionary.contains(".contentShape(Rectangle())")
                && dictionary.contains(".onDrag {")
                && dictionary.contains("dictionaryDragPreview(dict)"),
            "Dictionary rows must show a leading handle while allowing full-row dragging with a control-free preview"
        )
        require(
            audio.contains("audioSourceReorderHandle()")
                && audio.contains(".contentShape(Rectangle())")
                && audio.contains(".onDrag {")
                && audio.contains("audioSourceDragPreview(source)"),
            "Audio source rows must mirror Dictionary rows with a leading handle and whole-row dragging"
        )
        require(
            audio.contains("NativeSettingsReorderRow(")
                && !audio.contains(".onDrop(of: [.plainText]")
                && audio.contains("dropTargetAudioSourceID == source.id")
                && audio.contains("userConfig.audioSources.move"),
            "Audio source drops must use the same AppKit destination, highlight it, and persist the reordered array"
        )
        require(
            settings.contains("case profiles") && settings.contains("ProfilesView()"),
            "Native Settings must expose the Profiles management page"
        )
        require(
            profiles.contains("setGlobalActiveProfile") && profiles.contains("setPrimaryProfile"),
            "Profiles must support active and per-language default selection"
        )
        require(
            profiles.contains("copyFromProfileID: repository.activeProfile.id"),
            "Normal profile creation must copy the current active profile"
        )
        require(
            settings.contains(
                """
                Section("Reader") {
                                nativeSettingsRow(.audio)
                                nativeSettingsRow(.statistics)
                                nativeSettingsRow(.sasayaki)
                            }
                """
            ),
            "Reader settings must contain only audio, statistics and Sasayaki"
        )
        require(
            settings.contains(
                """
                #if HOSHI_VIDEO
                            Section("Video") {
                                nativeSettingsRow(.video)
                            }
                            #endif
                """
            ),
            "Video builds must expose Video in its own conditional settings group"
        )
        require(
            settings.contains(
                """
                Section("Shortcuts & Controls") {
                                nativeSettingsRow(.keyboardShortcuts)
                                nativeSettingsRow(.gameController)
                            }
                """
            ),
            "Keyboard shortcuts and game controller settings must have their own group"
        )
        require(
            advanced.contains("Section(\"Reader\")")
                && advanced.contains("Section(\"Video\")")
                && advanced.contains("Section(\"Shortcuts & Controls\")"),
            "The legacy Advanced settings path must use the same Reader, Video and controls grouping"
        )

        print("Native settings navigation contract passed")
    }
}

NativeSettingsNavigationContractTests.run()
