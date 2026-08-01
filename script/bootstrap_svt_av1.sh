#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/libmpv"
INCLUDE_DIR="$VENDOR_DIR/include/mpv/svt-av1"
LIB_DIR="$VENDOR_DIR/lib"
LIBRARY="$LIB_DIR/libSvtAv1Enc.4.dylib"

SVT_AV1_VERSION="4.0.1"
SVT_AV1_SOURCE_URL="https://gitlab.com/AOMediaCodec/SVT-AV1.git"
SVT_AV1_SOURCE_REVISION="4ae9272b588a05ee6e77a43e8dfdac05f54c4ff0"

TEMP_DIR="$(mktemp -d /tmp/hoshi-svt-av1-bootstrap.XXXXXX)"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "SVT-AV1 bootstrap failed: $*" >&2
  exit 1
}

is_universal() {
  local architectures
  [[ -f "$1" ]] || return 1
  architectures="$(lipo -archs "$1")"
  [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
}

is_ready() {
  is_universal "$LIBRARY" \
    && [[ -f "$INCLUDE_DIR/EbSvtAv1Enc.h" ]] \
    && [[ -f "$INCLUDE_DIR/EbSvtAv1.h" ]]
}

if is_ready; then
  echo "SVT-AV1 $SVT_AV1_VERSION universal dependency is ready"
  exit 0
fi

command -v cmake >/dev/null 2>&1 || fail "cmake is required to build SVT-AV1"
command -v git >/dev/null 2>&1 || fail "git is required to fetch SVT-AV1"
command -v lipo >/dev/null 2>&1 || fail "lipo is required to make a universal SVT-AV1 dylib"

SOURCE_DIR="$TEMP_DIR/svt-av1"
git clone --quiet --filter=blob:none --no-checkout "$SVT_AV1_SOURCE_URL" "$SOURCE_DIR"
git -C "$SOURCE_DIR" -c protocol.version=2 fetch \
  --quiet \
  --depth=1 \
  origin \
  "$SVT_AV1_SOURCE_REVISION"
fetched_revision="$(git -C "$SOURCE_DIR" rev-parse FETCH_HEAD)"
[[ "$fetched_revision" == "$SVT_AV1_SOURCE_REVISION" ]] || {
  fail "source revision mismatch (expected $SVT_AV1_SOURCE_REVISION, got $fetched_revision)"
}
git -C "$SOURCE_DIR" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD

build_architecture() {
  local architecture="$1"
  local build_dir="$TEMP_DIR/build-$architecture"
  local cmake_options=(
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_OSX_ARCHITECTURES=$architecture"
    -DBUILD_APPS=OFF
    -DBUILD_SHARED_LIBS=ON
    -DSVT_AV1_LTO=OFF
  )
  # The release build must work on a clean macOS machine. C-only x86_64 avoids
  # requiring NASM while retaining a real x86_64 encoder slice for Rosetta/Intel.
  if [[ "$architecture" == "x86_64" ]]; then
    cmake_options+=("-DCOMPILE_C_ONLY=ON")
  fi
  cmake -S "$SOURCE_DIR" -B "$build_dir" "${cmake_options[@]}"
  cmake --build "$build_dir" --target SvtAv1Enc --parallel

  local built_library
  built_library="$(find "$SOURCE_DIR/Bin/Release" -type f -name 'libSvtAv1Enc*.dylib' -print -quit)"
  [[ -n "$built_library" && -f "$built_library" ]] || {
    fail "SVT-AV1 $architecture build did not produce libSvtAv1Enc"
  }
  cp "$built_library" "$TEMP_DIR/libSvtAv1Enc.$architecture.dylib"
}

build_architecture arm64
build_architecture x86_64

mkdir -p "$INCLUDE_DIR" "$LIB_DIR"
rm -f "$INCLUDE_DIR"/*.h
cp "$SOURCE_DIR"/Source/API/*.h "$INCLUDE_DIR/"

lipo -create \
  "$TEMP_DIR/libSvtAv1Enc.arm64.dylib" \
  "$TEMP_DIR/libSvtAv1Enc.x86_64.dylib" \
  -output "$TEMP_DIR/libSvtAv1Enc.universal.dylib"
install_name_tool -id "@rpath/libSvtAv1Enc.4.dylib" "$TEMP_DIR/libSvtAv1Enc.universal.dylib"
mv "$TEMP_DIR/libSvtAv1Enc.universal.dylib" "$LIBRARY"
chmod 755 "$LIBRARY"

is_universal "$LIBRARY" || fail "the generated SVT-AV1 dylib is not universal"
if otool -L "$LIBRARY" | grep -E -q '/opt/homebrew|/usr/local'; then
  fail "the generated SVT-AV1 dylib contains a package-manager dependency"
fi

echo "SVT-AV1 $SVT_AV1_VERSION universal encoder and headers are ready"
