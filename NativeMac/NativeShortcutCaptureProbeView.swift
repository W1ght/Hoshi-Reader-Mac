import SwiftUI

struct NativeShortcutCaptureProbeView: View {
    @State private var isRecording = false
    @State private var lastCapture: NativeShortcutCaptureResult?
    @State private var lastEvent = "No capture yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcut Capture Probe")
                    .font(.headline)

                Text("Native AppKit key capture for the future keyboard-shortcut settings bridge. Press Escape while recording to verify cancel behavior.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(isRecording ? "Recording..." : "Start Recording") {
                    isRecording = true
                    lastEvent = "Waiting for a key. Escape should cancel."
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecording)

                if isRecording {
                    Button("Cancel") {
                        cancelRecording()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(lastEvent)
                    .foregroundStyle(isRecording ? .orange : .primary)

                if let lastCapture {
                    LabeledContent("Captured") {
                        Text(lastCapture.displayText)
                    }

                    LabeledContent("Key code") {
                        Text("\(lastCapture.keyCode)")
                    }

                    LabeledContent("Modifiers") {
                        Text(lastCapture.modifierSummary)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            NativeShortcutCaptureView(
                isActive: isRecording,
                onCapture: { result in
                    lastCapture = result
                    lastEvent = "Captured"
                    isRecording = false
                },
                onCancel: {
                    cancelRecording()
                }
            )
            .frame(width: 0, height: 0)
        }
    }

    private func cancelRecording() {
        isRecording = false
        lastEvent = "Cancelled by Escape"
    }
}
