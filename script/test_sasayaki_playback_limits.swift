import Foundation

let source = try String(
    contentsOfFile: "Features/Sasayaki/SasayakiSheet.swift",
    encoding: .utf8
)

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(
    source.contains("static let speedRange: ClosedRange<Float> = 0.5...2.5"),
    "Sasayaki should define one 0.5x to 2.5x speed range"
)
expect(
    source.components(separatedBy: "in: SasayakiPlaybackLimits.speedRange").count == 3,
    "native and legacy Sasayaki sliders should share the same speed range"
)

print("Sasayaki playback limits test passed")
