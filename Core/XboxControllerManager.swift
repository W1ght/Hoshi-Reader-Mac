//
//  XboxControllerManager.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import GameController

enum XboxControllerAction: String, CaseIterable, Identifiable {
    case previousPage
    case nextPage
    case previousSasayakiCue
    case playPauseSasayaki
    case nextSasayakiCue
    case replaySasayakiCue
    case jumpSasayakiCue
    case toggleStatistics

    var id: String { rawValue }

    var shortcutActionID: String? {
        switch self {
        case .previousPage:
            ReaderShortcutActions.previousPage.id
        case .nextPage:
            ReaderShortcutActions.nextPage.id
        case .previousSasayakiCue:
            SasayakiShortcutActions.previousCue.id
        case .playPauseSasayaki:
            SasayakiShortcutActions.playPause.id
        case .nextSasayakiCue:
            SasayakiShortcutActions.nextCue.id
        case .replaySasayakiCue:
            SasayakiShortcutActions.replayCue.id
        case .jumpSasayakiCue:
            SasayakiShortcutActions.jumpCue.id
        case .toggleStatistics:
            ReaderShortcutActions.toggleStatistics.id
        }
    }

    var titleKey: String {
        switch self {
        case .previousPage:
            ReaderShortcutActions.previousPage.titleKey
        case .nextPage:
            ReaderShortcutActions.nextPage.titleKey
        case .previousSasayakiCue:
            SasayakiShortcutActions.previousCue.titleKey
        case .playPauseSasayaki:
            SasayakiShortcutActions.playPause.titleKey
        case .nextSasayakiCue:
            SasayakiShortcutActions.nextCue.titleKey
        case .replaySasayakiCue:
            SasayakiShortcutActions.replayCue.titleKey
        case .jumpSasayakiCue:
            SasayakiShortcutActions.jumpCue.titleKey
        case .toggleStatistics:
            ReaderShortcutActions.toggleStatistics.titleKey
        }
    }
}

enum GameControllerFamily {
    case xbox
    case playStation
    case nintendo
    case generic
}

@MainActor
@Observable
final class XboxControllerManager {
    static let shared = XboxControllerManager()
    static let actionNotification = Notification.Name("XboxControllerActionNotification")

    private(set) var isConnected = false
    private(set) var connectedControllerName: String?
    private(set) var controllerFamily: GameControllerFamily = .generic
    var recordingAction: XboxControllerAction?

    private var userConfig: UserConfig?
    private var isStarted = false
    private var observers: [NSObjectProtocol] = []
    private var lastPressTimes: [String: Date] = [:]
    private let debounceInterval: TimeInterval = 0.18

    private init() {}

    func configure(userConfig: UserConfig) {
        self.userConfig = userConfig
        start()
    }

    func startRecording(for action: XboxControllerAction) {
        recordingAction = action
        start()
    }

    func cancelRecording() {
        recordingAction = nil
    }

    func resetDefaults(userConfig: UserConfig) {
        userConfig.readerPreviousPageControllerBinding = .dpadLeft
        userConfig.readerNextPageControllerBinding = .dpadRight
        userConfig.sasayakiPreviousCueControllerBinding = .leftShoulder
        userConfig.sasayakiPlayPauseControllerBinding = .buttonA
        userConfig.sasayakiNextCueControllerBinding = .rightShoulder
        userConfig.sasayakiReplayCueControllerBinding = .buttonX
        userConfig.sasayakiJumpCueControllerBinding = .buttonB
        userConfig.statisticsToggleControllerBinding = .buttonY
    }

    func binding(for action: XboxControllerAction, userConfig: UserConfig) -> XboxControllerBinding {
        switch action {
        case .previousPage:
            userConfig.readerPreviousPageControllerBinding
        case .nextPage:
            userConfig.readerNextPageControllerBinding
        case .previousSasayakiCue:
            userConfig.sasayakiPreviousCueControllerBinding
        case .playPauseSasayaki:
            userConfig.sasayakiPlayPauseControllerBinding
        case .nextSasayakiCue:
            userConfig.sasayakiNextCueControllerBinding
        case .replaySasayakiCue:
            userConfig.sasayakiReplayCueControllerBinding
        case .jumpSasayakiCue:
            userConfig.sasayakiJumpCueControllerBinding
        case .toggleStatistics:
            userConfig.statisticsToggleControllerBinding
        }
    }

