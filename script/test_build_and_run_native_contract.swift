import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let buildScriptPath = root.appendingPathComponent("script/build_and_run_native.sh")
private let buildScript = try String(contentsOf: buildScriptPath, encoding: .utf8)

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    buildScript.contains("INSTANCE_ID=\"${HOSHI_APP_INSTANCE_ID:-}\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"${HOSHI_DERIVED_DATA_PATH:-}\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"$ROOT_DIR/.build/xcode-derived-data-$INSTANCE_ID\"")
        && buildScript.contains("DERIVED_DATA_PATH=\"$ROOT_DIR/.build/xcode-derived-data\""),
    "build script should use a repo-local DerivedData path by default and support per-session instance DerivedData paths"
)

require(
    buildScript.contains("--instance <id>")
        && buildScript.contains("INSTANCE_ID=\"$2\"")
        && buildScript.contains("^[A-Za-z0-9._-]+$"),
    "build script should expose and validate a per-session instance id"
)

require(
    buildScript.contains("-scheme \"$SCHEME_NAME\"")
        && buildScript.contains("-sdk macosx")
        && buildScript.contains("-derivedDataPath \"$DERIVED_DATA_PATH\"")
        && buildScript.contains("-clonedSourcePackagesDirPath \"$SOURCE_PACKAGES_PATH\""),
    "xcodebuild should be constrained to the native macOS scheme and SDK"
)

require(
    buildScript.contains("cleanup_build_artifacts.sh\" --prune --protect \"$DERIVED_DATA_PATH\"")
        && buildScript.contains("--clean|clean)")
        && buildScript.contains("cleanup_build_artifacts.sh\" --all"),
    "build script should bound stale instance caches and expose an explicit full cleanup mode"
)

require(
    buildScript.contains("APP_BUNDLE=\"$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app\"")
        && !buildScript.contains("build_setting TARGET_BUILD_DIR")
        && !buildScript.contains("build_setting WRAPPER_NAME")
        && !buildScript.contains("-showBuildSettings"),
    "app bundle resolution should not call xcodebuild -showBuildSettings"
)

require(
    buildScript.contains("matching_app_pids()")
        && buildScript.contains("LC_ALL=C pgrep -f -- \"$APP_EXECUTABLE\"")
        && buildScript.contains("LC_ALL=C ps -p \"$pid\" -o command=")
        && buildScript.contains("[[ \"$command\" == \"$APP_EXECUTABLE\"* ]]")
        && !buildScript.contains("pkill -x \"$APP_NAME\""),
    "build script should target only the exact built app executable when stopping or verifying an app"
)

require(
    buildScript.contains("processIdentifier == $LOG_PID")
        && !buildScript.contains("process == \\\"$APP_NAME\\\""),
    "log streaming should be scoped to the launched process id, not all Niratan processes"
)

require(
    !buildScript.contains("-destination \"generic/platform=macOS\"")
        && !buildScript.contains("simctl")
        && !buildScript.contains("-runFirstLaunch")
        && !buildScript.contains("-downloadPlatform"),
    "native build script should not invoke simulator/device enumeration or platform download paths"
)

print("build_and_run_native contract checks passed")
