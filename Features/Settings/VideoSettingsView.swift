#if HOSHI_VIDEO
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

            NativeSettingsSectionCard {
                Text("Keyboard Shortcuts")
            } content: {
                NativeSettingsButtonRow {
                    Text("Configure Video shortcuts in the unified Keyboard Shortcuts page.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Video shortcuts share the same registry and scope-aware conflict detection as Reader and Popup shortcuts.")
            }
        }
        .navigationTitle("Video")
    }
}
#endif
