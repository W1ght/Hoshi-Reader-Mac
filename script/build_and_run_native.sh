#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Hoshi Reader"
PROJECT_NAME="Hoshi Reader.xcodeproj"
SCHEME_NAME="Hoshi Reader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_GLOB="$HOME/Library/Developer/Xcode/DerivedData/Hoshi_Reader-*"
APP_BUNDLE=""

cd "$ROOT_DIR"

kill_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -quiet \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -destination "generic/platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
}

resolve_app_bundle() {
  local bundle
  bundle="$(ls -dt $DERIVED_DATA_GLOB/Build/Products/Debug/"$APP_NAME".app 2>/dev/null | head -n 1 || true)"
  APP_BUNDLE="$bundle"
}

open_app() {
  if [[ $# -gt 0 ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --args "$@"
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        break
      fi
      sleep 0.1
    done
    /usr/bin/open "$APP_BUNDLE"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

verify_bundle() {
  resolve_app_bundle
  if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "Expected native macOS app bundle not found at: $APP_BUNDLE" >&2
    exit 1
  fi
}

refresh_app_icon_registration() {
  /usr/bin/touch "$APP_BUNDLE" "$APP_BUNDLE/Contents" "$APP_BUNDLE/Contents/Info.plist"
  if [[ -f "$APP_BUNDLE/Contents/Resources/HoshiIcon.icns" ]]; then
    /usr/bin/touch "$APP_BUNDLE/Contents/Resources/HoshiIcon.icns"
  fi

  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

case "$MODE" in
  run)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app
    ;;
  --open-latest|open-latest)
    kill_app
    verify_bundle
    refresh_app_icon_registration
    open_app
    ;;
  --reader-regression-lab|reader-regression-lab)
    shift
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app --reader-regression-lab "$@"
    ;;
  --debug|debug)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--open-latest|--reader-regression-lab|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
