#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$ROOT_DIR/artifacts/reader-regression/$TIMESTAMP"
FIXTURE_DIR="$ROOT_DIR/testdata/reader-fixtures"
PLAN_ONLY=1
SMOKE_CAPTURE=0
SCENARIO_CAPTURE=""
UPDATE_BASELINE_DIR=""
COMPARE_BASELINE_DIR=""
MAX_DIFF_PIXELS=0
MAX_DIFF_RATIO="0"
MAX_CHANNEL_DELTA=255

usage() {
  cat <<'EOF'
usage: script/capture_reader_regression.sh [--output DIR] [--fixtures DIR] [--plan-only] [--smoke-capture] [--scenario-capture N] [--update-baseline DIR] [--compare-baseline DIR] [--max-diff-pixels N] [--max-diff-ratio RATIO] [--max-channel-delta N]

Generates Reader fixtures, creates a Reader regression run directory, and writes
the planned screenshot manifest.

  --plan-only       Only write the run directory and manifest.
  --smoke-capture   Launch the Debug-only Reader Regression Lab and capture its
                    window to screenshots/00-reader-regression-lab.png. This is
                    a pipeline smoke check, not full scenario automation.
  --scenario-capture N
                    Launch Reader scenario N, or all scenarios with "all",
                    through the Debug-only Lab wiring and capture Reader
                    window screenshots.
  --update-baseline DIR
                    Copy captured screenshots and geometry sidecars into DIR.
  --compare-baseline DIR
                    Compare captured screenshots against DIR and write
                    baseline-report.json in the output directory.
  --max-diff-pixels N
                    Maximum differing pixels allowed per screenshot. Default: 0.
  --max-diff-ratio RATIO
                    Maximum differing pixel ratio allowed per screenshot. Default: 0.
  --max-channel-delta N
                    Maximum RGBA channel delta allowed on differing pixels.
                    Default: 255, so strictness is governed by pixel counts.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 ]]; then
        echo "--output requires a directory" >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --fixtures)
      if [[ $# -lt 2 ]]; then
        echo "--fixtures requires a directory" >&2
        exit 2
      fi
      FIXTURE_DIR="$2"
      shift 2
      ;;
    --plan-only)
      PLAN_ONLY=1
      shift
      ;;
    --smoke-capture)
      PLAN_ONLY=0
      SMOKE_CAPTURE=1
      shift
      ;;
    --scenario-capture)
      if [[ $# -lt 2 ]]; then
        echo "--scenario-capture requires a one-based scenario number or all" >&2
        exit 2
      fi
      PLAN_ONLY=0
      SCENARIO_CAPTURE="$2"
      shift 2
      ;;
    --update-baseline)
      if [[ $# -lt 2 ]]; then
        echo "--update-baseline requires a directory" >&2
        exit 2
      fi
      UPDATE_BASELINE_DIR="$2"
      shift 2
      ;;
    --compare-baseline)
      if [[ $# -lt 2 ]]; then
        echo "--compare-baseline requires a directory" >&2
        exit 2
      fi
      COMPARE_BASELINE_DIR="$2"
      shift 2
      ;;
    --max-diff-pixels)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
        echo "--max-diff-pixels requires a non-negative integer" >&2
        exit 2
      fi
      MAX_DIFF_PIXELS="$2"
      shift 2
      ;;
    --max-diff-ratio)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
         ! awk -v value="$2" 'BEGIN { exit !(value >= 0 && value <= 1) }'; then
        echo "--max-diff-ratio requires a decimal value between 0 and 1" >&2
        exit 2
      fi
      MAX_DIFF_RATIO="$2"
      shift 2
      ;;
    --max-channel-delta)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]] || (( 10#$2 > 255 )); then
        echo "--max-channel-delta requires an integer between 0 and 255" >&2
        exit 2
      fi
      MAX_CHANNEL_DELTA="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCREENSHOT_NAMES=(
  "01-horizontal-paginated-light.png"
  "02-horizontal-continuous-light.png"
  "03-vertical-paginated-light.png"
  "04-vertical-continuous-light.png"
  "05-vertical-fullscreen.png"
  "06-long-chapter-end.png"
  "07-ruby-popup.png"
  "08-multi-image-page.png"
  "09-cover-page.png"
  "10-eink-popup.png"
)

scenario_screenshot_name() {
  local scenario="$1"
  if [[ ! "$scenario" =~ ^[0-9]+$ ]]; then
    echo "--scenario-capture currently requires a one-based scenario number" >&2
    exit 2
  fi
  local index=$((scenario - 1))
  if (( index < 0 || index >= ${#SCREENSHOT_NAMES[@]} )); then
    echo "--scenario-capture must be between 1 and ${#SCREENSHOT_NAMES[@]}" >&2
    exit 2
  fi
  echo "${SCREENSHOT_NAMES[$index]}"
}

scenario_count() {
  echo "${#SCREENSHOT_NAMES[@]}"
}

front_window_id() {
  /usr/bin/swift - "$@" <<'SWIFT'
import CoreGraphics
import Foundation

let ownerNames = Set(CommandLine.arguments.dropFirst())
let deadline = Date().addingTimeInterval(60)

while Date() < deadline {
    if let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
        var bestWindow: (id: UInt32, area: Double)?
        for window in windows {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerNames.contains(ownerName),
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowID = window[kCGWindowNumber as String] as? UInt32,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else {
                continue
            }
            let area = width * height
            guard width >= 640, height >= 480 else {
                continue
            }
            if bestWindow == nil || area > bestWindow!.area {
                bestWindow = (windowID, area)
            }
        }
        if let bestWindow {
            print(bestWindow.id)
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.25)
}

fputs("Timed out waiting for Reader Regression Lab window owned by: \(ownerNames.sorted().joined(separator: ", "))\n", stderr)
exit(1)
SWIFT
}

window_capture_rect() {
  local window_id="$1"
  /usr/bin/swift - "$window_id" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let targetID = UInt32(CommandLine.arguments[1]),
      let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
      let window = windows.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == targetID }),
      let bounds = window[kCGWindowBounds as String] as? [String: Any],
      let x = bounds["X"] as? Double,
      let y = bounds["Y"] as? Double,
      let width = bounds["Width"] as? Double,
      let height = bounds["Height"] as? Double else {
    exit(1)
}

print("\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))")
SWIFT
}

crop_full_screenshot_to_rect() {
  local rect="$1"
  local screenshot="$2"
  local full_screenshot="$OUTPUT_DIR/screenshots/full-screenshot.tmp.png"
  /usr/sbin/screencapture -x "$full_screenshot"
  /usr/bin/swift - "$full_screenshot" "$rect" "$screenshot" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 4 else {
    fputs("usage: swift fullScreenshot rect output\n", stderr)
    exit(2)
}

let fullURL = URL(fileURLWithPath: CommandLine.arguments[1])
let rectParts = CommandLine.arguments[2].split(separator: ",").compactMap { Double($0) }
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
guard rectParts.count == 4,
      let source = CGImageSourceCreateWithURL(fullURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    exit(1)
}

let displayBounds = CGDisplayBounds(CGMainDisplayID())
let scaleX = Double(image.width) / displayBounds.width
let scaleY = Double(image.height) / displayBounds.height
let cropRect = CGRect(
    x: rectParts[0] * scaleX,
    y: rectParts[1] * scaleY,
    width: rectParts[2] * scaleX,
    height: rectParts[3] * scaleY
).integral

guard let cropped = image.cropping(to: cropRect),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, cropped, nil)
guard CGImageDestinationFinalize(destination) else {
    exit(1)
}
SWIFT
  rm -f "$full_screenshot"
}

capture_window_screenshot() {
  local screenshot="$1"
  local error_log="$OUTPUT_DIR/screenshots/screencapture-error.log"
  local attempt
  for attempt in 1 2 3 4 5; do
    local window_id
    window_id="$(front_window_id "Hoshi Reader")"
    if /usr/sbin/screencapture -x -l "$window_id" "$screenshot" 2>"$error_log" && [[ -s "$screenshot" ]]; then
      rm -f "$error_log"
      echo "$window_id"
      return 0
    fi
    local rect
    if rect="$(window_capture_rect "$window_id")" &&
       /usr/sbin/screencapture -x -R "$rect" "$screenshot" 2>"$error_log" &&
       [[ -s "$screenshot" ]]; then
      rm -f "$error_log"
      echo "$window_id"
      return 0
    fi
    if [[ -n "${rect:-}" ]] &&
       crop_full_screenshot_to_rect "$rect" "$screenshot" 2>"$error_log" &&
       [[ -s "$screenshot" ]]; then
      rm -f "$error_log"
      echo "$window_id"
      return 0
    fi
    rm -f "$screenshot"
    sleep 1
  done

  echo "Scenario screenshot was not created: $screenshot" >&2
  if [[ -s "$error_log" ]]; then
    cat "$error_log" >&2
  fi
  exit 1
}

write_capture_geometry_json() {
  local scenario="$1"
  local screenshot_relative="$2"
  local screenshot="$OUTPUT_DIR/$screenshot_relative"
  local window_id="$3"
  local reader_metrics="${4:-}"
  local geometry="$OUTPUT_DIR/${screenshot_relative%.png}.geometry.json"

  /usr/bin/swift - "$scenario" "$screenshot_relative" "$screenshot" "$window_id" "$FIXTURE_DIR" "$geometry" "$reader_metrics" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 8,
      let windowID = UInt32(arguments[4]) else {
    fputs("usage: swift geometry scenario screenshotRelative screenshotPath windowID fixtureDir outputPath readerMetricsPath\n", stderr)
    exit(2)
}

let scenario = arguments[1]
let screenshotRelative = arguments[2]
let screenshotURL = URL(fileURLWithPath: arguments[3])
let fixtureDirectory = arguments[5]
let outputURL = URL(fileURLWithPath: arguments[6])
let readerMetricsPath = arguments[7]

var screenshotPixels: [String: Any] = [:]
if let source = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
    screenshotPixels["width"] = properties[kCGImagePropertyPixelWidth as String]
    screenshotPixels["height"] = properties[kCGImagePropertyPixelHeight as String]
}

var windowPayload: [String: Any] = ["id": windowID]
if let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
   let window = windows.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == windowID }) {
    windowPayload["ownerName"] = window[kCGWindowOwnerName as String] as? String ?? ""
    windowPayload["title"] = window[kCGWindowName as String] as? String ?? ""
    windowPayload["layer"] = window[kCGWindowLayer as String] as? Int ?? 0
    if let bounds = window[kCGWindowBounds as String] as? [String: Any] {
        windowPayload["bounds"] = [
            "x": bounds["X"] ?? 0,
            "y": bounds["Y"] ?? 0,
            "width": bounds["Width"] ?? 0,
            "height": bounds["Height"] ?? 0
        ]
    }
}

