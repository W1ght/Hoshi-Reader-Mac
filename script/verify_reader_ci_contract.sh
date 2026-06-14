#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/reader-regression.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  [[ -f "$WORKFLOW" ]] || fail "Reader regression workflow is missing"
  rg -F -q -- "$text" "$WORKFLOW" || fail "$WORKFLOW is missing: $text"
}

assert_contains "runs-on: macos-26"
assert_contains "CODE_SIGNING_ALLOWED=NO"
assert_contains "./script/verify_reader_harness.sh"
assert_contains "--output artifacts/reader-regression/ci-plan"
assert_contains "actions/upload-artifact@v4"
assert_contains "path: artifacts/reader-regression/ci-plan"

echo "Reader CI contract checks passed"
