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
