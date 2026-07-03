#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Niratan.xcodeproj/project.pbxproj"
LIGHT_SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan.xcscheme"
VIDEO_SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan Video.xcscheme"
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
  grep -F -q -- "$text" "$file" || fail "$file is missing: $text"
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if grep -F -q -- "$text" "$file"; then
    fail "$file unexpectedly contains: $text"
  fi
}

[[ -f "$VIDEO_SCHEME" ]] || fail "Video scheme is missing"

assert_contains "$PROJECT_FILE" "Debug-Video"
assert_contains "$PROJECT_FILE" "Release-Video"
assert_contains "$PROJECT_FILE" "HOSHI_VIDEO"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Video;"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Light;"
assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = moe.shishamo.hoshi;"
assert_contains "$ROOT_DIR/Features/Video/Playback/HSMpvClient.mm" 'moe.shishamo.hoshi.video.mpv'
assert_contains "$PROJECT_FILE" 'Video/VideoAmbientBackdrop.swift'
assert_contains "$PROJECT_FILE" 'Video/VideoAmbientBackdropModel.swift'
assert_not_contains "$ROOT_DIR/Features/Video/Playback/HSMpvClient.mm" 'de.manhhao.hoshi.video.mpv'
assert_contains "$INFO_PLIST" "<key>HoshiBuildVariant</key>"
assert_contains "$INFO_PLIST" '<string>$(HOSHI_BUILD_VARIANT)</string>'

assert_contains "$LIGHT_SCHEME" 'buildConfiguration = "Debug"'
assert_contains "$VIDEO_SCHEME" 'buildConfiguration = "Debug-Video"'
assert_contains "$VIDEO_SCHEME" 'buildConfiguration = "Release-Video"'

assert_contains "$PACKAGE_SCRIPT" 'VARIANT="${2:-light}"'
assert_contains "$PACKAGE_SCRIPT" 'Release-Video'
assert_contains "$PACKAGE_SCRIPT" 'Niratan-Mac-Video-'
assert_contains "$PACKAGE_SCRIPT" 'verify_video_bundle'
assert_contains "$PACKAGE_SCRIPT" '-sdk macosx'
assert_not_contains "$PACKAGE_SCRIPT" '-destination "generic/platform=macOS"'
assert_contains "$PACKAGE_SCRIPT" "grep -E -q '/opt/homebrew|/usr/local'"
assert_not_contains "$PACKAGE_SCRIPT" "rg -q '/opt/homebrew|/usr/local'"
assert_contains "$PACKAGE_SCRIPT" 'codesign --verify --deep --strict "$APP_BUNDLE"'
assert_not_contains "$PACKAGE_SCRIPT" 'codesign --remove-signature'
assert_contains "$ROOT_DIR/script/build_and_run_native.sh" 'codesign_local_debug_bundle'
assert_contains "$ROOT_DIR/script/build_and_run_native.sh" 'local_debug_codesign_identity'
assert_contains "$ROOT_DIR/script/build_and_run_native.sh" 'Apple Development:'
assert_contains "$ROOT_DIR/script/build_and_run_native.sh" 'codesign --force --sign "$signing_identity"'
assert_contains "$ROOT_DIR/script/build_and_run_native.sh" 'codesign --verify --deep --strict "$APP_BUNDLE"'

assert_contains "$RELEASE_WORKFLOW" 'variant: light'
assert_contains "$RELEASE_WORKFLOW" 'variant: video'
assert_contains "$RELEASE_WORKFLOW" 'script/package_mac.sh "${{ steps.version.outputs.version }}" "${{ matrix.variant }}"'
assert_contains "$RELEASE_WORKFLOW" 'needs: build-mac'
assert_contains "$RELEASE_WORKFLOW" 'actions/upload-artifact@v4'
assert_contains "$RELEASE_WORKFLOW" 'actions/download-artifact@v4'
assert_contains "$RELEASE_WORKFLOW" 'Niratan-Mac-Video-'
assert_contains "$RELEASE_WORKFLOW" '--prerelease="$prerelease"'

assert_not_contains "$LIGHT_SCHEME" "HOSHI_VIDEO"

echo "Video variant contract checks passed"
