#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/Vendor/libmpv/lib"
DESTINATION="${1:?framework destination is required}"

[[ -f "$LIB_DIR/libmpv.2.dylib" ]] || {
  echo "Full-build libmpv dependency is missing. Run script/bootstrap_video_dependencies.sh." >&2
  exit 1
}
[[ -f "$LIB_DIR/libSvtAv1Enc.4.dylib" ]] || {
  echo "Full-build SVT-AV1 dependency is missing. Run script/bootstrap_video_dependencies.sh." >&2
  exit 1
}

mkdir -p "$DESTINATION"
find "$DESTINATION" -maxdepth 1 -name '*.dylib' -delete
cp "$LIB_DIR"/*.dylib "$DESTINATION/"
rm -f "$DESTINATION/libmpv.dylib"
