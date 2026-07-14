# YouTube Link Experimental Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Label the YouTube Add Link sheet as experimental, explain the instability risk in Chinese and English, and merge the complete YouTubeKit/JavaScriptCore streaming feature into `main` without unrelated dirty-worktree changes.

**Architecture:** Keep the warning entirely inside `RemoteVideoLinkSheet`: a compact title badge communicates status and one secondary line explains why. Lock the visible copy with the existing source-contract test, then validate the feature in an isolated clean integration worktree so unstaged waveform, Reader, dictionary, and mining changes cannot hide missing dependencies.

**Tech Stack:** SwiftUI for macOS 26, String Catalog localization, Swift source-contract tests, Xcode Light/Video schemes, Git worktrees.

## Global Constraints

- Native macOS is the only target.
- The toolbar action remains `Add Link`; only the sheet receives the experimental warning.
- New visible strings require English, Simplified Chinese, and Traditional Chinese localizations.
- YouTube stream extraction remains `alexeichhorn/YouTubeKit` plus local JavaScriptCore with no yt-dlp or Deno.
- Only YouTube remote-streaming changes may enter `main`; unrelated dirty changes remain in this host-owned worktree.
- Do not push, tag, release, or delete the host-owned worktree.

---

### Task 1: Lock the Experimental Warning Contract

**Files:**
- Modify: `script/test_video_youtubekit_contract.swift`

**Interfaces:**
- Consumes: the source text of `Features/Video/VideoLibraryView.swift` and `Localizable.xcstrings`.
- Produces: a failing contract until the sheet contains both visible strings and localization entries.

- [ ] **Step 1: Write the failing contract**

Add the library view to the test inputs and require these exact source strings:

```swift
let libraryView = read("Features/Video/VideoLibraryView.swift")

require(
    libraryView.contains("Text(\"Experimental\")")
        && libraryView.contains("Text(\"YouTube playback is experimental and may stop working when YouTube changes its service.\")"),
    "the Add Link sheet should explain that YouTube playback is experimental"
)
```

Add both keys to `requiredLocalizedKeys`:

```swift
"Experimental",
"YouTube playback is experimental and may stop working when YouTube changes its service.",
```

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
swift script/test_video_youtubekit_contract.swift
```

Expected: failure saying the Add Link sheet should explain that YouTube playback is experimental.

---

### Task 2: Add the Badge, Explanation, and Localization

**Files:**
- Modify: `Features/Video/VideoLibraryView.swift`
- Modify: `Localizable.xcstrings`
- Modify: `docs/CHANGELOG.md`

**Interfaces:**
- Consumes: the existing `RemoteVideoLinkSheet` and String Catalog.
- Produces: a localized title badge and secondary warning with no playback behavior changes.

- [ ] **Step 1: Implement the minimal SwiftUI title block**

Replace the single heading with:

```swift
HStack(spacing: 8) {
    Text("YouTube Video")
        .font(.headline)

    Text("Experimental")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.orange.opacity(0.14), in: Capsule())
}

Text("YouTube playback is experimental and may stop working when YouTube changes its service.")
    .font(.callout)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
```

- [ ] **Step 2: Add exact String Catalog entries**

Add English-source keys with these translations:

```text
Experimental
zh-Hans: 实验性
zh-Hant: 實驗性

YouTube playback is experimental and may stop working when YouTube changes its service.
zh-Hans: YouTube 播放属于实验性功能，YouTube 服务发生变化时可能会暂时失效。
zh-Hant: YouTube 播放屬於實驗性功能，YouTube 服務發生變化時可能會暫時失效。
```

- [ ] **Step 3: Update the user-visible changelog line**

Extend the existing YouTube entry to mention that Add Link now identifies the feature as experimental.

- [ ] **Step 4: Run focused validation and verify GREEN**

Run:

```bash
swift script/test_video_youtubekit_contract.swift
swift script/test_video_library_contract.swift
jq empty Localizable.xcstrings
git diff --check
```

Expected: both contracts pass, localization parses, and the diff check is clean.

---

### Task 3: Create a YouTube-Only Commit Set

**Files:**
- Stage: YouTubeKit package resolution/project changes, `Features/Video/Remote/`, required remote playback/library/window state changes, build/package boundaries, focused tests, and YouTube truth-source documentation.
- Exclude: waveform generators/alignment, Reader window geometry, dictionary import changes, unrelated Anki media-export changes, and unrelated mining changes.

**Interfaces:**
- Consumes: the mixed dirty worktree based at `3ba5a695`.
- Produces: named branch `codex/youtubekit-javascriptcore` whose committed tree contains a self-contained YouTube feature.

- [ ] **Step 1: Audit every staged path and mixed hunk**

Use `git add <feature-only paths>` and `git add -p <mixed paths>`, then inspect:

```bash
git diff --cached --stat
git diff --cached --check
git diff --cached
```

Reject staged hunks containing waveform, Reader, dictionary, or unrelated media-export symbols.

- [ ] **Step 2: Commit the implementation**

```bash
git commit -m "feat(video): add experimental YouTube streaming"
```

The committed feature includes its tests and source-of-truth documentation.

---

### Task 4: Verify the Committed Tree in Isolation

**Files:**
- Create temporarily: a Git-owned integration worktree outside the host-owned Codex worktree.

**Interfaces:**
- Consumes: the committed `codex/youtubekit-javascriptcore` branch.
- Produces: proof that no unstaged file is needed for compilation or runtime behavior.

- [ ] **Step 1: Create a clean detached verification worktree at the feature commit**

```bash
git worktree add --detach /tmp/hoshi-youtubekit-verify codex/youtubekit-javascriptcore
```

- [ ] **Step 2: Run focused tests and exact builds there**

Run the YouTube URL, selection, caption, loader, resolver, library, player, and window contracts; run the live reference subtitle check; then run:

```bash
./script/build_and_run.sh --instance youtubekit-merge-light --verify
./script/build_and_run.sh --video --instance youtubekit-merge-video --verify
```

Expected: all tests pass and both exact app identities are verified.

- [ ] **Step 3: Inspect the Add Link sheet in the exact Video app**

Confirm that `实验性` and the warning are visible, then confirm the reference YouTube video opens and publisher subtitles render without an error alert.

---

### Task 5: Merge to Main and Reverify

**Files:**
- Update: `main` ref through a dedicated clean integration worktree.

**Interfaces:**
- Consumes: verified feature branch.
- Produces: local `main` containing the YouTube feature; no push or release.

- [ ] **Step 1: Create a temporary clean `main` integration worktree**

Because the primary repository worktree currently checks out `codex/video-waveform-alignment`, create a temporary worktree for `main`, merge `codex/youtubekit-javascriptcore` with `--no-ff`, and preserve the host worktree.

```bash
git worktree add /tmp/hoshi-youtubekit-main main
git -C /tmp/hoshi-youtubekit-main merge --no-ff codex/youtubekit-javascriptcore -m "merge: add experimental YouTube streaming"
```

- [ ] **Step 2: Re-run focused contracts and Light/Video builds on merged `main`**

Use unique build instances and require zero failures before reporting success.

- [ ] **Step 3: Remove only temporary verification/integration worktrees**

Do not remove `/Users/wight/.codex/worktrees/1d17/Hoshi-Reader` and do not delete the feature branch while it remains useful for audit.

```bash
git worktree remove /tmp/hoshi-youtubekit-verify
git worktree remove /tmp/hoshi-youtubekit-main
git worktree prune
```
