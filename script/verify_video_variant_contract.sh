#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Hoshi Reader.xcodeproj/project.pbxproj"
LIGHT_SCHEME="$ROOT_DIR/Hoshi Reader.xcodeproj/xcshareddata/xcschemes/Hoshi Reader.xcscheme"
VIDEO_SCHEME="$ROOT_DIR/Hoshi Reader.xcodeproj/xcshareddata/xcschemes/Hoshi Reader Video.xcscheme"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_mac.sh"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release-mac.yml"
INFO_PLIST="$ROOT_DIR/HoshiReader-Info.plist"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local text="$2"
  rg -F -q -- "$text" "$file" || fail "$file is missing: $text"
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if rg -F -q -- "$text" "$file"; then
    fail "$file unexpectedly contains: $text"
  fi
}

[[ -f "$VIDEO_SCHEME" ]] || fail "Video scheme is missing"

assert_contains "$PROJECT_FILE" "Debug-Video"
assert_contains "$PROJECT_FILE" "Release-Video"
assert_contains "$PROJECT_FILE" "HOSHI_VIDEO"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Video;"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Light;"
assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = de.manhhao.hoshi;"
assert_contains "$INFO_PLIST" "<key>HoshiBuildVariant</key>"
assert_contains "$INFO_PLIST" '<string>$(HOSHI_BUILD_VARIANT)</string>'

assert_contains "$LIGHT_SCHEME" 'buildConfiguration = "Debug"'
assert_contains "$VIDEO_SCHEME" 'buildConfiguration = "Debug-Video"'
assert_contains "$VIDEO_SCHEME" 'buildConfiguration = "Release-Video"'

assert_contains "$PACKAGE_SCRIPT" 'VARIANT="${2:-light}"'
assert_contains "$PACKAGE_SCRIPT" 'Release-Video'
assert_contains "$PACKAGE_SCRIPT" 'Hoshi-Reader-Mac-Video-'
assert_contains "$PACKAGE_SCRIPT" 'verify_video_bundle'

assert_contains "$RELEASE_WORKFLOW" 'script/package_mac.sh "${{ steps.version.outputs.version }}" light'
assert_contains "$RELEASE_WORKFLOW" 'script/package_mac.sh "${{ steps.version.outputs.version }}" video'
assert_contains "$RELEASE_WORKFLOW" 'Hoshi-Reader-Mac-Video-'

assert_not_contains "$LIGHT_SCHEME" "HOSHI_VIDEO"

echo "Video variant contract checks passed"
