#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="${TMPDIR:-/tmp}"
FIXTURE_ROOT="$(mktemp -d "${TEMP_ROOT%/}/niratan-build-cleanup-test.XXXXXX")"
ACTIVE_BUILD_PID=""

cleanup() {
  if [[ -n "$ACTIVE_BUILD_PID" ]]; then
    kill "$ACTIVE_BUILD_PID" >/dev/null 2>&1 || true
    wait "$ACTIVE_BUILD_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

require_path() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "FAIL: expected path to exist: $path" >&2
    exit 1
  }
}

require_missing() {
  local path="$1"
  [[ ! -e "$path" ]] || {
    echo "FAIL: expected path to be removed: $path" >&2
    exit 1
  }
}

mkdir -p "$FIXTURE_ROOT/script" "$FIXTURE_ROOT/.build" "$FIXTURE_ROOT/release"
cp "$SOURCE_ROOT/script/cleanup_build_artifacts.sh" "$FIXTURE_ROOT/script/"

mkdir -p \
  "$FIXTURE_ROOT/.build/xcode-derived-data" \
  "$FIXTURE_ROOT/.build/xcode-derived-data-current" \
  "$FIXTURE_ROOT/.build/xcode-derived-data-new" \
  "$FIXTURE_ROOT/.build/xcode-derived-data-old" \
  "$FIXTURE_ROOT/.build/xcode-source-packages" \
  "$FIXTURE_ROOT/release/Niratan-Mac-test"

touch -t 202601010101 "$FIXTURE_ROOT/.build/xcode-derived-data-old"
touch -t 202602020202 "$FIXTURE_ROOT/.build/xcode-derived-data-new"

HOSHI_BUILD_RETENTION_COUNT=1 \
  bash "$FIXTURE_ROOT/script/cleanup_build_artifacts.sh" \
    --prune \
    --protect "$FIXTURE_ROOT/.build/xcode-derived-data-current"

require_path "$FIXTURE_ROOT/.build/xcode-derived-data"
require_path "$FIXTURE_ROOT/.build/xcode-derived-data-current"
require_path "$FIXTURE_ROOT/.build/xcode-derived-data-new"
require_missing "$FIXTURE_ROOT/.build/xcode-derived-data-old"
require_path "$FIXTURE_ROOT/.build/xcode-source-packages"

mkdir -p "$FIXTURE_ROOT/.build/xcode-derived-data-active"
bash -c 'while true; do sleep 1; done' \
  "$FIXTURE_ROOT/.build/xcode-derived-data-active" &
ACTIVE_BUILD_PID=$!

bash "$FIXTURE_ROOT/script/cleanup_build_artifacts.sh" --all

require_missing "$FIXTURE_ROOT/.build/xcode-derived-data"
require_missing "$FIXTURE_ROOT/.build/xcode-derived-data-current"
require_missing "$FIXTURE_ROOT/.build/xcode-derived-data-new"
require_path "$FIXTURE_ROOT/.build/xcode-derived-data-active"
require_missing "$FIXTURE_ROOT/.build/xcode-source-packages"
require_missing "$FIXTURE_ROOT/release/Niratan-Mac-test"

kill "$ACTIVE_BUILD_PID"
wait "$ACTIVE_BUILD_PID" >/dev/null 2>&1 || true
ACTIVE_BUILD_PID=""

bash "$FIXTURE_ROOT/script/cleanup_build_artifacts.sh" --all
require_missing "$FIXTURE_ROOT/.build/xcode-derived-data-active"

echo "build artifact cleanup tests passed"
