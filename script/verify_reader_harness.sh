#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking Reader fixture generator syntax"
python3 -m py_compile script/generate_reader_fixtures.py

echo "==> Checking Reader screenshot capture harness syntax"
bash -n script/capture_reader_regression.sh

echo "==> Checking Reader baseline threshold validation"
if bash script/capture_reader_regression.sh \
  --fixtures /tmp/hoshi-reader-invalid-ratio-fixtures \
  --output /tmp/hoshi-reader-invalid-ratio-output \
  --max-diff-ratio 1.1 \
  --plan-only >/tmp/hoshi-reader-invalid-ratio.log 2>&1; then
  echo "Reader capture harness should reject max diff ratios above 1" >&2
  exit 1
fi
if bash script/capture_reader_regression.sh \
  --fixtures /tmp/hoshi-reader-invalid-channel-fixtures \
  --output /tmp/hoshi-reader-invalid-channel-output \
  --max-channel-delta 256 \
  --plan-only >/tmp/hoshi-reader-invalid-channel.log 2>&1; then
  echo "Reader capture harness should reject max channel deltas above 255" >&2
  exit 1
fi

echo "==> Rejecting machine-local tracked skill links"
while IFS= read -r link; do
  target="$(readlink "$link")"
  if [[ "$target" = /* ]]; then
    echo "Tracked skill link is machine-local: $link -> $target" >&2
    exit 1
  fi
done < <(find .claude/skills -type l -print 2>/dev/null)

echo "==> Creating Reader screenshot capture plan"
rm -rf /tmp/hoshi-reader-regression-harness
python3 script/generate_reader_fixtures.py --output /tmp/hoshi-reader-fixtures >/tmp/hoshi-reader-fixtures.log
bash script/capture_reader_regression.sh \
  --fixtures /tmp/hoshi-reader-fixtures \
  --output /tmp/hoshi-reader-regression-harness \
  --plan-only >/tmp/hoshi-reader-regression-harness.log
test -f /tmp/hoshi-reader-regression-harness/manifest.txt
test -f /tmp/hoshi-reader-regression-harness/README.md

echo "==> Checking Reader baseline mismatch exit status"
rm -rf /tmp/hoshi-reader-empty-baseline /tmp/hoshi-reader-regression-compare
mkdir -p /tmp/hoshi-reader-empty-baseline/screenshots
if bash script/capture_reader_regression.sh \
  --fixtures /tmp/hoshi-reader-fixtures \
  --output /tmp/hoshi-reader-regression-compare \
  --plan-only \
  --compare-baseline /tmp/hoshi-reader-empty-baseline >/tmp/hoshi-reader-regression-compare.log 2>&1; then
  echo "Reader baseline comparison should fail when required baselines are missing" >&2
  exit 1
fi
test -f /tmp/hoshi-reader-regression-compare/baseline-report.json

echo "==> Running Reader popup/Sasayaki regression checks"
swiftc \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions
/tmp/test_reader_popup_sasayaki_regressions

echo "Reader harness checks passed"
