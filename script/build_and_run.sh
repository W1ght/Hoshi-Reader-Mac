#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Hoshi Reader"
PROJECT_NAME="Hoshi Reader.xcodeproj"
SCHEME_NAME="Hoshi Reader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_GLOB="$HOME/Library/Developer/Xcode/DerivedData/Hoshi_Reader-*"
APP_BUNDLE=""

kill_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -quiet \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -destination "generic/platform=macOS,variant=Mac Catalyst" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
}

resolve_app_bundle() {
  local bundle
  bundle="$(ls -dt $DERIVED_DATA_GLOB/Build/Products/Debug-maccatalyst/"$APP_NAME".app 2>/dev/null | head -n 1 || true)"
  APP_BUNDLE="$bundle"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_bundle() {
  resolve_app_bundle
  if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "Expected app bundle not found at: $APP_BUNDLE" >&2
    exit 1
  fi
}

kill_app
build_app
verify_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
