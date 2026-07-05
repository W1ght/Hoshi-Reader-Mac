#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Niratan.xcodeproj/project.pbxproj"
SCHEME_FILE="$ROOT_DIR/Niratan.xcodeproj/xcshareddata/xcschemes/Niratan.xcscheme"
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
assert_not_contains "$PROJECT_FILE" "Niratan Native"
assert_contains "$SCHEME_FILE" 'BuildableName = "Niratan.app"'
assert_contains "$SCHEME_FILE" 'BlueprintName = "Niratan"'

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
assert_contains "$ROOT_DIR/script/package_mac.sh" 'SCHEME_NAME="Niratan"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'APP_VERSION="${VERSION%%-*}"'
assert_contains "$ROOT_DIR/script/package_mac.sh" '[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'APP_VERSION="${BASH_REMATCH[1]}"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'expected $APP_VERSION, got $INFO_VERSION'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'SIGNING_IDENTITY="${HOSHI_RELEASE_SIGNING_IDENTITY:--}"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$item"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_BUNDLE"'
assert_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --verify --deep --strict "$APP_BUNDLE"'
assert_not_contains "$ROOT_DIR/script/package_mac.sh" 'codesign --remove-signature'
assert_not_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "notary"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'HOSHI_RELEASE_SIGNING_IDENTITY: ${{ secrets.HOSHI_RELEASE_SIGNING_IDENTITY }}'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'HOSHI_RELEASE_CERTIFICATE_P12_BASE64: ${{ secrets.HOSHI_RELEASE_CERTIFICATE_P12_BASE64 }}'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'security import "$certificate_path"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "No release signing certificate secret configured; package_mac.sh will use ad-hoc signing."
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "signed with the configured macOS release certificate"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" "ad-hoc signed native macOS build"
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'prerelease="true"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" '--prerelease="$prerelease"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'artifact_mode="single-dmg"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'git fetch --force origin "refs/tags/${GITHUB_REF_NAME}:refs/tags/${GITHUB_REF_NAME}"'
assert_contains "$ROOT_DIR/.github/workflows/release-mac.yml" 'release/niratan.dmg'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'APP_VERSION="${VERSION%%-*}"'
assert_contains "$ROOT_DIR/script/release_mac.sh" '[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'APP_VERSION="${BASH_REMATCH[1]}"'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'HOSHI_RELEASE_ARTIFACT_MODE:-standard'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'Release-Artifact-Mode: $RELEASE_ARTIFACT_MODE'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'if git diff --cached --quiet; then'
assert_contains "$ROOT_DIR/script/release_mac.sh" 'chore(release): bump version to $VERSION'
assert_contains "$BUILD_RUN_SCRIPT" '--open-url|open-url)'
assert_contains "$BUILD_RUN_SCRIPT" 'open_with_env -a "$APP_BUNDLE" "$url"'
assert_contains "$BUILD_RUN_SCRIPT" 'EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"'
assert_contains "$BUILD_RUN_SCRIPT" 'Built app bundle identifier mismatch: expected $EXPECTED_BUNDLE_ID, got $bundle_identifier.'
assert_contains "$BUILD_RUN_SCRIPT" 'LC_ALL=C pgrep -f -- "$APP_EXECUTABLE"'
assert_not_contains "$BUILD_RUN_SCRIPT" 'pgrep -x "$APP_NAME"'

echo "Native release contract checks passed"
