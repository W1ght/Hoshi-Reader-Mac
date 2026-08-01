#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/libmpv"
INCLUDE_ROOT="$VENDOR_DIR/include"
LIB_DIR="$VENDOR_DIR/lib"
CHECKSUM_FILE="$ROOT_DIR/script/libmpv-1.4.2.sha256"

# IINA publishes release-specific dylib sets but no separate headers archive.
# Pin both sides of the ABI boundary to IINA 1.4.2 build 164: the dylibs come
# from that immutable release directory and the headers come from its exact
# source commit. Never point either URL at develop or the rolling universal set.
IINA_ARTIFACT_VERSION="1.4.2"
IINA_SOURCE_REVISION="f6755d24ae461ce27c08814b9babe566ab43c80a"
BASE_URL="https://iina.io/dylibs/$IINA_ARTIFACT_VERSION/universal"
SOURCE_URL="https://github.com/iina/iina.git"
EXPECTED_FILE_LIST_SHA256="665da1e0506eeb952c0870153265df23602a9ef35e45290c8218dccc50a6da96"

EXPECTED_LIBAVCODEC_MAJOR="61"
EXPECTED_LIBAVFORMAT_MAJOR="61"
EXPECTED_LIBAVUTIL_MAJOR="59"

TEMP_DIR="$(mktemp -d /tmp/hoshi-libmpv-bootstrap.XXXXXX)"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$INCLUDE_ROOT" "$LIB_DIR"

fail() {
  echo "libmpv bootstrap failed: $*" >&2
  exit 1
}

sha256_for_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_header_major() {
  local header="$1"
  local macro="$2"
  local expected="$3"
  local actual
  actual="$(awk -v macro="$macro" '$1 == "#define" && $2 == macro { print $3; exit }' "$header")"
  [[ "$actual" == "$expected" ]] || {
    fail "$macro mismatch in $header (expected $expected, got ${actual:-missing})"
  }
}

download_pinned_headers() {
  local source_checkout="$TEMP_DIR/iina-source"
  git init --quiet "$source_checkout"
  git -C "$source_checkout" remote add origin "$SOURCE_URL"
  git -C "$source_checkout" -c protocol.version=2 fetch \
    --quiet \
    --depth=1 \
    --filter=blob:none \
    origin \
    "$IINA_SOURCE_REVISION"

  local fetched_revision
  fetched_revision="$(git -C "$source_checkout" rev-parse FETCH_HEAD)"
  [[ "$fetched_revision" == "$IINA_SOURCE_REVISION" ]] || {
    fail "IINA source revision mismatch (expected $IINA_SOURCE_REVISION, got $fetched_revision)"
  }

  git -C "$source_checkout" sparse-checkout init --cone
  git -C "$source_checkout" sparse-checkout set \
    deps/include/mpv \
    deps/include/libavcodec \
    deps/include/libavformat \
    deps/include/libavutil
  git -C "$source_checkout" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD

  local mpv_source_directory="$source_checkout/deps/include/mpv"
  [[ -d "$mpv_source_directory" ]] || fail "missing pinned header directory: mpv"
  rm -rf "$INCLUDE_ROOT/mpv"
  cp -R "$mpv_source_directory" "$INCLUDE_ROOT/mpv"

  # Keep every generated header under the repository's ignored mpv dependency
  # boundary. Xcode adds this nested directory as a second header search root so
  # FFmpeg's canonical <libavcodec/...> imports continue to resolve.
  local header_directory
  for header_directory in libavcodec libavformat libavutil; do
    local source_directory="$source_checkout/deps/include/$header_directory"
    [[ -d "$source_directory" ]] || fail "missing pinned header directory: $header_directory"
    cp -R "$source_directory" "$INCLUDE_ROOT/mpv/$header_directory"
    rm -rf "$INCLUDE_ROOT/$header_directory"
  done

  verify_header_major \
    "$INCLUDE_ROOT/mpv/libavcodec/version_major.h" \
    LIBAVCODEC_VERSION_MAJOR \
    "$EXPECTED_LIBAVCODEC_MAJOR"
  verify_header_major \
    "$INCLUDE_ROOT/mpv/libavformat/version_major.h" \
    LIBAVFORMAT_VERSION_MAJOR \
    "$EXPECTED_LIBAVFORMAT_MAJOR"
  verify_header_major \
    "$INCLUDE_ROOT/mpv/libavutil/version.h" \
    LIBAVUTIL_VERSION_MAJOR \
    "$EXPECTED_LIBAVUTIL_MAJOR"
}