    func label(for binding: XboxControllerBinding) -> String {
        switch controllerFamily {
        case .xbox:
            xboxLabel(for: binding.input)
        case .playStation:
            playStationLabel(for: binding.input)
        case .nintendo:
            nintendoLabel(for: binding.input)
        case .generic:
            binding.label
        }
    }

    private func start() {
        guard !isStarted else {
            refreshConnectedControllers()
            return
        }

        isStarted = true
        observeControllerConnections()
        refreshConnectedControllers()
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    private func observeControllerConnections() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object is GCController else { return }
            Task { @MainActor in
                self?.refreshConnectedControllers()
            }
        })

        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshConnectedControllers()
            }
        })
    }

    private func refreshConnectedControllers() {
        GCController.controllers().forEach(configure)
        let controller = GCController.controllers().first
        isConnected = controller != nil
        connectedControllerName = controller?.vendorName
        controllerFamily = controller.map(detectFamily) ?? .generic
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        bind(gamepad.buttonA, to: "buttonA")
        bind(gamepad.buttonB, to: "buttonB")
        bind(gamepad.buttonX, to: "buttonX")
        bind(gamepad.buttonY, to: "buttonY")
        bind(gamepad.leftShoulder, to: "leftShoulder")
        bind(gamepad.rightShoulder, to: "rightShoulder")
        bind(gamepad.leftTrigger, to: "leftTrigger")
        bind(gamepad.rightTrigger, to: "rightTrigger")
        bind(gamepad.buttonMenu, to: "buttonMenu")
        bindIfAvailable(gamepad.buttonOptions, to: "buttonOptions")
        bindIfAvailable(gamepad.buttonHome, to: "buttonHome")
        bindIfAvailable(gamepad.leftThumbstickButton, to: "leftThumbstickButton")
        bindIfAvailable(gamepad.rightThumbstickButton, to: "rightThumbstickButton")
        if let xboxGamepad = controller.physicalInputProfile as? GCXboxGamepad {
            bindIfAvailable(xboxGamepad.buttonShare, to: "buttonShare")
            bindIfAvailable(xboxGamepad.paddleButton1, to: "xboxPaddle1")
            bindIfAvailable(xboxGamepad.paddleButton2, to: "xboxPaddle2")
            bindIfAvailable(xboxGamepad.paddleButton3, to: "xboxPaddle3")
            bindIfAvailable(xboxGamepad.paddleButton4, to: "xboxPaddle4")
        }
        if let dualShockGamepad = controller.physicalInputProfile as? GCDualShockGamepad {
            bind(dualShockGamepad.touchpadButton, to: "playStationTouchpad")
        }
        if let dualSenseGamepad = controller.physicalInputProfile as? GCDualSenseGamepad {
            bind(dualSenseGamepad.touchpadButton, to: "playStationTouchpad")
        }

        bind(gamepad.dpad.up, to: "dpadUp")
        bind(gamepad.dpad.down, to: "dpadDown")
        bind(gamepad.dpad.left, to: "dpadLeft")
        bind(gamepad.dpad.right, to: "dpadRight")

        bind(gamepad.leftThumbstick.up, to: "leftThumbstickUp")
        bind(gamepad.leftThumbstick.down, to: "leftThumbstickDown")
        bind(gamepad.leftThumbstick.left, to: "leftThumbstickLeft")
        bind(gamepad.leftThumbstick.right, to: "leftThumbstickRight")

        bind(gamepad.rightThumbstick.up, to: "rightThumbstickUp")
        bind(gamepad.rightThumbstick.down, to: "rightThumbstickDown")
        bind(gamepad.rightThumbstick.left, to: "rightThumbstickLeft")
        bind(gamepad.rightThumbstick.right, to: "rightThumbstickRight")
    }

    private func bind(_ button: GCControllerButtonInput, to input: String) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.handle(input: input)
            }
        }
    }

    private func bindIfAvailable(_ button: GCControllerButtonInput?, to input: String) {
        guard let button else { return }
        bind(button, to: input)
    }

    private func handle(input: String) {
        let now = Date()
        if let lastPressTime = lastPressTimes[input],
           now.timeIntervalSince(lastPressTime) < debounceInterval {
            return
        }
        lastPressTimes[input] = now

        if let recordingAction, let userConfig {
            setBinding(XboxControllerBinding(input: input), for: recordingAction, userConfig: userConfig)
            self.recordingAction = nil
            return
        }

        guard let action = action(for: input) else {
            return
        }

        NotificationCenter.default.post(
            name: Self.actionNotification,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }

    private func action(for input: String) -> XboxControllerAction? {
        guard let userConfig else { return nil }
        return XboxControllerAction.allCases.first {
            binding(for: $0, userConfig: userConfig).input == input
        }
    }

    private func setBinding(_ binding: XboxControllerBinding, for action: XboxControllerAction, userConfig: UserConfig) {
        switch action {
        case .previousPage:
            userConfig.readerPreviousPageControllerBinding = binding
        case .nextPage:
            userConfig.readerNextPageControllerBinding = binding
        case .previousSasayakiCue:
            userConfig.sasayakiPreviousCueControllerBinding = binding
        case .playPauseSasayaki:
            userConfig.sasayakiPlayPauseControllerBinding = binding
        case .nextSasayakiCue:
            userConfig.sasayakiNextCueControllerBinding = binding
        case .replaySasayakiCue:
            userConfig.sasayakiReplayCueControllerBinding = binding
        case .jumpSasayakiCue:
            userConfig.sasayakiJumpCueControllerBinding = binding
        case .toggleStatistics:
            userConfig.statisticsToggleControllerBinding = binding
        }
    }

    private func detectFamily(for controller: GCController) -> GameControllerFamily {
        if controller.physicalInputProfile is GCXboxGamepad {
            return .xbox
        }
        if controller.physicalInputProfile is GCDualShockGamepad || controller.physicalInputProfile is GCDualSenseGamepad {
            return .playStation
        }

        let vendorName = controller.vendorName?.lowercased() ?? ""
        if vendorName.contains("xbox") {
            return .xbox
        }
        if vendorName.contains("playstation") || vendorName.contains("dualshock") || vendorName.contains("dualsense") || vendorName.contains("sony") {
            return .playStation
        }
        if vendorName.contains("switch") || vendorName.contains("nintendo") || vendorName.contains("joy-con") || vendorName.contains("pro controller") {
            return .nintendo
        }
        return .generic
    }

    private func xboxLabel(for input: String) -> String {
        switch input {
        case "buttonA": "A"
        case "buttonB": "B"
        case "buttonX": "X"
        case "buttonY": "Y"
        case "leftShoulder": "LB"
        case "rightShoulder": "RB"
        case "leftTrigger": "LT"
        case "rightTrigger": "RT"
        case "buttonOptions": "View"
        case "buttonMenu": "Menu"
        case "buttonHome": "Xbox"
        case "buttonShare": "Share"
        case "xboxPaddle1": "Paddle 1"
        case "xboxPaddle2": "Paddle 2"
        case "xboxPaddle3": "Paddle 3"
        case "xboxPaddle4": "Paddle 4"
        default: XboxControllerBinding(input: input).label
        }
    }

    private func playStationLabel(for input: String) -> String {
        switch input {
        case "buttonA": "Cross"
        case "buttonB": "Circle"
        case "buttonX": "Square"
        case "buttonY": "Triangle"
        case "leftShoulder": "L1"
        case "rightShoulder": "R1"
        case "leftTrigger": "L2"
        case "rightTrigger": "R2"
        case "leftThumbstickButton": "L3"
        case "rightThumbstickButton": "R3"
        case "buttonOptions": "Share/Create"
        case "buttonMenu": "Options"
        case "buttonHome": "PS"
        case "buttonShare": "Create"
        case "playStationTouchpad": "Touchpad"
        default: XboxControllerBinding(input: input).label
        }
    }

    private func nintendoLabel(for input: String) -> String {
        switch input {
        case "buttonA": "B"
        case "buttonB": "A"
        case "buttonX": "Y"
        case "buttonY": "X"
        case "leftShoulder": "L"
        case "rightShoulder": "R"
        case "leftTrigger": "ZL"
        case "rightTrigger": "ZR"
        case "buttonOptions": "-"
        case "buttonMenu": "+"
        case "buttonHome": "Home"
        case "buttonShare": "Capture"
        default: XboxControllerBinding(input: input).label
        }
    }
}
