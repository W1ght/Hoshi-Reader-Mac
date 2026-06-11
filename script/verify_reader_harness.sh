#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking Reader fixture generator syntax"
python3 -m py_compile script/generate_reader_fixtures.py

echo "==> Checking Reader screenshot capture harness syntax"
bash -n script/capture_reader_regression.sh

echo "==> Creating Reader screenshot capture plan"
rm -rf /tmp/hoshi-reader-regression-harness
python3 script/generate_reader_fixtures.py --output /tmp/hoshi-reader-fixtures >/tmp/hoshi-reader-fixtures.log
script/capture_reader_regression.sh \
  --fixtures /tmp/hoshi-reader-fixtures \
  --output /tmp/hoshi-reader-regression-harness \
  --plan-only >/tmp/hoshi-reader-regression-harness.log
test -f /tmp/hoshi-reader-regression-harness/manifest.txt
test -f /tmp/hoshi-reader-regression-harness/README.md

echo "==> Running Reader popup/Sasayaki regression checks"
swiftc \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions
/tmp/test_reader_popup_sasayaki_regressions

echo "Reader harness checks passed"
