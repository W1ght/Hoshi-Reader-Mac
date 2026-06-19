#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Rejecting machine-local tracked skill links"
while IFS= read -r link; do
  target="$(readlink "$link")"
  if [[ "$target" = /* ]]; then
    echo "Tracked skill link is machine-local: $link -> $target" >&2
    exit 1
  fi
done < <(find .claude/skills -type l -print 2>/dev/null)

echo "==> Running Reader popup/Sasayaki regression checks"
swiftc \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions
/tmp/test_reader_popup_sasayaki_regressions

echo "==> Running unified shortcut checks"
bash script/verify_shortcut_harness.sh

echo "==> Running app open URL route checks"
swiftc \
  NativeMac/AppOpenURLRoute.swift \
  script/test_app_open_url_route.swift \
  -o /tmp/test_app_open_url_route
/tmp/test_app_open_url_route

echo "==> Checking Native-only release contract"
bash script/verify_native_release_contract.sh

echo "==> Checking Native upgrade compatibility contract"
bash script/verify_native_upgrade_contract.sh

echo "==> Checking actual-data Reader validation contract"
bash script/verify_reader_actual_data_contract.sh

echo "Reader contract checks passed"
