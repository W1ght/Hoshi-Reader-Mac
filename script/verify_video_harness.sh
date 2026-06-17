#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Running unified shortcut checks"
bash script/verify_shortcut_harness.sh

echo "==> Checking dual-variant contract"
bash script/verify_video_variant_contract.sh

echo "==> Running playback model checks"
swiftc -D HOSHI_VIDEO \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoPlaylist.swift \
  Features/Video/VideoPlaybackHistoryStore.swift \
  Features/Video/VideoPlayerViewModel.swift \
  script/test_video_playback_model.swift \
  -o /tmp/test_video_playback_model
/tmp/test_video_playback_model

echo "==> Running advanced playback checks"
swiftc -D HOSHI_VIDEO \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoPlaylist.swift \
  Features/Video/VideoPlaybackHistoryStore.swift \
  Features/Video/VideoPlayerViewModel.swift \
  script/test_video_advanced_playback.swift \
  -o /tmp/test_video_advanced_playback
/tmp/test_video_advanced_playback

echo "==> Checking mpv track mapping"
swift script/test_video_track_mapping.swift

echo "==> Running playlist checks"
swiftc -D HOSHI_VIDEO \
  Features/Video/VideoPlaylist.swift \
  script/test_video_playlist.swift \
  -o /tmp/test_video_playlist
/tmp/test_video_playlist

echo "==> Running playback history checks"
swiftc -D HOSHI_VIDEO \
  Features/Video/VideoPlaybackHistoryStore.swift \
  script/test_video_playback_history.swift \
  -o /tmp/test_video_playback_history
/tmp/test_video_playback_history

echo "==> Checking Video settings contract"
swift script/test_video_settings_contract.swift

echo "==> Checking Video fullscreen contract"
swift script/test_video_fullscreen_contract.swift

echo "==> Running subtitle parser and timeline checks"
swiftc -D HOSHI_VIDEO \
  Models/Subtitle.swift \
  Features/Video/Subtitles/SubtitleParser.swift \
  Features/Video/Subtitles/SubtitleCueStore.swift \
  script/test_video_subtitles.swift \
  -o /tmp/test_video_subtitles
/tmp/test_video_subtitles

echo "==> Running bilingual transcript checks"
swiftc -D HOSHI_VIDEO \
  Models/Subtitle.swift \
  Features/Video/Subtitles/SubtitleCueStore.swift \
  script/test_video_transcript.swift \
  -o /tmp/test_video_transcript
/tmp/test_video_transcript

echo "==> Running embedded subtitle overlay checks"
swiftc -D HOSHI_VIDEO \
  Models/Subtitle.swift \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/Subtitles/SubtitleCueStore.swift \
  Features/Video/Subtitles/SubtitleParser.swift \
  Features/Video/Subtitles/VideoSubtitleController.swift \
  script/test_video_embedded_subtitles.swift \
  -o /tmp/test_video_embedded_subtitles
/tmp/test_video_embedded_subtitles

echo "==> Running subtitle selection checks"
swiftc -D HOSHI_VIDEO \
  Features/Video/Subtitles/SubtitleSelectionResolver.swift \
  script/test_video_subtitle_selection.swift \
  -o /tmp/test_video_subtitle_selection
/tmp/test_video_subtitle_selection

echo "==> Running video mining context checks"
swiftc -D HOSHI_VIDEO \
  Models/Anki.swift \
  script/test_video_mining_context.swift \
  -o /tmp/test_video_mining_context
/tmp/test_video_mining_context

echo "==> Running video media mining checks"
swiftc -D HOSHI_VIDEO \
  Models/Anki.swift \
  script/test_video_media_mining.swift \
  -o /tmp/test_video_media_mining
/tmp/test_video_media_mining

echo "==> Checking Video Liquid Glass contract"
swift script/test_video_liquid_glass_contract.swift

if [[ -f Vendor/libmpv/lib/libmpv.2.dylib ]]; then
  echo "==> Running libmpv initialization probe"
  clang script/test_libmpv_probe.c \
    -I Vendor/libmpv/include \
    -L Vendor/libmpv/lib \
    -lmpv \
    -Wl,-rpath,"$ROOT_DIR/Vendor/libmpv/lib" \
    -o /tmp/test_libmpv_probe
  /tmp/test_libmpv_probe

  echo "==> Compiling AppKit libmpv bridge probe"
  clang++ -std=c++20 -fobjc-arc -D HOSHI_VIDEO \
    -framework AppKit \
    -framework Foundation \
    -framework OpenGL \
    Features/Video/Playback/HSMpvClient.mm \
    script/test_mpv_client.mm \
    -I Features/Video/Playback \
    -I Vendor/libmpv/include \
    -L Vendor/libmpv/lib \
    -lmpv \
    -Wl,-rpath,"$ROOT_DIR/Vendor/libmpv/lib" \
    -o /tmp/test_mpv_client

  if command -v ffmpeg >/dev/null 2>&1; then
    echo "==> Running AppKit libmpv media probe"
    ffmpeg -loglevel error -y \
      -f lavfi -i "color=c=navy:s=320x180:d=1" \
      -f lavfi -i "sine=frequency=440:duration=1" \
      -pix_fmt yuv420p \
      -c:a aac -shortest \
      /tmp/hoshi-video-harness.mp4
    /tmp/test_libmpv_probe /tmp/hoshi-video-harness.mp4
    /tmp/test_mpv_client /tmp/hoshi-video-harness.mp4

    ffmpeg -loglevel error -y \
      -f lavfi -i "sine=frequency=330:duration=1" \
      -c:a aac \
      -f mp4 \
      /tmp/hoshi-video-audiobook.m4b
    /tmp/test_mpv_client /tmp/hoshi-video-audiobook.m4b audio-only

    cat > /tmp/hoshi-video-external.srt <<'EOF'
1
00:00:00,000 --> 00:00:00,900
外部字幕テスト
EOF
    /tmp/test_mpv_client \
      /tmp/hoshi-video-harness.mp4 \
      external-subtitles \
      /tmp/hoshi-video-external.srt

    cat > /tmp/hoshi-video-embedded.srt <<'EOF'
1
00:00:00,000 --> 00:00:00,900
内蔵字幕テスト
EOF
    ffmpeg -loglevel error -y \
      -i /tmp/hoshi-video-harness.mp4 \
      -i /tmp/hoshi-video-embedded.srt \
      -c copy -c:s srt \
      /tmp/hoshi-video-embedded.mkv
    /tmp/test_mpv_client /tmp/hoshi-video-embedded.mkv expect-subtitles

    echo "==> Running AVFoundation audio clip export probe"
    swiftc -D HOSHI_VIDEO \
      Features/Video/Playback/VideoAudioClipExporter.swift \
      script/test_video_audio_export.swift \
      -framework AVFoundation \
      -o /tmp/test_video_audio_export
    /tmp/test_video_audio_export \
      /tmp/hoshi-video-harness.mp4 \
      /tmp/hoshi-video-audio-clip.m4a
  else
    echo "Skipping media probes because ffmpeg is unavailable"
  fi
fi

echo "Video harness checks passed"
