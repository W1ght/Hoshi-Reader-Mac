#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version> [light|video]" >&2
  echo "example: $0 0.6.0 video" >&2
  exit 2
fi

VERSION="$1"
APP_VERSION="${VERSION%%-*}"
VARIANT="${2:-light}"
APP_NAME="Hoshi Reader"
EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"
PROJECT_NAME="Hoshi Reader.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 2
fi

case "$VARIANT" in
  light)
    SCHEME_NAME="Hoshi Reader"
    CONFIGURATION="Release"
    ARTIFACT_NAME="Hoshi-Reader-Mac-$VERSION"
    ;;
  video)
    SCHEME_NAME="Hoshi Reader Video"
    CONFIGURATION="Release-Video"
    ARTIFACT_NAME="Hoshi-Reader-Mac-Video-$VERSION"
    ;;
  *)
    echo "Unknown variant: $VARIANT" >&2
    exit 2
    ;;
esac

BUILD_DIR="$RELEASE_DIR/DerivedData-$VARIANT"
STAGING_DIR="$RELEASE_DIR/$ARTIFACT_NAME"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_NAME.dmg"
CHECKSUM_PATH="$RELEASE_DIR/$ARTIFACT_NAME.sha256"

cd "$ROOT_DIR"

if [[ "$VARIANT" == "video" ]]; then
  bash script/bootstrap_libmpv.sh
fi

xcodebuild \
  -quiet \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_BUNDLE="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Release app bundle not found." >&2
  exit 1
fi

INFO_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$INFO_VERSION" != "$APP_VERSION" ]]; then
  echo "Built app version mismatch: expected $APP_VERSION, got $INFO_VERSION." >&2
  exit 1
fi

INFO_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$INFO_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Built app bundle identifier mismatch: expected $EXPECTED_BUNDLE_ID, got $INFO_BUNDLE_ID." >&2
  exit 1
fi

if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
  echo "Built app executable is missing: $APP_BUNDLE/Contents/MacOS/$APP_NAME" >&2
  exit 1
fi

verify_video_bundle() {
  local frameworks="$APP_BUNDLE/Contents/Frameworks"
  if [[ "$VARIANT" == "light" ]]; then
    if find "$frameworks" -name 'libmpv*.dylib' -print -quit 2>/dev/null | grep -q .; then
      echo "Light app unexpectedly contains libmpv." >&2
      exit 1
    fi
    return
  fi

  [[ -f "$frameworks/libmpv.2.dylib" ]] || {
    echo "Video app is missing libmpv." >&2
    exit 1
  }

  while IFS= read -r library; do
    architectures="$(lipo -archs "$library")"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
      echo "Video dependency is not universal: $library ($architectures)" >&2
      exit 1
    }
    if otool -L "$library" | rg -q '/opt/homebrew|/usr/local'; then
      echo "Video dependency contains a package-manager path: $library" >&2
      exit 1
    fi
    while IFS= read -r dependency; do
      case "$dependency" in
        @rpath/*|@loader_path/*|/usr/lib/*|/System/Library/*) ;;
        *)
          echo "Video dependency contains a non-portable load path: $library -> $dependency" >&2
          exit 1
          ;;
      esac
    done < <(otool -L -arch arm64 "$library" | tail -n +2 | awk '{print $1}')
  done < <(find "$frameworks" -maxdepth 1 -name '*.dylib' -type f | sort)
}

verify_video_bundle

adhoc_sign_bundle() {
  local item
  while IFS= read -r item; do
    chmod u+w "$item" 2>/dev/null || true
    codesign --force --sign - --timestamp=none "$item" >/dev/null
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
    codesign --force --sign - --timestamp=none "$item" >/dev/null
  done < <(
    find \
      "$APP_BUNDLE/Contents/MacOS" \
      "$APP_BUNDLE/Contents/Frameworks" \
      -type f ! -name '*.dylib' -perm -111 \
      2>/dev/null \
      | sort -u
  )
  codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null
  codesign --verify --deep --strict "$APP_BUNDLE"
}

adhoc_sign_bundle

rm -rf "$STAGING_DIR" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "Hoshi Reader $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "$SHA256  $(basename "$DMG_PATH")" > "$CHECKSUM_PATH"

echo "DMG_PATH=$DMG_PATH"
echo "CHECKSUM_PATH=$CHECKSUM_PATH"
echo "SHA256=$SHA256"
echo "VARIANT=$VARIANT"
