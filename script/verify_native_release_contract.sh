#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Hoshi Reader.xcodeproj/project.pbxproj"
SCHEME_FILE="$ROOT_DIR/Hoshi Reader.xcodeproj/xcshareddata/xcschemes/Hoshi Reader.xcscheme"
BUILD_RUN_SCRIPT="$ROOT_DIR/script/build_and_run_native.sh"

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
    fail "$file still contains: $text"
  fi
}

assert_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "legacy path still exists: $path"
}

assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = moe.shishamo.hoshi;"
assert_not_contains "$PROJECT_FILE" "de.manhhao.hoshi.native"
assert_not_contains "$PROJECT_FILE" "SUPPORTS_MACCATALYST"
assert_not_contains "$PROJECT_FILE" "ShareExtension"
assert_not_contains "$PROJECT_FILE" "Hoshi Reader Native"
assert_contains "$SCHEME_FILE" 'BuildableName = "Hoshi Reader.app"'
assert_contains "$SCHEME_FILE" 'BlueprintName = "Hoshi Reader"'

assert_absent "$ROOT_DIR/App"
assert_absent "$ROOT_DIR/ShareExtension"
assert_absent "$ROOT_DIR/script/build_and_run_catalyst.sh"
assert_absent "$ROOT_DIR/Features/Reader/ReaderView/ReaderView.swift"
assert_absent "$ROOT_DIR/Features/Reader/ReaderView/ReaderViewModel.swift"
assert_absent "$ROOT_DIR/Features/Reader/ReaderView/FullscreenImageView.swift"
assert_absent "$ROOT_DIR/Features/Reader/ReaderWebView/ReaderWebView.swift"
assert_absent "$ROOT_DIR/Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift"

assert_not_contains "$ROOT_DIR/script/package_mac.sh" "Mac Catalyst"
assert_not_contains "$ROOT_DIR/script/package_mac.sh" "Release-maccatalyst"
assert_contains "$ROOT_DIR/script/package_mac.sh" 'SCHEME_NAME="Hoshi Reader"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'APP_VERSION="${VERSION%%-*}"'
assert_contains "$ROOT_DIR/script/package_mac.sh" '[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'APP_VERSION="${BASH_REMATCH[1]}"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'expected $APP_VERSION, got $INFO_VERSION'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --force --sign - --timestamp=none "$item"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --force --sign - --timestamp=none "$APP_BUNDLE"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --verify --deep --strict "$APP_BUNDLE"'
assert_not_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --remove-signature'
assert_not_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "notary"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "ad-hoc signed"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'prerelease="true"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" '--prerelease="$prerelease"'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'APP_VERSION="${VERSION%%-*}"'
assert_contains "$ROOT_DIR/script/release_mac.sh" '[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'APP_VERSION="${BASH_REMATCH[1]}"'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'if git diff --cached --quiet; then'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'chore(release): bump version to $VERSION'
assert_contains "$BUILD_RUN_SCRIPT" '--open-url|open-url)'
assert_contains "$BUILD_RUN_SCRIPT" '/usr/bin/open -a "$APP_BUNDLE" "$url"'
assert_contains "$BUILD_RUN_SCRIPT" 'EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"'
assert_contains "$BUILD_RUN_SCRIPT" 'Built app bundle identifier mismatch: expected $EXPECTED_BUNDLE_ID, got $bundle_identifier.'
assert_contains "$BUILD_RUN_SCRIPT" 'pgrep -f -- "$APP_EXECUTABLE"'
assert_not_contains "$BUILD_RUN_SCRIPT" 'pgrep -x "$APP_NAME"'

echo "Native release contract checks passed"
