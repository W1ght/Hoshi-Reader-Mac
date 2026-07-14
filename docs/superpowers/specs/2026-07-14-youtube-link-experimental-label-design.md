# YouTube Link Experimental Label Design

## Goal

Make the Add Link sheet clearly identify YouTube playback as experimental before a user submits a URL, without changing resolution, playback, subtitle, quality, persistence, or window behavior.

## User Interface

The existing `RemoteVideoLinkSheet` title row will keep `YouTube Video` as its primary heading and add a compact orange `Experimental` capsule beside it. The capsule is informational rather than interactive and uses native SwiftUI text, color, padding, and `Capsule` styling.

A short secondary line appears immediately below the title:

> YouTube playback is experimental and may stop working when YouTube changes its service.

The URL field, resolving state, error presentation, Cancel action, and Add Link action remain unchanged. The toolbar button remains `Add Link`; the experimental warning belongs to the sheet where the user can read it before proceeding.

## Localization

Both new visible strings are stored in `Localizable.xcstrings` with English, Simplified Chinese, and Traditional Chinese values:

- `Experimental`
- `YouTube playback is experimental and may stop working when YouTube changes its service.`

The badge remains short in every language. The explanatory line may wrap within the existing 420-point sheet width.

## Validation

The Video library contract will require the title row, `Experimental` badge, explanatory text, and localization keys. The test must fail before the UI and localization are added, then pass after the minimal implementation.

Verification covers:

- the focused Video library and YouTubeKit contracts;
- JSON validity for `Localizable.xcstrings` and `git diff --check`;
- exact Light and Video builds, preserving the Light dependency boundary;
- a direct UI check of the Add Link sheet in the exact Video build.

## Integration Scope

The final YouTube streaming commit and merge must exclude unrelated Reader, waveform alignment, dictionary, and mining changes already present in the worktree. No release, tag, push, or worktree deletion is part of this task.
