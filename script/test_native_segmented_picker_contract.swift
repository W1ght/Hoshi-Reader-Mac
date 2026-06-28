import Foundation
import Darwin

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("NativeMac/NativeReuseViews.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let projectURL = root.appendingPathComponent("Hoshi Reader.xcodeproj/project.pbxproj")
let project = try String(contentsOf: projectURL, encoding: .utf8)

guard
    let pickerStart = source.range(of: "struct NativeGlassSegmentedPicker"),
    let pickerEnd = source.range(of: "struct NativeGlassMenuPicker", range: pickerStart.upperBound..<source.endIndex)
else {
    fatalError("Could not locate NativeGlassSegmentedPicker in NativeReuseViews.swift")
}

let pickerSource = String(source[pickerStart.lowerBound..<pickerEnd.lowerBound])

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("error: \(message)\n", stderr)
        exit(1)
    }
}

expect(
    !pickerSource.contains("Picker(\"\", selection: $selection)"),
    "NativeGlassSegmentedPicker should not use the material segmented Picker in Settings."
)
expect(
    !pickerSource.contains(".pickerStyle(.segmented)"),
    "NativeGlassSegmentedPicker should not use the material segmented picker style."
)
expect(
    pickerSource.contains("GlassEffectContainer(spacing: 0)"),
    "NativeGlassSegmentedPicker should group its glass elements."
)
expect(
    pickerSource.contains(".nativeGlassSegmentContainer()")
    && pickerSource.contains(".nativeGlassSelectedSegment()")
    && source.contains("func nativeGlassSegmentContainer()")
    && source.contains("func nativeGlassSelectedSegment()")
    && source.contains(".glassEffect(.regular.interactive(), in: Capsule())"),
    "NativeGlassSegmentedPicker should use the native Liquid Glass effect."
)
expect(
    !pickerSource.contains("#available(macOS 26.0)")
    && !pickerSource.contains("#unavailable(macOS 26.0)"),
    "NativeGlassSegmentedPicker should not branch for macOS 26 now that it is the minimum target."
)
expect(
    pickerSource.contains("matchedGeometryEffect"),
    "NativeGlassSegmentedPicker should animate the selected glass segment."
)
expect(
    !project.contains("MACOSX_DEPLOYMENT_TARGET = 15.0;")
    && project.contains("MACOSX_DEPLOYMENT_TARGET = 26.0;"),
    "Hoshi Reader should target macOS 26.0 or newer."
)

print("Native segmented picker contract passed")
