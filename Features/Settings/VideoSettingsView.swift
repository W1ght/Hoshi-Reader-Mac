#if HOSHI_VIDEO
import AppKit
import SwiftUI

struct VideoSettingsView: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig

        NativeSettingsForm {
            NativeSettingsSectionCard("Playback") {
                NativeSettingsToggle(
                    "Auto-Play Next Episode",
                    isOn: $userConfig.videoAutoPlayNext
                )
                NativeSettingsSeparator()
                NativeSettingsToggle(
                    "Remember Playback Position",
                    isOn: $userConfig.videoRememberPlaybackPosition
                )
                NativeSettingsSeparator()
                NativeSettingsRow("Default Seek Interval") {
                    Text("\(Int(userConfig.videoSeekInterval)) s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: $userConfig.videoSeekInterval,
                        in: 1...60,
                        step: 1
                    )
                    .labelsHidden()
                }
            }

            NativeSettingsSectionCard("Mining") {
                NativeSettingsRow("Mining History Storage Limit") {
                    Text("\(userConfig.videoMiningHistoryLimit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: $userConfig.videoMiningHistoryLimit,
                        in: 0...1000,
                        step: 1
                    )
                    .labelsHidden()
                }
            } footer: {
                Text("Set to 0 to disable and clear Mining History.")
            }

            subtitleAppearanceSection

            NativeSettingsSectionCard {
                Text("Subtitle Mask")
            } content: {
                NativeSettingsToggle(
                    "Mask subtitles until hover",
                    isOn: $userConfig.videoSubtitleMaskEnabled
                )
                NativeSettingsSeparator()
                NativeSettingsRow("Mask Mode") {
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.videoSubtitleMaskMode,
                        values: VideoSubtitleMaskMode.allCases,
                        minSegmentWidth: 94
                    ) { mode in
                        Text(LocalizedStringKey(mode.rawValue))
                            .font(.caption.weight(.semibold))
                    }
                }
                .disabled(!userConfig.videoSubtitleMaskEnabled)
                NativeSettingsSeparator()
                if userConfig.videoSubtitleMaskMode == .blur {
                    NativeSettingsSliderRow(
                        title: "Blur Radius",
                        value: "\(Int(userConfig.videoSubtitleMaskBlurRadius)) px"
                    ) {
                        Slider(
                            value: $userConfig.videoSubtitleMaskBlurRadius,
                            in: 0...20,
                            step: 1
                        )
                    }
                } else {
                    NativeSettingsSliderRow(
                        title: "Hidden Opacity",
                        value: "\(Int(userConfig.videoSubtitleMaskHiddenOpacity * 100))%"
                    ) {
                        Slider(
                            value: $userConfig.videoSubtitleMaskHiddenOpacity,
                            in: 0...1,
                            step: 0.05
                        )
                    }
                }
            } footer: {
                Text("Masked subtitles are shown normally while the pointer is over the subtitle row.")
            }

            shortcutSummarySection
        }
        .navigationTitle("Video")
    }

    private var subtitleAppearanceSection: some View {
        @Bindable var userConfig = userConfig

        return NativeSettingsSectionCard {
            Text("Subtitle Appearance")
        } content: {
            NativeSettingsRow("Subtitle Font") {
                Picker(selection: $userConfig.videoSubtitleFontFamily) {
                    Text("System Default").tag("")
                    ForEach(Self.subtitleFontFamilies, id: \.self) { family in
                        Text(verbatim: family).tag(family)
                    }
                } label: {
                    Text("Subtitle Font")
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            NativeSettingsSeparator()
            NativeSettingsSliderRow(
                title: "Subtitle Size",
                value: "\(Int(userConfig.videoSubtitleFontSize)) px"
            ) {
                Slider(
                    value: $userConfig.videoSubtitleFontSize,
                    in: 12...72,
                    step: 1
                )
            }
        } footer: {
            Text("Defaults match asbplayer text subtitles: system font and 36 px size.")
        }
    }

    private var shortcutSummarySection: some View {
        NativeSettingsSectionCard {
            Text("Keyboard Shortcuts")
        } content: {
            shortcutSummaryGroup(
                title: "Playback Shortcuts",
                actions: [
                    VideoShortcutActions.playPause,
                    VideoShortcutActions.seekBackward,
                    VideoShortcutActions.seekForward,
                    VideoShortcutActions.previousEpisode,
                    VideoShortcutActions.nextEpisode,
                    VideoShortcutActions.toggleFullScreen,
                    VideoShortcutActions.decreaseSpeed,
                    VideoShortcutActions.increaseSpeed,
                    VideoShortcutActions.resetSpeed,
                ]
            )

            NativeSettingsSeparator()

            shortcutSummaryGroup(
                title: "Subtitle Shortcuts",
                actions: [
                    VideoShortcutActions.mineCurrentSubtitle,
                    VideoShortcutActions.previousSubtitleCue,
                    VideoShortcutActions.nextSubtitleCue,
                    VideoShortcutActions.toggleSubtitlesVisible,
                    VideoShortcutActions.cycleSubtitleTrack,
                    VideoShortcutActions.subtitleEarlier,
                    VideoShortcutActions.subtitleLater,
                    VideoShortcutActions.resetSubtitleTiming,
                    VideoShortcutActions.toggleTranscript,
                ]
            )

            NativeSettingsSeparator()

            shortcutSummaryGroup(
                title: "Audio Shortcuts",
                actions: [
                    VideoShortcutActions.volumeDown,
                    VideoShortcutActions.volumeUp,
                    VideoShortcutActions.toggleMute,
                    VideoShortcutActions.audioEarlier,
                    VideoShortcutActions.audioLater,
                ]
            )

            NativeSettingsSeparator()

            NativeSettingsButtonRow {
                Label("Open Keyboard Shortcuts", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Configure Video shortcuts in the unified Keyboard Shortcuts page.")
        }
    }

    private func shortcutSummaryGroup(
        title: LocalizedStringKey,
        actions: [ShortcutAction]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    NativeSettingsSeparator()
                }
                shortcutSummaryRow(action)
            }
        }
    }

    private func shortcutSummaryRow(_ action: ShortcutAction) -> some View {
        NativeSettingsRow(LocalizedStringKey(action.titleKey)) {
            Text(userConfig.shortcutBinding(for: action).label)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private static var subtitleFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
#endif
