#!/usr/bin/env bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" != *-Video ]]; then
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/Vendor/libmpv/lib"
DESTINATION="${1:?framework destination is required}"

[[ -f "$LIB_DIR/libmpv.2.dylib" ]] || {
  echo "Video dependencies are missing. Run script/bootstrap_libmpv.sh." >&2
  exit 1
}

mkdir -p "$DESTINATION"
find "$DESTINATION" -maxdepth 1 -name '*.dylib' -delete
cp "$LIB_DIR"/*.dylib "$DESTINATION/"
rm -f "$DESTINATION/libmpv.dylib"
