#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Niratan.xcodeproj/project.pbxproj"
LIGHT_SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan.xcscheme"
VIDEO_SCHEME="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan Video.xcscheme"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_mac.sh"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release-mac.yml"
INFO_PLIST="$ROOT_DIR/HoshiReader-Info.plist"
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

[[ -f "$VIDEO_SCHEME" ]] || fail "Video scheme is missing"

assert_contains "$PROJECT_FILE" "Debug-Video"
assert_contains "$PROJECT_FILE" "Release-Video"
assert_contains "$PROJECT_FILE" "HOSHI_VIDEO"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Video;"
assert_contains "$PROJECT_FILE" "HOSHI_BUILD_VARIANT = Light;"
assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = moe.shishamo.hoshi;"
assert_contains "$PROJECT_FILE" '$(SRCROOT)/Vendor/libmpv/include/mpv'
assert_contains "$MPV_CLIENT" 'moe.shishamo.hoshi.video.mpv'
assert_contains "$PROJECT_FILE" 'Video/VideoAmbientBackdrop.swift'
assert_contains "$PROJECT_FILE" 'Video/VideoAmbientBackdropModel.swift'
assert_not_contains "$MPV_CLIENT" 'de.manhhao.hoshi.video.mpv'
assert_not_contains "$PROJECT_FILE" 'Vendor/iina/deps/include'
assert_contains "$INFO_PLIST" "<key>HoshiBuildVariant</key>"
assert_contains "$INFO_PLIST" '<string>$(HOSHI_BUILD_VARIANT)</string>'

assert_contains "$BOOTSTRAP_SCRIPT" 'IINA_ARTIFACT_VERSION="1.4.2"'
assert_contains "$BOOTSTRAP_SCRIPT" 'IINA_SOURCE_REVISION="f6755d24ae461ce27c08814b9babe566ab43c80a"'
assert_contains "$BOOTSTRAP_SCRIPT" 'EXPECTED_FILE_LIST_SHA256="665da1e0506eeb952c0870153265df23602a9ef35e45290c8218dccc50a6da96"'
assert_contains "$BOOTSTRAP_SCRIPT" 'deps/include/libavcodec'
assert_contains "$BOOTSTRAP_SCRIPT" 'deps/include/libavformat'
assert_contains "$BOOTSTRAP_SCRIPT" 'deps/include/libavutil'
assert_contains "$BOOTSTRAP_SCRIPT" '"$INCLUDE_ROOT/mpv/libavcodec/version_major.h"'
assert_contains "$BOOTSTRAP_SCRIPT" 'downloaded_sha256'
assert_contains "$BOOTSTRAP_SCRIPT" 'upstream_library="$library.upstream"'
assert_contains "$BOOTSTRAP_SCRIPT" 'checksum_target="$upstream_library"'
assert_contains "$BOOTSTRAP_SCRIPT" '-Wl,-no_uuid'
assert_not_contains "$BOOTSTRAP_SCRIPT" 'iina/develop'
assert_contains "$DEPENDENCY_MANIFEST" '"artifactVersion": "1.4.2"'
assert_contains "$DEPENDENCY_MANIFEST" '"headersRevision": "f6755d24ae461ce27c08814b9babe566ab43c80a"'
assert_contains "$DEPENDENCY_CHECKSUMS" '312aeb9871b82984a384d6764f7667f1c114f283e8c6e6975466dbe63512157a  libavcodec.61.dylib'
assert_contains "$DEPENDENCY_CHECKSUMS" 'a43adb2d49ab7a1e362a684427a7bbb033ebb50e311aab87bf138f0df7ec0e29  libavformat.61.dylib'
assert_contains "$DEPENDENCY_CHECKSUMS" 'dbdc1c952fb7f0983c02f4759544d331fac62568e8dcb9c1a096e300f6c43118  libavutil.59.dylib'
assert_contains "$DEPENDENCY_CHECKSUMS" 'e862b11fd8b0bad5d9ab371ff763cfcbc28dc2e2a9feb20d2f010c363e3c5293  libmpv.2.dylib'
[[ "$(wc -l < "$DEPENDENCY_CHECKSUMS" | tr -d ' ')" == "71" ]] \
  || fail "$DEPENDENCY_CHECKSUMS must lock all 71 IINA 1.4.2 dylibs"
assert_contains "$MPV_CLIENT" '#include <libavcodec/version_major.h>'
assert_contains "$MPV_CLIENT" '#include <libavformat/version_major.h>'
assert_contains "$MPV_CLIENT" '#include <libavutil/version.h>'
assert_contains "$MPV_CLIENT" 'HSMpvValidateFFmpegRuntimeVersions(error)'
assert_contains "$MPV_CLIENT" 'codecMajor != LIBAVCODEC_VERSION_MAJOR'
assert_contains "$MPV_CLIENT" 'formatMajor != LIBAVFORMAT_VERSION_MAJOR'
assert_contains "$MPV_CLIENT" 'utilMajor != LIBAVUTIL_VERSION_MAJOR'

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