download_pinned_headers

[[ -f "$CHECKSUM_FILE" ]] || fail "missing artifact checksum manifest: $CHECKSUM_FILE"

file_list="$TEMP_DIR/filelist.txt"
curl -fsSL --retry 3 --connect-timeout 10 "$BASE_URL/filelist.txt" -o "$file_list"
actual_file_list_sha256="$(sha256_for_file "$file_list")"
[[ "$actual_file_list_sha256" == "$EXPECTED_FILE_LIST_SHA256" ]] || {
  fail "IINA $IINA_ARTIFACT_VERSION file list checksum mismatch"
}

expected_names="$TEMP_DIR/expected-library-names.txt"
remote_names="$TEMP_DIR/remote-library-names.txt"
awk '{print $2}' "$CHECKSUM_FILE" | LC_ALL=C sort > "$expected_names"
LC_ALL=C sort "$file_list" > "$remote_names"
cmp -s "$expected_names" "$remote_names" || {
  fail "artifact checksum manifest does not match the pinned IINA file list"
}

while read -r expected_sha256 file; do
  [[ -n "$expected_sha256" && -n "$file" ]] || continue
  library="$LIB_DIR/$file"
  upstream_library="$library.upstream"

  # IINA's legacy GCC runtime libraries are x86_64-only. Keep their pinned
  # upstream bytes in a sidecar so the universal compatibility wrapper can be
  # regenerated without looking like a checksum mismatch on every bootstrap.
  case "$file" in
    libgcc_s.1.1.dylib|libstdc++.6.dylib)
      checksum_target="$upstream_library"
      ;;
    *)
      checksum_target="$library"
      ;;
  esac
  actual_sha256=""
  if [[ -f "$checksum_target" ]]; then
    actual_sha256="$(sha256_for_file "$checksum_target")"
  fi
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    downloaded_library="$TEMP_DIR/$file"
    echo "Downloading $file from IINA $IINA_ARTIFACT_VERSION"
    curl -fsSL --retry 3 --connect-timeout 10 "$BASE_URL/$file" -o "$downloaded_library"
    downloaded_sha256="$(sha256_for_file "$downloaded_library")"
    [[ "$downloaded_sha256" == "$expected_sha256" ]] || {
      fail "$file checksum mismatch"
    }
    mv "$downloaded_library" "$checksum_target"
  fi

  if [[ "$checksum_target" != "$library" ]]; then
    cp "$checksum_target" "$library"
  fi
done < "$CHECKSUM_FILE"

# Keep the generated dependency directory equal to the pinned artifact set.
while IFS= read -r library; do
  name="$(basename "$library")"
  [[ "$name" == "libmpv.dylib" ]] && continue
  [[ "$name" == "libSvtAv1Enc.4.dylib" ]] && continue
  if ! grep -Fqx "$name" "$expected_names"; then
    echo "Removing stale Video dependency $name"
    rm -f "$library"
  fi
done < <(find "$LIB_DIR" -maxdepth 1 -type f -name '*.dylib' | sort)

ln -sf libmpv.2.dylib "$LIB_DIR/libmpv.dylib"

create_unused_arm64_slice() {
  local library="$1"
  local name
  name="$(basename "$library")"
  local stub="$TEMP_DIR/${name}.arm64"
  local combined="$TEMP_DIR/${name}.universal"
  clang -arch arm64 -dynamiclib -x c /dev/null \
    -Wl,-no_uuid \
    -install_name "@rpath/$name" \
    -o "$stub"
  lipo -create "$library" "$stub" -output "$combined"
  mv "$combined" "$library"
}

for library in "$LIB_DIR"/*.dylib; do
  [[ "$(basename "$library")" == "libSvtAv1Enc.4.dylib" ]] && continue
  chmod 755 "$library"
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
    fail "expected universal dylib: $library ($architectures)"
  }
done

echo "libmpv $IINA_ARTIFACT_VERSION vendor dependencies and matching headers are ready"