let readerMetrics: Any
if !readerMetricsPath.isEmpty,
   let data = try? Data(contentsOf: URL(fileURLWithPath: readerMetricsPath)),
   let object = try? JSONSerialization.jsonObject(with: data),
   JSONSerialization.isValidJSONObject(object) {
    readerMetrics = object
} else {
    readerMetrics = NSNull()
}

var payload: [String: Any] = [
    "schemaVersion": 1,
    "capturedAt": ISO8601DateFormatter().string(from: Date()),
    "scenario": scenario,
    "screenshot": screenshotRelative,
    "fixtureDirectory": fixtureDirectory,
    "window": windowPayload,
    "screenshotPixels": screenshotPixels,
    "readerMetrics": readerMetrics,
    "notes": readerMetrics is NSNull
        ? "Desktop/window capture geometry only. Reader-internal viewport/page metrics were not available."
        : "Desktop/window capture geometry plus Reader-internal metrics."
]

if let scenarioNumber = Int(scenario) {
    payload["scenarioIndex"] = scenarioNumber
}

let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputURL)
SWIFT
}

capture_smoke_screenshot() {
  local screenshot_relative="screenshots/00-reader-regression-lab.png"
  local screenshot="$OUTPUT_DIR/$screenshot_relative"
  pkill -x "Hoshi Reader" >/dev/null 2>&1 || true
  "$ROOT_DIR/script/build_and_run_native.sh" --reader-regression-lab --reader-regression-fixtures "$FIXTURE_DIR"
  sleep 3
  local window_id
  window_id="$(capture_window_screenshot "$screenshot")"
  write_capture_geometry_json "lab" "$screenshot_relative" "$window_id" ""
  echo "Captured Reader Regression Lab smoke screenshot:"
  echo "$screenshot"
}

