#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  echo "example: $0 0.1.3" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"
BRANCH="${RELEASE_BRANCH:-codex/mac-catalyst-develop}"
PROJECT_NAME="Hoshi Reader.xcodeproj"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/$PROJECT_NAME/project.pbxproj"

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

python3 - "$PROJECT_FILE" "$VERSION" <<'PY'
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
git commit -m "Bump version to $VERSION"
git push origin "HEAD:$BRANCH"
git tag -a "$TAG" -m "Hoshi Reader Mac $VERSION"
git push origin "$TAG"

echo "Pushed $TAG. GitHub Actions will build the DMG and create the release."
echo "Release URL: https://github.com/W1ght/Hoshi-Reader-for-Mac/releases/tag/$TAG"
