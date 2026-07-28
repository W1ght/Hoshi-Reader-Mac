#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build"
RELEASE_ROOT="$ROOT_DIR/release"
KEEP_INSTANCE_BUILDS="${HOSHI_BUILD_RETENTION_COUNT:-2}"
MODE="prune"
PROTECTED_PATH=""

usage() {
  cat <<'EOF'
usage: cleanup_build_artifacts.sh [--prune [--protect <derived-data-path>] | --all]

  --prune    Keep the newest instance DerivedData directories and skip active builds.
  --protect  Never remove the specified DerivedData directory while pruning.
  --all      Remove inactive repo-local build caches and release artifacts.

HOSHI_BUILD_RETENTION_COUNT controls how many inactive instance builds --prune keeps (default: 2).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prune)
      MODE="prune"
      shift
      ;;
    --protect)
      if [[ $# -lt 2 ]]; then
        echo "--protect requires a path" >&2
        usage >&2
        exit 2
      fi
      PROTECTED_PATH="$2"
      shift 2
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$KEEP_INSTANCE_BUILDS" =~ ^[0-9]+$ ]]; then
  echo "HOSHI_BUILD_RETENTION_COUNT must be a non-negative integer." >&2
  exit 2
fi

path_is_in_use() {
  local path="$1"
  local escaped_path
  escaped_path="$(printf '%s' "$path" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
  LC_ALL=C pgrep -f -- \
    "(^|[[:space:]])${escaped_path}([[:space:]]|$)" \
    >/dev/null 2>&1
}

remove_build_path() {
  local path="$1"
  case "$path" in
    "$BUILD_ROOT"/xcode-derived-data|"$BUILD_ROOT"/xcode-derived-data-*|"$BUILD_ROOT"/xcode-source-packages)
      ;;
    "$RELEASE_ROOT"/DerivedData|"$RELEASE_ROOT"/Niratan-Mac-*)
      ;;
    *)
      echo "Refusing to remove unexpected path: $path" >&2
      return 1
      ;;
  esac

  if [[ ! -e "$path" ]]; then
    return
  fi
  if path_is_in_use "$path"; then
    echo "Keeping active build path: $path"
    return
  fi

  rm -rf "$path"
  echo "Removed: $path"
}

prune_instance_builds() {
  if [[ ! -d "$BUILD_ROOT" ]]; then
    return
  fi

  local kept=0
  local record
  local path
  while IFS= read -r record; do
    path="${record#* }"
    if [[ -n "$PROTECTED_PATH" && "$path" == "$PROTECTED_PATH" ]]; then
      continue
    fi
    if path_is_in_use "$path"; then
      echo "Keeping active build path: $path"
      continue
    fi
    if (( kept < KEEP_INSTANCE_BUILDS )); then
      kept=$((kept + 1))
      continue
    fi
    remove_build_path "$path"
  done < <(
    find "$BUILD_ROOT" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      -name 'xcode-derived-data-*' \
      -exec stat -f '%m %N' {} \; \
      | sort -rn
  )
}

clean_all() {
  local path
  if [[ -d "$BUILD_ROOT" ]]; then
    while IFS= read -r path; do
      remove_build_path "$path"
    done < <(
      find "$BUILD_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        \( -name 'xcode-derived-data' -o -name 'xcode-derived-data-*' -o -name 'xcode-source-packages' \) \
        | sort
    )
  fi

  if [[ -d "$RELEASE_ROOT" ]]; then
    while IFS= read -r path; do
      remove_build_path "$path"
    done < <(
      find "$RELEASE_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        \( -name 'DerivedData' -o -name 'Niratan-Mac-*' \) \
        | sort
    )
  fi
}

case "$MODE" in
  prune)
    prune_instance_builds
    ;;
  all)
    clean_all
    ;;
esac