capture_scenario_screenshot() {
  local scenario="$1"
  local screenshot_name
  screenshot_name="$(scenario_screenshot_name "$scenario")"
  local screenshot_relative="screenshots/$screenshot_name"
  local screenshot="$OUTPUT_DIR/$screenshot_relative"
  local reader_metrics="$OUTPUT_DIR/screenshots/${screenshot_name%.png}.reader-metrics.json"
  pkill -x "Hoshi Reader" >/dev/null 2>&1 || true
  "$ROOT_DIR/script/build_and_run_native.sh" --reader-regression-lab \
    --reader-regression-fixtures "$FIXTURE_DIR" \
    --reader-regression-scenario "$scenario" \
    --reader-regression-metrics "$reader_metrics"
  local deadline=$((SECONDS + 60))
  while [[ ! -s "$reader_metrics" && $SECONDS -lt $deadline ]]; do
    sleep 0.25
  done
  if [[ ! -s "$reader_metrics" ]]; then
    echo "Timed out waiting for Native Reader metrics: $reader_metrics" >&2
    exit 1
  fi
  sleep 2
  local window_id
  window_id="$(capture_window_screenshot "$screenshot")"
  write_capture_geometry_json "$scenario" "$screenshot_relative" "$window_id" "$reader_metrics"
  echo "Captured Reader regression scenario $scenario screenshot:"
  echo "$screenshot"
}

