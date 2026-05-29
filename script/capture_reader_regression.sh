#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$ROOT_DIR/artifacts/reader-regression/$TIMESTAMP"
PLAN_ONLY=1

usage() {
  cat <<'EOF'
usage: script/capture_reader_regression.sh [--output DIR] [--plan-only]

Creates a Reader regression run directory and planned screenshot manifest.
This skeleton does not yet drive the app or capture screenshots automatically.
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

mkdir -p "$OUTPUT_DIR/screenshots"

{
  echo "# Reader Regression Capture"
  echo
  echo "Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "This run directory was created by the capture skeleton."
  echo "Automatic app driving and screenshots are intentionally not implemented yet."
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
  echo "Next step: implement Debug-only Reader Regression Lab and app-driven screenshot capture."
fi
