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
                    "Remember Playback State",
                    isOn: $userConfig.videoRememberPlaybackPosition
                )
                NativeSettingsSeparator()
                NativeSettingsToggle(
                    "Auto-Hide Playback Controls",
                    isOn: $userConfig.videoPlaybackControlsAutoHideEnabled
                )
                NativeSettingsSeparator()
                NativeSettingsRow("Playback Controls Hide Delay") {
                    Text(String(format: "%.1f s", userConfig.videoPlaybackControlsAutoHideDelay))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: $userConfig.videoPlaybackControlsAutoHideDelay,
                        in: 0.5...10,
                        step: 0.5
                    )
                    .labelsHidden()
                }
                .disabled(!userConfig.videoPlaybackControlsAutoHideEnabled)
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
            } footer: {
                Text("Restores the last playback position and subtitle selection for each video.")
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
            NativeSettingsSeparator()
            NativeSettingsRow("Subtitle Color") {
                ColorPicker("Subtitle Color", selection: $userConfig.videoSubtitleColor)
                    .labelsHidden()
            }
            NativeSettingsSeparator()
            NativeSettingsRow("Lookup Highlight Color") {
                ColorPicker("Lookup Highlight Color", selection: $userConfig.videoSubtitleLookupHighlightColor)
                    .labelsHidden()
            }
        } footer: {
            Text("Customize subtitle typography, text color, and lookup highlight background.")
        }
    }

    private static var subtitleFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
#endif
