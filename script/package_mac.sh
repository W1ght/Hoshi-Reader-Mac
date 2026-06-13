#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.1.2" >&2
  exit 2
fi

VERSION="$1"
APP_NAME="Hoshi Reader"
EXPECTED_BUNDLE_ID="de.manhhao.hoshi"
PROJECT_NAME="Hoshi Reader.xcodeproj"
SCHEME_NAME="Hoshi Reader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
BUILD_DIR="$RELEASE_DIR/DerivedData"
STAGING_DIR="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION"
DMG_PATH="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION.dmg"
CHECKSUM_PATH="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION.sha256"

cd "$ROOT_DIR"

xcodebuild \
  -quiet \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_BUNDLE="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Release app bundle not found." >&2
  exit 1
fi

INFO_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$INFO_VERSION" != "$VERSION" ]]; then
  echo "Built app version mismatch: expected $VERSION, got $INFO_VERSION." >&2
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

codesign --remove-signature "$APP_BUNDLE"
if codesign -dv "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "Built app still contains a code signature." >&2
  exit 1
fi

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
