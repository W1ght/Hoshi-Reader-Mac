#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.1.2" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"
REPO="${GITHUB_REPOSITORY:-W1ght/Hoshi-Reader-for-Mac}"
APP_NAME="Hoshi Reader"
PROJECT_NAME="Hoshi Reader.xcodeproj"
SCHEME_NAME="Hoshi Reader"
BRANCH="${RELEASE_BRANCH:-codex/mac-catalyst-develop}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/$PROJECT_NAME/project.pbxproj"
RELEASE_DIR="$ROOT_DIR/release"
STAGING_DIR="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION"
DMG_PATH="$RELEASE_DIR/Hoshi-Reader-Mac-$VERSION.dmg"
NOTES_PATH="$RELEASE_DIR/release-notes-$VERSION.md"

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash changes before releasing." >&2
  git status --short
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally." >&2
  exit 1
fi

if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
  echo "Tag $TAG already exists on origin." >&2
  exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on $REPO." >&2
  exit 1
fi

python3 - "$PROJECT_FILE" "$VERSION" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()
import re
text, count = re.subn(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text)
if count == 0:
    raise SystemExit("MARKETING_VERSION not found")
path.write_text(text)
PY

git add "$PROJECT_FILE"
git commit -m "Bump version to $VERSION"

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

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Hoshi Reader $VERSION" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"

cat > "$NOTES_PATH" <<EOF
## Hoshi Reader Mac $VERSION

This Mac-focused release includes the latest reader and sync fixes.

### Highlights
- Fixes Google Drive auth storage on Mac Catalyst builds where Keychain may be unavailable.
- Keeps the reader pagination and desktop interaction refinements from the 0.1.x Mac work.

### Install
Download \`Hoshi-Reader-Mac-$VERSION.dmg\`, open it, then drag \`Hoshi Reader.app\` to Applications. If macOS blocks the unsigned app, open it from Finder with right click > Open.

### Checksum
\`Hoshi-Reader-Mac-$VERSION.dmg\`

SHA256: \`$SHA256\`
EOF

git push origin "HEAD:$BRANCH"
git tag -a "$TAG" -m "Hoshi Reader Mac $VERSION"
git push origin "$TAG"

gh release create "$TAG" "$DMG_PATH" \
  --repo "$REPO" \
  --title "Hoshi Reader Mac $VERSION" \
  --notes-file "$NOTES_PATH"

echo "Release created: https://github.com/$REPO/releases/tag/$TAG"
echo "DMG: $DMG_PATH ($SIZE)"
echo "SHA256: $SHA256"
