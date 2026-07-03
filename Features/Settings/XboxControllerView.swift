//
//  XboxControllerView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct XboxControllerView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var controllerManager = XboxControllerManager.shared

    var body: some View {
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Controller")
            } content: {
                NativeSettingsRow {
                    Label("Controller", systemImage: "gamecontroller")
                } accessory: {
                    Text(controllerManager.connectedControllerName ?? String(localized: "Not Connected"))
                        .foregroundStyle(controllerManager.isConnected ? .secondary : .tertiary)
                }

                if let recordingAction = controllerManager.recordingAction {
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        Button(role: .cancel) {
                            controllerManager.cancelRecording()
                        } label: {
                            Label("Waiting for controller input...", systemImage: "record.circle")
                        }
                        Text(LocalizedStringKey(recordingAction.titleKey))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Choose an action, then press a button or direction on an Xbox, PlayStation, Switch, or compatible controller.")
            }

            NativeSettingsSectionCard("Reading") {
                XboxControllerRecorderRow(
                    binding: userConfig.readerPreviousPageControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.readerPreviousPageControllerBinding),
                    action: .previousPage,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
                NativeSettingsSeparator()
                XboxControllerRecorderRow(
                    binding: userConfig.readerNextPageControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.readerNextPageControllerBinding),
                    action: .nextPage,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
            }

            NativeSettingsSectionCard("Sasayaki") {
                XboxControllerRecorderRow(
                    binding: userConfig.sasayakiPreviousCueControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.sasayakiPreviousCueControllerBinding),
                    action: .previousSasayakiCue,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
                NativeSettingsSeparator()
                XboxControllerRecorderRow(
                    binding: userConfig.sasayakiPlayPauseControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.sasayakiPlayPauseControllerBinding),
                    action: .playPauseSasayaki,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
                NativeSettingsSeparator()
                XboxControllerRecorderRow(
                    binding: userConfig.sasayakiNextCueControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.sasayakiNextCueControllerBinding),
                    action: .nextSasayakiCue,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
                NativeSettingsSeparator()
                XboxControllerRecorderRow(
                    binding: userConfig.sasayakiReplayCueControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.sasayakiReplayCueControllerBinding),
                    action: .replaySasayakiCue,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
                NativeSettingsSeparator()
                XboxControllerRecorderRow(
                    binding: userConfig.sasayakiJumpCueControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.sasayakiJumpCueControllerBinding),
                    action: .jumpSasayakiCue,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
            }

            NativeSettingsSectionCard("Statistics") {
                XboxControllerRecorderRow(
                    binding: userConfig.statisticsToggleControllerBinding,
                    displayLabel: controllerManager.label(for: userConfig.statisticsToggleControllerBinding),
                    action: .toggleStatistics,
                    recording: controllerManager.recordingAction,
                    onRecord: controllerManager.startRecording
                )
            }

            NativeSettingsSectionCard("Defaults") {
                NativeSettingsButtonRow {
                    Button("Reset Defaults") {
                        controllerManager.resetDefaults(userConfig: userConfig)
                    }
                }
            }
        }
        .navigationTitle("Game Controller")
        .onAppear {
            controllerManager.configure(userConfig: userConfig)
        }
    }
}

private struct XboxControllerRecorderRow: View {
    let binding: XboxControllerBinding
    let displayLabel: String
    let action: XboxControllerAction
    let recording: XboxControllerAction?
    let onRecord: (XboxControllerAction) -> Void

    private var isRecording: Bool {
        recording == action
    }

    var body: some View {
        Button {
            onRecord(action)
        } label: {
            HStack {
                Text(LocalizedStringKey(action.titleKey))
                    .foregroundStyle(.primary)

                Spacer()

                XboxControllerValuePill {
                    Text(isRecording ? "Press controller..." : displayLabel)
                        .foregroundStyle(isRecording ? Color.accentColor : .secondary)
                }
            }
            .frame(minHeight: 46)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct XboxControllerValuePill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.body.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}