capture_all_scenario_screenshots() {
  local count
  count="$(scenario_count)"
  for scenario in $(seq 1 "$count"); do
    capture_scenario_screenshot "$scenario"
  done
}

update_baseline() {
  [[ -n "$UPDATE_BASELINE_DIR" ]] || return 0
  mkdir -p "$UPDATE_BASELINE_DIR/screenshots"
  if compgen -G "$OUTPUT_DIR/screenshots/*.png" >/dev/null; then
    cp "$OUTPUT_DIR"/screenshots/*.png "$UPDATE_BASELINE_DIR/screenshots/"
  fi
  if compgen -G "$OUTPUT_DIR/screenshots/*.geometry.json" >/dev/null; then
    cp "$OUTPUT_DIR"/screenshots/*.geometry.json "$UPDATE_BASELINE_DIR/screenshots/"
  fi
  cp "$OUTPUT_DIR/manifest.txt" "$UPDATE_BASELINE_DIR/manifest.txt"
  cp "$OUTPUT_DIR/geometry-manifest.txt" "$UPDATE_BASELINE_DIR/geometry-manifest.txt"
  /usr/bin/swift - "$UPDATE_BASELINE_DIR" "$OUTPUT_DIR" "$MAX_DIFF_PIXELS" "$MAX_DIFF_RATIO" "$MAX_CHANNEL_DELTA" "${SCREENSHOT_NAMES[@]}" <<'SWIFT'
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 7,
      let maxDiffPixels = Int(arguments[3]),
      let maxDiffRatio = Double(arguments[4]),
      let maxAllowedChannelDelta = Int(arguments[5]) else {
    fputs("usage: swift baselineDir outputDir maxDiffPixels maxDiffRatio maxChannelDelta screenshotName...\n", stderr)
    exit(2)
}

let baselineDir = URL(fileURLWithPath: arguments[1])
let outputDir = arguments[2]
let screenshotNames = Array(arguments.dropFirst(6)).map { "screenshots/\($0)" }
let policy: [String: Any] = [
    "schemaVersion": 1,
    "createdAt": ISO8601DateFormatter().string(from: Date()),
    "sourceOutput": outputDir,
    "requiredScreenshots": screenshotNames,
    "thresholds": [
        "maxDiffPixels": maxDiffPixels,
        "maxDiffRatio": maxDiffRatio,
        "maxChannelDelta": maxAllowedChannelDelta
    ],
    "passCondition": "A changed screenshot passes only when either differingPixels <= maxDiffPixels or diffRatio <= maxDiffRatio, and maxChannelDelta is not exceeded. Defaults require exact pixel equality."
]
let data = try JSONSerialization.data(withJSONObject: policy, options: [.prettyPrinted, .sortedKeys])
try data.write(to: baselineDir.appendingPathComponent("baseline-policy.json"))
SWIFT
  echo "Updated Reader regression baseline:"
  echo "$UPDATE_BASELINE_DIR"
}

compare_baseline() {
  [[ -n "$COMPARE_BASELINE_DIR" ]] || return 0
  local compare_names=()
  if [[ "$SMOKE_CAPTURE" -eq 1 ]]; then
    compare_names=("00-reader-regression-lab.png")
  elif [[ "$SCENARIO_CAPTURE" == "all" ]]; then
    compare_names=("${SCREENSHOT_NAMES[@]}")
  elif [[ -n "$SCENARIO_CAPTURE" ]]; then
    compare_names=("$(scenario_screenshot_name "$SCENARIO_CAPTURE")")
  else
    compare_names=("${SCREENSHOT_NAMES[@]}")
  fi

  /usr/bin/swift - "$COMPARE_BASELINE_DIR" "$OUTPUT_DIR" "$MAX_DIFF_PIXELS" "$MAX_DIFF_RATIO" "$MAX_CHANNEL_DELTA" "${compare_names[@]}" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count >= 7,
      let maxDiffPixels = Int(arguments[3]),
      let maxDiffRatio = Double(arguments[4]),
      let maxAllowedChannelDelta = Int(arguments[5]) else {
    fputs("usage: swift baselineDir outputDir maxDiffPixels maxDiffRatio maxChannelDelta screenshotName...\n", stderr)
    exit(2)
}

let baselineDir = URL(fileURLWithPath: arguments[1])
let outputDir = URL(fileURLWithPath: arguments[2])
let screenshotNames = Array(arguments.dropFirst(6))

func imagePixels(_ url: URL) throws -> (width: Int, height: Int, pixels: [UInt8]) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ReaderBaselineDiff", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load image: \(url.path)"])
    }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ReaderBaselineDiff", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"])
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, pixels)
}

var results: [[String: Any]] = []
var failures = 0

for name in screenshotNames {
    let baselineURL = baselineDir.appendingPathComponent("screenshots").appendingPathComponent(name)
    let currentURL = outputDir.appendingPathComponent("screenshots").appendingPathComponent(name)
    var result: [String: Any] = ["screenshot": "screenshots/\(name)"]

    guard FileManager.default.fileExists(atPath: baselineURL.path) else {
        result["status"] = "missing-baseline"
        failures += 1
        results.append(result)
        continue
    }
    guard FileManager.default.fileExists(atPath: currentURL.path) else {
        result["status"] = "missing-current"
        failures += 1
        results.append(result)
        continue
    }

    do {
        let baseline = try imagePixels(baselineURL)
        let current = try imagePixels(currentURL)
        result["baselinePixels"] = ["width": baseline.width, "height": baseline.height]
        result["currentPixels"] = ["width": current.width, "height": current.height]

        guard baseline.width == current.width, baseline.height == current.height else {
            result["status"] = "dimension-mismatch"
            failures += 1
            results.append(result)
            continue
        }

        var differingPixels = 0
        var maxChannelDelta = 0
        var channelDeltaTotal = 0
        let totalPixels = baseline.width * baseline.height
        for index in stride(from: 0, to: baseline.pixels.count, by: 4) {
            let dr = abs(Int(baseline.pixels[index]) - Int(current.pixels[index]))
            let dg = abs(Int(baseline.pixels[index + 1]) - Int(current.pixels[index + 1]))
            let db = abs(Int(baseline.pixels[index + 2]) - Int(current.pixels[index + 2]))
            let da = abs(Int(baseline.pixels[index + 3]) - Int(current.pixels[index + 3]))
            let delta = max(max(dr, dg), max(db, da))
            if delta > 0 {
                differingPixels += 1
                maxChannelDelta = max(maxChannelDelta, delta)
                channelDeltaTotal += dr + dg + db + da
            }
        }

        let diffRatio = totalPixels > 0 ? Double(differingPixels) / Double(totalPixels) : 0
        let passesPixelThreshold = differingPixels <= maxDiffPixels || diffRatio <= maxDiffRatio
        let passesChannelThreshold = maxChannelDelta <= maxAllowedChannelDelta
        let passesThreshold = passesPixelThreshold && passesChannelThreshold
        result["status"] = if differingPixels == 0 {
            "match"
        } else if passesThreshold {
            "within-threshold"
        } else {
            "different"
        }
        result["totalPixels"] = totalPixels
        result["differingPixels"] = differingPixels
        result["diffRatio"] = diffRatio
        result["maxChannelDelta"] = maxChannelDelta
        result["channelDeltaTotal"] = channelDeltaTotal
        if !passesThreshold {
            failures += 1
        }
    } catch {
        result["status"] = "error"
        result["error"] = error.localizedDescription
        failures += 1
    }
    results.append(result)
}

let report: [String: Any] = [
    "schemaVersion": 1,
    "createdAt": ISO8601DateFormatter().string(from: Date()),
    "baseline": baselineDir.path,
    "output": outputDir.path,
    "policy": [
        "maxDiffPixels": maxDiffPixels,
        "maxDiffRatio": maxDiffRatio,
        "maxChannelDelta": maxAllowedChannelDelta,
        "passCondition": "A changed screenshot passes only when either differingPixels <= maxDiffPixels or diffRatio <= maxDiffRatio, and maxChannelDelta is not exceeded. Defaults require exact pixel equality."
    ],
    "failureCount": failures,
    "results": results
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputDir.appendingPathComponent("baseline-report.json"))

print("Reader baseline comparison report:")
print(outputDir.appendingPathComponent("baseline-report.json").path)
print("failures: \(failures)")
exit(failures == 0 ? 0 : 1)
SWIFT
}

python3 "$ROOT_DIR/script/generate_reader_fixtures.py" --output "$FIXTURE_DIR" >/tmp/hoshi-reader-fixtures.txt
mkdir -p "$OUTPUT_DIR/screenshots"

{
  echo "# Reader Regression Capture"
  echo
  echo "Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "This run directory was created by the Reader regression capture harness."
  echo "Fixture EPUBs were generated before this manifest was written."
  if [[ "$SMOKE_CAPTURE" -eq 1 ]]; then
    echo "A smoke screenshot of the Debug-only Reader Regression Lab was captured."
    echo "A desktop/window geometry sidecar JSON was written next to the screenshot."
    echo "Smoke captures can be compared against a smoke baseline with the configured pixel-diff policy."
  elif [[ "$SCENARIO_CAPTURE" == "all" ]]; then
    echo "Reader screenshots for all planned scenarios were captured."
    echo "Geometry sidecar JSON files with desktop/window and Reader metrics were written next to the screenshots."
    echo "JavaScript scroll/selection/popup/Sasayaki metrics and pixel-diff comparison are available for this run."
  elif [[ -n "$SCENARIO_CAPTURE" ]]; then
    echo "A Reader screenshot for scenario $SCENARIO_CAPTURE was captured."
    echo "A geometry sidecar JSON with desktop/window and Reader metrics was written next to the screenshot."
    echo "JavaScript scroll/selection/popup/Sasayaki metrics and pixel-diff comparison are available for this run."
  else
    echo "Automatic UI driving and per-scenario screenshots are intentionally not implemented in plan-only mode."
  fi
  echo
  echo "Open the Debug-only lab:"
  echo
  echo '```bash'
  echo './script/build_and_run_native.sh --reader-regression-lab'
  echo '```'
  echo
  echo "In the lab, select each screenshot scenario. The lab imports the matching fixture and applies temporary Reader settings before opening Reader."
  echo
  echo "Generated fixtures:"
  while IFS= read -r fixture; do
    echo "- $fixture"
  done </tmp/hoshi-reader-fixtures.txt
  echo
  echo "Planned screenshots:"
  if [[ "$SMOKE_CAPTURE" -eq 1 ]]; then
    echo "- screenshots/00-reader-regression-lab.png"
    echo "- screenshots/00-reader-regression-lab.geometry.json"
  elif [[ "$SCENARIO_CAPTURE" == "all" ]]; then
    :
  elif [[ -n "$SCENARIO_CAPTURE" ]]; then
    screenshot_name="$(scenario_screenshot_name "$SCENARIO_CAPTURE")"
    echo "- screenshots/$screenshot_name"
    echo "- screenshots/${screenshot_name%.png}.geometry.json"
  fi
  for name in "${SCREENSHOT_NAMES[@]}"; do
    echo "- screenshots/$name"
  done
} > "$OUTPUT_DIR/README.md"

{
  for name in "${SCREENSHOT_NAMES[@]}"; do
    echo "screenshots/$name"
  done
} > "$OUTPUT_DIR/manifest.txt"

{
  for name in "${SCREENSHOT_NAMES[@]}"; do
    echo "screenshots/${name%.png}.geometry.json"
  done
} > "$OUTPUT_DIR/geometry-manifest.txt"

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  echo "Created Reader regression plan directory:"
  echo "$OUTPUT_DIR"
  echo "Open the lab with: ./script/build_and_run_native.sh --reader-regression-lab"
  echo "Next step: run a smoke capture with: script/capture_reader_regression.sh --smoke-capture"
elif [[ "$SMOKE_CAPTURE" -eq 1 ]]; then
  capture_smoke_screenshot
elif [[ "$SCENARIO_CAPTURE" == "all" ]]; then
  capture_all_scenario_screenshots
elif [[ -n "$SCENARIO_CAPTURE" ]]; then
  capture_scenario_screenshot "$SCENARIO_CAPTURE"
fi

update_baseline
compare_baseline
