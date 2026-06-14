#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ENTRY="$ROOT_DIR/NativeMac/HoshiNativeMacApp.swift"
BOOK_STORAGE="$ROOT_DIR/Core/BookStorage.swift"
USER_CONFIG="$ROOT_DIR/Core/UserConfig.swift"
TOKEN_STORAGE="$ROOT_DIR/Features/Sync/TokenStorage.swift"
PROJECT_FILE="$ROOT_DIR/Hoshi Reader.xcodeproj/project.pbxproj"

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
    fail "$file still contains destructive upgrade behavior: $text"
  fi
}

assert_contains "$PROJECT_FILE" "PRODUCT_BUNDLE_IDENTIFIER = de.manhhao.hoshi;"
assert_contains "$USER_CONFIG" "private static let defaults = UserDefaults.standard"
assert_contains "$TOKEN_STORAGE" 'private static let service = "de.manhhao.hoshi.google-drive"'
assert_contains "$TOKEN_STORAGE" "getLegacyKeychainValue(key)"
assert_not_contains "$APP_ENTRY" "TokenStorage.clearOldKeys()"
assert_not_contains "$TOKEN_STORAGE" "static func clearOldKeys()"

assert_contains "$BOOK_STORAGE" "for: .applicationSupportDirectory"
assert_contains "$BOOK_STORAGE" 'let items = ["Books", "Fonts", "Dictionaries", "Audio", "anki_words.json", "anki_config.json"]'
assert_contains "$BOOK_STORAGE" 'static let metadata = "metadata.json"'
assert_contains "$BOOK_STORAGE" 'static let bookmark = "bookmark.json"'
assert_contains "$BOOK_STORAGE" 'static let bookinfo = "bookinfo.json"'
assert_contains "$BOOK_STORAGE" 'static let statistics = "statistics.json"'
assert_contains "$BOOK_STORAGE" 'static let sasayakiMatch = "sasayaki_match.json"'
assert_contains "$BOOK_STORAGE" 'static let sasayakiPlayback = "sasayaki_playback.json"'
assert_contains "$BOOK_STORAGE" 'static let highlights = "highlights.json"'

echo "Native upgrade contract checks passed"
