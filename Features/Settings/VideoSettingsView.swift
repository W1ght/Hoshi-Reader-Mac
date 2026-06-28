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
                NativeSettingsRow("Control Bar Layout") {
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.videoControlBarLayout,
                        values: VideoControlBarLayout.allCases,
                        minSegmentWidth: 104
                    ) { layout in
                        switch layout {
                        case .floating:
                            Text("Floating")
                        case .compactBottom:
                            Text("Compact Bottom")
                        }
                    }
                }
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

            videoEnhancementSection

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

    private var videoEnhancementSection: some View {
        @Bindable var userConfig = userConfig

        return NativeSettingsSectionCard {
            Text("Video Enhancement")
        } content: {
            NativeSettingsToggle(
                "Hardware Decoding",
                isOn: $userConfig.videoHardwareDecodingEnabled
            )
            NativeSettingsSeparator()
            NativeSettingsToggle(
                "Deinterlace",
                isOn: $userConfig.videoDeinterlacingEnabled
            )
            NativeSettingsSeparator()
            NativeSettingsToggle(
                "HDR",
                isOn: $userConfig.videoHDREnhancementEnabled
            )
            NativeSettingsSeparator()
            videoEqualizerSlider(.brightness, value: $userConfig.videoBrightness)
            NativeSettingsSeparator()
            videoEqualizerSlider(.contrast, value: $userConfig.videoContrast)
            NativeSettingsSeparator()
            videoEqualizerSlider(.saturation, value: $userConfig.videoSaturation)
            NativeSettingsSeparator()
            videoEqualizerSlider(.gamma, value: $userConfig.videoGamma)
            NativeSettingsSeparator()
            videoEqualizerSlider(.hue, value: $userConfig.videoHue)
        } footer: {
            Text("Hardware decoding uses mpv's automatic safe decoder path. HDR changes mpv tone-mapping peak handling.")
        }
    }

    private var subtitleAppearanceSection: some View {
        @Bindable var userConfig = userConfig

        return NativeSettingsSectionCard {
            Text("Subtitle Appearance")
        } content: {
            NativeSettingsRow("Subtitle Font") {
                NativeGlassMenuPicker(
                    selection: $userConfig.videoSubtitleFontFamily,
                    values: [""] + Self.subtitleFontFamilies,
                    minWidth: 170
                ) { family in
                    if family.isEmpty {
                        Text("System Default")
                    } else {
                        Text(verbatim: family)
                    }
                }
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
            NativeSettingsRow("Subtitle Weight") {
                Text("\(userConfig.videoSubtitleFontWeight)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Stepper(
                    "",
                    value: $userConfig.videoSubtitleFontWeight,
                    in: 100...900,
                    step: 100
                )
                .labelsHidden()
            }
            NativeSettingsSeparator()
            NativeSettingsSliderRow(
                title: "Shadow",
                value: String(format: "%.1f", userConfig.videoSubtitleShadowRadius)
            ) {
                Slider(
                    value: $userConfig.videoSubtitleShadowRadius,
                    in: 0...10,
                    step: 0.5
                )
            }
            NativeSettingsSeparator()
            NativeSettingsSliderRow(
                title: "Background Opacity",
                value: "\(Int(userConfig.videoSubtitleBackgroundOpacity * 100))%"
            ) {
                Slider(
                    value: $userConfig.videoSubtitleBackgroundOpacity,
                    in: 0...1,
                    step: 0.05
                )
                .disabled(userConfig.videoSubtitleBackgroundDisabled)
            }
            NativeSettingsSeparator()
            NativeSettingsToggle(
                "No Background",
                isOn: $userConfig.videoSubtitleBackgroundDisabled
            )
            NativeSettingsSeparator()
            NativeSettingsSliderRow(
                title: "Vertical Position",
                value: "\(Int(userConfig.videoSubtitleVerticalPosition))"
            ) {
                Slider(
                    value: $userConfig.videoSubtitleVerticalPosition,
                    in: -200...200,
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
            NativeSettingsSeparator()
            NativeSettingsRow("Lookup Highlight Text Color") {
                ColorPicker("Lookup Highlight Text Color", selection: $userConfig.videoSubtitleLookupHighlightTextColor)
                    .labelsHidden()
            }
            NativeSettingsSeparator()
            NativeSettingsRow {
                Button("Restore Defaults", action: userConfig.resetVideoSubtitleAppearance)
            } accessory: {
                EmptyView()
            }
        } footer: {
            Text("Customize subtitle typography, text color, and lookup highlight colors.")
            Text("Let subtitle background stay transparent.")
        }
    }

    private static var subtitleFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func videoEqualizerSlider(
        _ adjustment: VideoEqualizerAdjustment,
        value: Binding<Double>
    ) -> some View {
        NativeSettingsSliderRow(
            title: LocalizedStringKey(adjustment.title),
            value: "\(Int(value.wrappedValue.rounded()))"
        ) {
            HStack(spacing: 10) {
                Slider(
                    value: value,
                    in: VideoEqualizerAdjustment.minimum...VideoEqualizerAdjustment.maximum,
                    step: 1
                )
                Button {
                    value.wrappedValue = VideoEqualizerAdjustment.neutral
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset")
            }
        }
    }
}
#endif
