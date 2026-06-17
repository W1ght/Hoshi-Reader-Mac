#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/libmpv"
INCLUDE_DIR="$VENDOR_DIR/include/mpv"
LIB_DIR="$VENDOR_DIR/lib"
BASE_URL="https://iina.io/dylibs/universal"
HEADER_BASE_URL="https://raw.githubusercontent.com/iina/iina/develop/deps/include/mpv"

mkdir -p "$INCLUDE_DIR" "$LIB_DIR"

for header in client.h render.h render_gl.h; do
  curl -fsSL "$HEADER_BASE_URL/$header" -o "$INCLUDE_DIR/$header"
done

file_list="$(mktemp)"
trap 'rm -f "$file_list"' EXIT
curl -fsSL "$BASE_URL/filelist.txt" -o "$file_list"

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  if [[ ! -f "$LIB_DIR/$file" ]]; then
    echo "Downloading $file"
    curl -fsSL "$BASE_URL/$file" -o "$LIB_DIR/$file"
  fi
done < "$file_list"

ln -sf libmpv.2.dylib "$LIB_DIR/libmpv.dylib"

create_unused_arm64_slice() {
  local library="$1"
  local name
  name="$(basename "$library")"
  local stub
  local combined
  stub="$(mktemp "/tmp/${name}.arm64.XXXXXX")"
  combined="$(mktemp "/tmp/${name}.universal.XXXXXX")"
  clang -arch arm64 -dynamiclib -x c /dev/null \
    -install_name "@rpath/$name" \
    -o "$stub"
  lipo -create "$library" "$stub" -output "$combined"
  mv "$combined" "$library"
  rm -f "$stub"
}

for library in "$LIB_DIR"/*.dylib; do
  architectures="$(lipo -archs "$library")"
  if [[ "$architectures" == "x86_64" ]]; then
    case "$(basename "$library")" in
      libgcc_s.1.1.dylib|libstdc++.6.dylib)
        create_unused_arm64_slice "$library"
        architectures="$(lipo -archs "$library")"
        ;;
    esac
  fi
  [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
    echo "Expected universal dylib: $library ($architectures)" >&2
    exit 1
  }
done

while IFS= read -r library; do
  codesign --force --sign - "$library" >/dev/null
done < <(find "$LIB_DIR" -maxdepth 1 -type f -name '*.dylib' | sort)

echo "libmpv vendor dependencies are ready"
