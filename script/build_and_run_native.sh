#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Hoshi Reader"
PROJECT_NAME="Hoshi Reader.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_GLOB="$HOME/Library/Developer/Xcode/DerivedData/Hoshi_Reader-*"
APP_BUNDLE=""
MODE="run"
VARIANT="light"
MODE_ARGS=()

usage() {
  cat <<'EOF'
usage: build_and_run_native.sh [--light|--video] [mode] [arguments]

variants:
  --light                 Build and launch the Light variant (default).
  --video                 Build and launch the Video variant.

modes:
  run                     Build and launch.
  --open-latest           Launch the latest existing build without rebuilding.
  --open-url <url>        Build, launch, and open a Hoshi URL.
  --reader-regression-lab Build and open the Reader regression lab.
  --debug                 Build and attach LLDB.
  --logs                  Build, launch, and stream logs.
  --telemetry             Build, launch, and stream logs.
  --verify                Build, launch, and verify the process started.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --light)
      VARIANT="light"
      shift
      ;;
    --video)
      VARIANT="video"
      shift
      ;;
    run|--open-latest|open-latest|--open-url|open-url|--reader-regression-lab|reader-regression-lab|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
      MODE="$1"
      shift
      MODE_ARGS=("$@")
      break
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$VARIANT" in
  light)
    SCHEME_NAME="Hoshi Reader"
    CONFIGURATION="Debug"
    ;;
  video)
    SCHEME_NAME="Hoshi Reader Video"
    CONFIGURATION="Debug-Video"
    ;;
esac

cd "$ROOT_DIR"

kill_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  if [[ "$VARIANT" == "video" && ! -f "$ROOT_DIR/Vendor/libmpv/lib/libmpv.2.dylib" ]]; then
    bash "$ROOT_DIR/script/bootstrap_libmpv.sh"
  fi
  xcodebuild \
    -quiet \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
}

resolve_app_bundle() {
  local bundle
  bundle="$(ls -dt $DERIVED_DATA_GLOB/Build/Products/"$CONFIGURATION"/"$APP_NAME".app 2>/dev/null | head -n 1 || true)"
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

open_url() {
  local url="$1"
  /usr/bin/open -a "$APP_BUNDLE" "$url"
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
  --open-url|open-url)
    if [[ ${#MODE_ARGS[@]} -ne 1 ]]; then
      echo "usage: $0 [--light|--video] --open-url <url>" >&2
      exit 2
    fi
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_url "${MODE_ARGS[0]}"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --reader-regression-lab|reader-regression-lab)
    kill_app
    build_app
    verify_bundle
    refresh_app_icon_registration
    open_app --reader-regression-lab "${MODE_ARGS[@]}"
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
    usage >&2
    exit 2
    ;;
esac
