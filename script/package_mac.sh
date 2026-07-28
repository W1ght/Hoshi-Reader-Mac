#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.6.0" >&2
  exit 2
fi

VERSION="$1"
APP_VERSION="${VERSION%%-*}"
if [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]; then
  APP_VERSION="${BASH_REMATCH[1]}"
fi
APP_NAME="Niratan"
EXPECTED_BUNDLE_ID="moe.shishamo.hoshi"
PROJECT_NAME="Niratan.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
SIGNING_IDENTITY="${HOSHI_RELEASE_SIGNING_IDENTITY:--}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ \
  && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+beta[0-9]+$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 2
fi

SCHEME_NAME="Niratan"
CONFIGURATION="Release"
ARTIFACT_NAME="Niratan-Mac-$VERSION"
BUILD_DIR="$RELEASE_DIR/DerivedData"
STAGING_DIR="$RELEASE_DIR/$ARTIFACT_NAME"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_NAME.dmg"
CHECKSUM_PATH="$RELEASE_DIR/$ARTIFACT_NAME.sha256"

cd "$ROOT_DIR"

bash script/bootstrap_libmpv.sh

xcodebuild \
  -quiet \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -sdk macosx \
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

verify_full_bundle() {
  local frameworks="$APP_BUNDLE/Contents/Frameworks"
  local youtube_resources="$APP_BUNDLE/Contents/Resources/YouTubeKit_YouTubeKit.bundle"
  [[ -f "$frameworks/libmpv.2.dylib" ]] || {
    echo "Full app is missing libmpv." >&2
    exit 1
  }
  [[ -d "$youtube_resources" ]] || {
    echo "Full app is missing YouTubeKit resources." >&2
    exit 1
  }

  while IFS= read -r library; do
    architectures="$(lipo -archs "$library")"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
      echo "Bundled video dependency is not universal: $library ($architectures)" >&2
      exit 1
    }
    if otool -L "$library" | grep -E -q '/opt/homebrew|/usr/local'; then
      echo "Bundled video dependency contains a package-manager path: $library" >&2
      exit 1
    fi
    while IFS= read -r dependency; do
      case "$dependency" in
        @rpath/*|@loader_path/*|/usr/lib/*|/System/Library/*) ;;
        *)
          echo "Bundled video dependency contains a non-portable load path: $library -> $dependency" >&2
          exit 1
          ;;
      esac
    done < <(otool -L -arch arm64 "$library" | tail -n +2 | awk '{print $1}')
  done < <(find "$frameworks" -maxdepth 1 -name '*.dylib' -type f | sort)
}

verify_full_bundle

sign_bundle() {
  local item
  while IFS= read -r item; do
    chmod u+w "$item" 2>/dev/null || true
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$item" >/dev/null
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
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$item" >/dev/null
  done < <(
    find \
      "$APP_BUNDLE/Contents/MacOS" \
      "$APP_BUNDLE/Contents/Frameworks" \
      -type f ! -name '*.dylib' -perm -111 \
      2>/dev/null \
      | sort -u
  )
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_BUNDLE" >/dev/null
  codesign --verify --deep --strict "$APP_BUNDLE"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Signed full app with ad-hoc identity."
  else
    echo "Signed full app with release identity: $SIGNING_IDENTITY"
  fi
}

sign_bundle

rm -rf "$STAGING_DIR" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "Niratan $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
for attempt in {1..5}; do
  if hdiutil verify "$DMG_PATH"; then
    break
  fi
  if [[ "$attempt" == "5" ]]; then
    echo "DMG verification failed after $attempt attempts." >&2
    exit 1
  fi
  sleep "$attempt"
done

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "$SHA256  $(basename "$DMG_PATH")" > "$CHECKSUM_PATH"
rm -rf "$STAGING_DIR"

echo "DMG_PATH=$DMG_PATH"
echo "CHECKSUM_PATH=$CHECKSUM_PATH"
echo "SHA256=$SHA256"
