#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "obsolete Reader visual harness path still exists: $path"
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if rg -F -q -- "$text" "$file"; then
    fail "$file still contains obsolete Reader visual harness wiring: $text"
  fi
}

assert_contains() {
  local file="$1"
  local text="$2"
  rg -F -q -- "$text" "$file" || fail "$file is missing Reader contract wiring: $text"
}

assert_absent "$ROOT_DIR/Features/Reader/ReaderRegressionLab"
assert_absent "$ROOT_DIR/script/capture_reader_regression.sh"
assert_absent "$ROOT_DIR/script/generate_reader_fixtures.py"
assert_absent "$ROOT_DIR/script/verify_reader_ci_contract.sh"
assert_absent "$ROOT_DIR/testdata/reader-baselines"
assert_absent "$ROOT_DIR/testdata/reader-fixtures-src"

assert_not_contains "$ROOT_DIR/NativeMac/NativeMacRootView.swift" "ReaderRegression"
assert_not_contains "$ROOT_DIR/NativeMac/NativeReuseViews.swift" "ReaderRegression"
assert_not_contains "$ROOT_DIR/NativeMac/NativeReaderView.swift" "reader-regression"
assert_not_contains "$ROOT_DIR/Features/Bookshelf/BookshelfView.swift" "ReaderRegression"
assert_not_contains "$ROOT_DIR/Features/Bookshelf/BookshelfViewModel.swift" "importReaderRegressionFixture"
assert_not_contains "$ROOT_DIR/script/build_and_run_native.sh" "reader-regression-lab"

WORKFLOW="$ROOT_DIR/.github/workflows/reader-contract.yml"
assert_contains "$WORKFLOW" "name: Reader Contract"
assert_contains "$WORKFLOW" "./script/verify_reader_harness.sh"
assert_not_contains "$WORKFLOW" "capture_reader_regression"
assert_not_contains "$WORKFLOW" "upload-artifact"

echo "Reader actual-data contract checks passed"
