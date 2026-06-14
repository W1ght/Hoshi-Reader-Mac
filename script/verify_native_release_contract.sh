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
  rg -F -q -- "$text" "$file" || fail "$file is missing: $text"
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if rg -F -q -- "$text" "$file"; then
    fail "$file still contains: $text"
  fi
}

assert_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "legacy path still exists: $path"
}

assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = de.manhhao.hoshi;"
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
assert_contains "$ROOT_DIR/script/package_mac.sh" 'EXPECTED_BUNDLE_ID="de.manhhao.hoshi"'
assert_not_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "notary"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "unsigned"
assert_contains "$ROOT_DIR/script/release_mac.sh" 'chore(release): bump version to $VERSION'
assert_contains "$BUILD_RUN_SCRIPT" '--open-url|open-url)'
assert_contains "$BUILD_RUN_SCRIPT" '/usr/bin/open -a "$APP_BUNDLE" "$url"'

echo "Native release contract checks passed"
