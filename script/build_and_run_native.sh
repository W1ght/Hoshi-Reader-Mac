#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Hoshi Reader"
EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"
PROJECT_NAME="Hoshi Reader.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_GLOB="$HOME/Library/Developer/Xcode/DerivedData/Hoshi_Reader-*"
APP_BUNDLE=""
APP_EXECUTABLE=""
MODE="run"
VARIANT="light"
MODE_ARGS=()
OPEN_ENV_ARGS=()

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
    run|--open-latest|open-latest|--open-url|open-url|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
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
  APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

running_app_pid() {
  pgrep -f -- "$APP_EXECUTABLE" | head -n 1
}

wait_for_running_app() {
  local pid=""
  for _ in {1..40}; do
    pid="$(running_app_pid || true)"
    if [[ -n "$pid" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.1
  done
  echo "Expected app executable did not start: $APP_EXECUTABLE" >&2
  return 1
}

open_app() {
  if [[ $# -gt 0 ]]; then
    open_with_env -n "$APP_BUNDLE" --args "$@"
    wait_for_running_app >/dev/null
    open_with_env "$APP_BUNDLE"
  else
    open_with_env -n "$APP_BUNDLE"
  fi
}

open_url() {
  local url="$1"
  open_with_env -a "$APP_BUNDLE" "$url"
}

open_env_args() {
  OPEN_ENV_ARGS=()
  if [[ -n "${HOSHI_VIDEO_LIBRARY_CATALOG_URL:-}" ]]; then
    OPEN_ENV_ARGS+=(--env "HOSHI_VIDEO_LIBRARY_CATALOG_URL=$HOSHI_VIDEO_LIBRARY_CATALOG_URL")
  fi
}

open_with_env() {
  open_env_args
  if [[ ${#OPEN_ENV_ARGS[@]} -gt 0 ]]; then
    /usr/bin/open "${OPEN_ENV_ARGS[@]}" "$@"
  else
    /usr/bin/open "$@"
  fi
}

verify_bundle() {
  resolve_app_bundle
  if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "Expected native macOS app bundle not found at: $APP_BUNDLE" >&2
    exit 1
  fi

  local bundle_identifier
  bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$bundle_identifier" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Built app bundle identifier mismatch: expected $EXPECTED_BUNDLE_ID, got $bundle_identifier." >&2
    exit 1
  fi
  if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Expected app executable not found: $APP_EXECUTABLE" >&2
    exit 1
  fi
}

local_debug_codesign_identity() {
  local identity
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
  else
    printf '%s\n' "-"
  fi
}

codesign_local_debug_bundle() {
  if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    return
  fi

  local signing_identity
  signing_identity="$(local_debug_codesign_identity)"

  local item
  while IFS= read -r item; do
    chmod u+w "$item" 2>/dev/null || true
    codesign --force --sign "$signing_identity" "$item" >/dev/null 2>&1
  done < <(
    find \
      "$APP_BUNDLE/Contents/MacOS" \
      "$APP_BUNDLE/Contents/Frameworks" \
      -type f -name '*.dylib' \
      2>/dev/null \
      | sort -u
  )
  while IFS= read -r item; do
    chmod u+w "$item" 2>/dev/null || true
    codesign --force --sign "$signing_identity" "$item" >/dev/null 2>&1
  done < <(
    find \
      "$APP_BUNDLE/Contents/MacOS" \
      "$APP_BUNDLE/Contents/Frameworks" \
      -type f ! -name '*.dylib' -perm -111 \
      2>/dev/null \
      | sort -u
  )
  codesign --force --sign "$signing_identity" "$APP_BUNDLE" >/dev/null 2>&1
  codesign --verify --deep --strict "$APP_BUNDLE"
  if [[ "$signing_identity" != "-" ]]; then
    sleep 1
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
    codesign_local_debug_bundle
    refresh_app_icon_registration
    open_app
    ;;
  --open-latest|open-latest)
    kill_app
    verify_bundle
    codesign_local_debug_bundle
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
    codesign_local_debug_bundle
    refresh_app_icon_registration
    open_url "${MODE_ARGS[0]}"
    wait_for_running_app >/dev/null
    ;;
  --debug|debug)
    kill_app
    build_app
    verify_bundle
    codesign_local_debug_bundle
    refresh_app_icon_registration
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    kill_app
    build_app
    verify_bundle
    codesign_local_debug_bundle
    refresh_app_icon_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    kill_app
    build_app
    verify_bundle
    codesign_local_debug_bundle
    refresh_app_icon_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    kill_app
    build_app
    verify_bundle
    codesign_local_debug_bundle
    refresh_app_icon_registration
    open_app
    VERIFIED_PID="$(wait_for_running_app)"
    echo "Verified $EXPECTED_BUNDLE_ID at $APP_BUNDLE (pid $VERIFIED_PID)"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
