#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version>" >&2
  echo "       $0 <version> <release-notes-file>" >&2
  echo "example: $0 0.2.0 /tmp/hoshi-0.2.0-notes.md" >&2
  exit 2
fi

VERSION="$1"
APP_VERSION="${VERSION%%-*}"
if [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)beta[0-9]+$ ]]; then
  APP_VERSION="${BASH_REMATCH[1]}"
fi
TAG="v$VERSION"
NOTES_FILE="${2:-}"
BRANCH="${RELEASE_BRANCH:-$(git branch --show-current)}"
PROJECT_NAME="Hoshi Reader.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/$PROJECT_NAME/project.pbxproj"

cd "$ROOT_DIR"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ \
  && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+beta[0-9]+$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 2
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash changes before releasing." >&2
  git status --short
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  echo "Unable to resolve current branch. Set RELEASE_BRANCH explicitly." >&2
  exit 1
fi

if [[ "$BRANCH" != "main" && "${ALLOW_NON_MAIN_RELEASE:-0}" != "1" ]]; then
  echo "Refusing to release from $BRANCH. Release tags should be cut from main." >&2
  echo "Set ALLOW_NON_MAIN_RELEASE=1 only if this is intentional." >&2
  exit 1
fi

if [[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]]; then
  echo "Release notes file not found: $NOTES_FILE" >&2
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

python3 - "$PROJECT_FILE" "$APP_VERSION" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()
text, count = re.subn(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text)
if count == 0:
    raise SystemExit("MARKETING_VERSION not found")
path.write_text(text)
PY

git add "$PROJECT_FILE"
if git diff --cached --quiet; then
  echo "Marketing version is already $APP_VERSION; tagging the current commit."
else
  git commit -m "chore(release): bump version to $VERSION"
fi
git push origin "$BRANCH"

TAG_MESSAGE="$(mktemp)"
{
  echo "Hoshi Reader Mac $VERSION"
  echo
  if [[ -n "$NOTES_FILE" ]]; then
    cat "$NOTES_FILE"
  else
    echo "This Mac-focused release includes the latest user-facing fixes and improvements."
  fi
} > "$TAG_MESSAGE"

git tag -a "$TAG" --cleanup=verbatim -F "$TAG_MESSAGE"
rm -f "$TAG_MESSAGE"
git push origin "$TAG"

echo "Pushed $TAG. GitHub Actions will build the DMG and create the release."
echo "Release URL: https://github.com/W1ght/Hoshi-Reader-Mac/releases/tag/$TAG"
