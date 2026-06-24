#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hoshi-video-library-ui.XXXXXX")"
SOURCE_DIR="$FIXTURE_ROOT/Video Bookshelf Fixture"
CATALOG_URL="$FIXTURE_ROOT/video_library.json"

mkdir -p "$SOURCE_DIR/Season 1" "$SOURCE_DIR/Movies" "$SOURCE_DIR/.hidden"
printf 'scan fixture\n' > "$SOURCE_DIR/Season 1/Alpha Episode.mp4"
printf 'scan fixture\n' > "$SOURCE_DIR/Season 1/Beta Episode.mkv"
printf 'scan fixture\n' > "$SOURCE_DIR/Movies/Gamma Movie.webm"
printf 'not media\n' > "$SOURCE_DIR/notes.txt"
printf 'hidden media\n' > "$SOURCE_DIR/.hidden/Hidden Episode.mp4"

cat <<EOF
Video library disposable fixture created.

Source folder to add in Hoshi:
  $SOURCE_DIR

Disposable catalog:
  $CATALOG_URL

Manual pass:
  1. In Video, choose Add Video Folder and select the source folder above.
  2. Confirm All Videos shows Alpha Episode, Beta Episode, and Gamma Movie.
  3. Confirm notes.txt and .hidden/Hidden Episode.mp4 do not appear.
  4. Try List/Posters layout, Continue Watching, Unwatched, Finished, Missing,
     Search, Sort, Unfinished, Folders, Refresh, and Manage Sources.
  5. Confirm Manage Sources shows video/source counts, per-source refresh, and
     Reveal Source in Finder.
  6. Remove one fixture video, confirm Missing/source missing count updates, then
     refresh that source and confirm the stale item disappears.
  7. Remove the source and confirm files remain on disk.

These fixture files are scan-only placeholders. Use a real local video file for playback,
Recent ordering, mark watched, clear progress, play from beginning, seeking,
poster thumbnail generation, subtitle, and mining validation.

Cleanup after the manual pass:
  rm -rf "$FIXTURE_ROOT"

Launching Video with HOSHI_VIDEO_LIBRARY_CATALOG_URL set to the disposable catalog.
EOF

cd "$ROOT_DIR"
HOSHI_VIDEO_LIBRARY_CATALOG_URL="$CATALOG_URL" ./script/build_and_run.sh --video --verify
