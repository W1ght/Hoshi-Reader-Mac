#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Niratan.xcodeproj/project.pbxproj"
SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan.xcscheme"
RETIRED_VIDEO_SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan Video.xcscheme"
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run_native.sh"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_mac.sh"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release-mac.yml"
BOOTSTRAP_SCRIPT="$ROOT_DIR/script/bootstrap_libmpv.sh"
DEPENDENCY_MANIFEST="$ROOT_DIR/Vendor/libmpv/manifest.json"
DEPENDENCY_CHECKSUMS="$ROOT_DIR/script/libmpv-1.4.2.sha256"
MPV_CLIENT="$ROOT_DIR/Features/Video/Playback/HSMpvClient.mm"

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

[[ ! -e "$RETIRED_VIDEO_SCHEME" ]] || fail "The retired Video scheme still exists"

assert_contains "$SCHEME" 'buildConfiguration = "Debug"'
assert_contains "$SCHEME" 'buildConfiguration = "Release"'
assert_not_contains "$PROJECT_FILE" "Debug-Video"
assert_not_contains "$PROJECT_FILE" "Release-Video"
assert_not_contains "$PROJECT_FILE" "HOSHI_VIDEO"
assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = moe.shishamo.hoshi;"
assert_contains "$PROJECT_FILE" "Manga/SuwayomiClient.swift"
assert_contains "$PROJECT_FILE" "Manga/SuwayomiSourceView.swift"
assert_not_contains "$PROJECT_FILE" "Manga Source Runtime.xpc"
assert_not_contains "$PROJECT_FILE" "SwiftSoup"
assert_contains "$PROJECT_FILE" '$(SRCROOT)/Vendor/libmpv/include/mpv'
assert_contains "$PROJECT_FILE" 'LIBRARY_SEARCH_PATHS = "$(SRCROOT)/Vendor/libmpv/lib";'
assert_contains "$PROJECT_FILE" 'OTHER_LDFLAGS = "-lmpv";'
assert_contains "$PROJECT_FILE" 'SWIFT_OBJC_BRIDGING_HEADER = "Features/Video/Playback/HoshiVideo-Bridging-Header.h";'
assert_contains "$MPV_CLIENT" 'moe.shishamo.hoshi.video.mpv'
assert_not_contains "$MPV_CLIENT" 'de.manhhao.hoshi.video.mpv'
assert_not_contains "$MPV_CLIENT" "HOSHI_VIDEO"
assert_not_contains "$PROJECT_FILE" 'Vendor/iina/deps/include'

assert_contains "$BOOTSTRAP_SCRIPT" 'IINA_ARTIFACT_VERSION="1.4.2"'
assert_contains "$BOOTSTRAP_SCRIPT" 'IINA_SOURCE_REVISION="f6755d24ae461ce27c08814b9babe566ab43c80a"'
assert_contains "$BOOTSTRAP_SCRIPT" 'EXPECTED_FILE_LIST_SHA256="665da1e0506eeb952c0870153265df23602a9ef35e45290c8218dccc50a6da96"'
assert_contains "$DEPENDENCY_MANIFEST" '"artifactVersion": "1.4.2"'
[[ "$(wc -l < "$DEPENDENCY_CHECKSUMS" | tr -d ' ')" == "71" ]] \
  || fail "$DEPENDENCY_CHECKSUMS must lock all 71 IINA 1.4.2 dylibs"

assert_contains "$BUILD_SCRIPT" 'SCHEME_NAME="Niratan"'
assert_contains "$BUILD_SCRIPT" 'CONFIGURATION="Debug"'
assert_contains "$BUILD_SCRIPT" 'bash "$ROOT_DIR/script/bootstrap_libmpv.sh"'
assert_not_contains "$BUILD_SCRIPT" 'VARIANT='
assert_not_contains "$BUILD_SCRIPT" 'Debug-Video'

assert_contains "$PACKAGE_SCRIPT" 'SCHEME_NAME="Niratan"'
assert_contains "$PACKAGE_SCRIPT" 'CONFIGURATION="Release"'
assert_contains "$PACKAGE_SCRIPT" 'ARTIFACT_NAME="Niratan-Mac-$VERSION"'
assert_contains "$PACKAGE_SCRIPT" 'verify_full_bundle'
assert_contains "$PACKAGE_SCRIPT" 'YouTubeKit_YouTubeKit.bundle'
assert_not_contains "$PACKAGE_SCRIPT" 'VARIANT='
assert_not_contains "$PACKAGE_SCRIPT" 'Niratan-Mac-Video-'
assert_contains "$PACKAGE_SCRIPT" "grep -E -q '/opt/homebrew|/usr/local'"
assert_contains "$PACKAGE_SCRIPT" 'codesign --verify --deep --strict "$APP_BUNDLE"'
assert_not_contains "$PACKAGE_SCRIPT" 'codesign --remove-signature'

assert_not_contains "$RELEASE_WORKFLOW" 'variant: light'
assert_not_contains "$RELEASE_WORKFLOW" 'variant: video'
assert_not_contains "$RELEASE_WORKFLOW" 'Niratan-Mac-Video-'
assert_contains "$RELEASE_WORKFLOW" 'script/package_mac.sh "${{ steps.version.outputs.version }}"'
assert_contains "$RELEASE_WORKFLOW" 'actions/upload-artifact@v4'
assert_contains "$RELEASE_WORKFLOW" 'actions/download-artifact@v4'
assert_contains "$RELEASE_WORKFLOW" '--prerelease="$prerelease"'

if rg -q '#if[[:space:]]+HOSHI_VIDEO|#elseif[[:space:]]+HOSHI_VIDEO' \
  "$ROOT_DIR/Core" "$ROOT_DIR/Features" "$ROOT_DIR/Models" "$ROOT_DIR/NativeMac" "$ROOT_DIR/Util"; then
  fail "Source code still contains HOSHI_VIDEO conditional compilation"
fi

echo "Full-build contract checks passed"
