#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.1.2" >&2
  exit 2
fi

VERSION="$1"
APP_NAME="Hoshi Reader"
PROJECT_NAME="Hoshi Reader.xcodeproj"
SCHEME_NAME="Hoshi Reader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
STAGING_DIR="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION"
DMG_PATH="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION.dmg"
CHECKSUM_PATH="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION.sha256"

cd "$ROOT_DIR"

xcodebuild \
  -quiet \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS,variant=Mac Catalyst" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_BUNDLE="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Hoshi_Reader-*/Build/Products/Release-maccatalyst/"$APP_NAME.app" | head -n 1)"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "Release app bundle not found." >&2
  exit 1
fi

INFO_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$INFO_VERSION" != "$VERSION" ]]; then
  echo "Built app version mismatch: expected $VERSION, got $INFO_VERSION." >&2
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
