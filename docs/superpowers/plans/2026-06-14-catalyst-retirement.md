# Catalyst Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Catalyst and ShareExtension completely, promote the native macOS app to the historical `Hoshi Reader` identity, and produce an unsigned native DMG release pipeline.

**Architecture:** Keep the existing Native shell and shared SwiftUI/services/assets, then delete legacy targets and implementations from the outside inward. Protect the transition with repository contract checks, native Debug/Release builds, Reader automation, and DMG inspection.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WKWebView, Xcode project format, Bash, GitHub Actions, `hdiutil`, `plutil`.

---

### Task 1: Add Retirement Contract Checks

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`
- Create: `script/verify_native_release_contract.sh`
- Modify: `script/verify_reader_harness.sh`

- [ ] Add assertions that the project, scripts, and release workflow reference only the native scheme/product and historical bundle id.
- [ ] Assert Catalyst scripts, ShareExtension, UIKit Reader wrappers, and Catalyst destinations are absent.
- [ ] Run the checks and confirm they fail against the current repository.

### Task 2: Promote Native Product Identity

**Files:**
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj`
- Replace: `Hoshi Reader.xcodeproj/xcshareddata/xcschemes/Hoshi Reader.xcscheme`
- Modify: `NativeMac/HoshiNativeMacApp.swift`
- Modify: `HoshiReader-Info.plist`
- Modify: `script/build_and_run_native.sh`

- [ ] Remove Catalyst and ShareExtension target objects, build phases, dependencies, configurations, products, and synchronized membership sets.
- [ ] Rename the native target/product to `Hoshi Reader`, set `PRODUCT_BUNDLE_IDENTIFIER = de.manhhao.hoshi`, and retain native macOS deployment settings.
- [ ] Point the shared scheme at the surviving native target.
- [ ] Remove iOS-only plist keys while retaining document and URL declarations.
- [ ] Update local build/run process and bundle discovery names.
- [ ] Run `xcodebuild -list` and unsigned Debug/Release builds.

### Task 3: Delete Legacy Implementations

**Files:**
- Delete: `App/`
- Delete: `ShareExtension/`
- Delete: `Features/Reader/ReaderView/ReaderView.swift`
- Delete: `Features/Reader/ReaderView/ReaderViewModel.swift`
- Delete: `Features/Reader/ReaderView/ReaderWindow.swift`
- Delete: `Features/Reader/ReaderView/FullscreenImageView.swift`
- Delete: `Features/Reader/ReaderWebView/ReaderWebView.swift`
- Delete: `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`
- Delete: `script/build_and_run_catalyst.sh`

- [ ] Delete code used only by removed targets.
- [ ] Preserve shared JavaScript and geometry helpers used by Native.
- [ ] Remove stale static-test reads and assertions for deleted files.
- [ ] Run the retirement contract and native build.

### Task 4: Collapse Shared Platform Branches

**Files:**
- Modify: shared files reported by `rg 'canImport\\(UIKit\\)|targetEnvironment\\(macCatalyst\\)|import UIKit'`.

- [ ] Remove UIKit-only branches where an AppKit implementation already exists.
- [ ] Keep only narrowly required legacy color decoding for persisted `UIColor` archives.
- [ ] Replace remaining Catalyst platform conditions with direct macOS behavior.
- [ ] Run Swift script tests and native Debug build.

### Task 5: Migrate Unsigned Native Packaging

**Files:**
- Modify: `script/package_mac.sh`
- Modify: `script/release_mac.sh`
- Modify: `.github/workflows/release-mac.yml`
- Create: `script/test_package_mac.sh`

- [ ] Build the native Release product with signing disabled.
- [ ] Verify app name, bundle id, version, executable, DMG layout, DMG integrity, and checksum.
- [ ] Update release notes to state that the app is unsigned.
- [ ] Change the version bump commit to `chore(release): bump version to <version>`.
- [ ] Run packaging with the current version and inspect the mounted DMG.

### Task 6: Align Documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/TODO.md`
- Modify: `docs/MAC_NATIVE_MIGRATION_INVENTORY.md`
- Modify: `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`
- Modify: `docs/READER_REGRESSION_TESTING.md`
- Modify or archive: `docs/mac-catalyst-interactions.md`
- Modify: agent development guides where active commands are stale.

- [ ] Remove Catalyst as a current target, command, release path, or validation requirement.
- [ ] Record Native as the sole app and unsigned DMG as the release format.
- [ ] Keep historical release statements clearly labeled as history.

### Task 7: Final Verification And Commits

**Files:**
- All modified files.

- [ ] Run repository contract checks and `git diff --check`.
- [ ] Run native Debug and Release unsigned builds.
- [ ] Run Reader harness, Lab smoke capture, popup scenario capture, and Sasayaki highlight scenario capture.
- [ ] Run package test, `hdiutil verify`, mount inspection, and checksum verification.
- [ ] Confirm the working tree contains no generated fixtures, mounted volumes, or release artifacts.
- [ ] Commit coherent slices using Conventional Commits.
