#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep the existing IINA/libmpv ABI bootstrap separate from the source-built
# encoder, but expose one idempotent entry point to local builds and releases.
bash "$ROOT_DIR/script/bootstrap_libmpv.sh"
bash "$ROOT_DIR/script/bootstrap_svt_av1.sh"
