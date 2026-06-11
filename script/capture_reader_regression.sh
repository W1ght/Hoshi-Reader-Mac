#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$ROOT_DIR/artifacts/reader-regression/$TIMESTAMP"
FIXTURE_DIR="$ROOT_DIR/testdata/reader-fixtures"
PLAN_ONLY=1

usage() {
  cat <<'EOF'
usage: script/capture_reader_regression.sh [--output DIR] [--fixtures DIR] [--plan-only]

Generates Reader fixtures, creates a Reader regression run directory, and writes
the planned screenshot manifest. This harness can launch the Debug-only Reader
Regression Lab, but it does not yet drive UI clicks or capture screenshots
automatically.
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

python3 "$ROOT_DIR/script/generate_reader_fixtures.py" --output "$FIXTURE_DIR" >/tmp/hoshi-reader-fixtures.txt
mkdir -p "$OUTPUT_DIR/screenshots"

{
  echo "# Reader Regression Capture"
  echo
  echo "Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "This run directory was created by the Reader regression capture harness."
  echo "Fixture EPUBs were generated before this manifest was written."
  echo "Automatic UI driving and screenshots are intentionally not implemented yet."
  echo
  echo "Open the Debug-only lab:"
  echo
  echo '```bash'
  echo './script/build_and_run_catalyst.sh --reader-regression-lab'
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
  for name in "${SCREENSHOT_NAMES[@]}"; do
    echo "- screenshots/$name"
  done
} > "$OUTPUT_DIR/README.md"

{
  for name in "${SCREENSHOT_NAMES[@]}"; do
    echo "screenshots/$name"
  done
} > "$OUTPUT_DIR/manifest.txt"

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  echo "Created Reader regression plan directory:"
  echo "$OUTPUT_DIR"
  echo "Open the lab with: ./script/build_and_run_catalyst.sh --reader-regression-lab"
  echo "Next step: add app-driven screenshot capture on top of the deterministic lab scenarios."
fi
