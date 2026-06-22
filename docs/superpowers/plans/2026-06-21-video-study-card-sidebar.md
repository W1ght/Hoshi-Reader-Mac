# Video Study Card Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Mining History, Transcript, and Chapters as clickable Liquid Glass cards, brighten the sidebar in light appearance, and make the user's current subtitle lookup highlight color the product default.

**Architecture:** Add one Video-only reusable card container that owns hover, selection, hit shape, glass/fallback rendering, and spacing. Keep each tab responsible only for its content and seek/copy/delete actions. Use a semantic light/dark sidebar background and preserve stored user color preferences while changing only the missing-value fallback.

**Tech Stack:** SwiftUI, macOS 26 Liquid Glass with material fallback, UserDefaults-backed `UserConfig`, standalone Swift contract tests.

---

### Task 1: Lock the unified card and default-color contracts

**Files:**
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `script/test_video_settings_contract.swift`

- [ ] Add assertions that all three lists render through `VideoStudyListCard`, use nonzero card spacing, keep full-row seek actions, and retain history copy/delete actions.
- [ ] Add assertions that the sidebar uses an appearance-aware bright background with Liquid Glass/material treatment.
- [ ] Add an assertion that the missing-value fallback for `videoSubtitleLookupHighlightColor` is `#B5C1CB3E` expressed as sRGB components.
- [ ] Run both tests and verify they fail because the shared card and new fallback do not exist yet.

### Task 2: Implement the shared Liquid Glass card

**Files:**
- Create: `Features/Video/VideoStudyListCard.swift`
- Modify: `Features/Video/VideoMiningHistorySidebar.swift`
- Modify: `Features/Video/Subtitles/SubtitleTranscriptView.swift`

- [ ] Add `VideoStudyListCard`, with whole-card button semantics, hover feedback, selected-state tint, a 14-point continuous corner radius, macOS 26 interactive glass, and a thin-material fallback.
- [ ] Convert chapter rows to spaced cards and preserve current-chapter auto-scroll and selected state.
- [ ] Convert transcript rows to spaced cards and preserve windowed loading, current-cue auto-scroll, and primary/secondary subtitle text.
- [ ] Convert history rows to the same card shell; make the content area jump on click and retain trailing copy/delete buttons as distinct hit targets.
- [ ] Run the narrow Liquid Glass contract and verify it passes.

### Task 3: Brighten the sidebar and freeze the current highlight default

**Files:**
- Modify: `Features/Video/VideoMiningHistorySidebar.swift`
- Modify: `Core/UserConfig.swift`

- [ ] Use a near-white semantic sidebar glass base in light appearance and a dark semantic glass base in dark appearance, while keeping the leading divider.
- [ ] Replace the missing-value lookup-highlight fallback with sRGB red `181/255`, green `193/255`, blue `203/255`, opacity `62/255`; do not overwrite existing UserDefaults values.
- [ ] Run the Video settings and Liquid Glass contracts and verify they pass.

### Task 4: Verify both product variants

**Files:**
- Modify only if current user-visible architecture text becomes inaccurate: `docs/CHANGELOG.md`, `docs/VIDEO_LEARNING_ARCHITECTURE.md`

- [ ] Run `swift script/test_video_settings_contract.swift`.
- [ ] Run `swift script/test_video_liquid_glass_contract.swift`.
- [ ] Run `./script/verify_video_variant_contract.sh`.
- [ ] Run `./script/build_and_run.sh --verify` and confirm the exact Light executable path and bundle identifier.
- [ ] Run `./script/build_and_run.sh --video --verify` and confirm the exact Video executable path and bundle identifier.
- [ ] In the exact Video build, verify light appearance, card hover/selection, full-card seek, history copy/delete, and persisted custom highlight behavior; report any UI scenario that cannot be exercised.
