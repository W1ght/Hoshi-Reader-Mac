# Native Bookshelf Sasayaki Match Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the v0.5.0 Sasayaki SRT matching flow and its grouped-card match sheet from the native macOS bookshelf.

**Architecture:** Reconnect the existing `BookCell` → `ShelfView` callback to state owned by `NativeBookshelfReuseView`. Present `SasayakiMatchView` as an item sheet, render it with the shared native settings cards and a custom v0.5.0-style header, and keep all matching, parsing, and sidecar persistence in the existing services.

**Tech Stack:** SwiftUI, native macOS, Swift script contract tests, Xcode build script, Computer Use.

---

### Task 1: Add a failing native bookshelf matching contract

**Files:**
- Create: `script/test_native_bookshelf_sasayaki_match_contract.swift`
- Read: `NativeMac/NativeReuseViews.swift`

- [ ] **Step 1: Write the failing contract**

```swift
import Foundation

let source = try String(contentsOfFile: "NativeMac/NativeReuseViews.swift", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

require(source.contains("@State private var sasayakiBook: BookMetadata?"), "Native bookshelf must own the selected Sasayaki match book")
require(source.contains(".sheet(item: $sasayakiBook)"), "Native bookshelf must present the existing Sasayaki match sheet")
require(source.contains("SasayakiMatchView(book: book, viewModel: viewModel)"), "Native bookshelf must reuse SasayakiMatchView")
require(source.contains("@Binding var sasayakiBook: BookMetadata?"), "Bookshelf sections must receive the match selection binding")
require(source.contains("onMatch: { sasayakiBook = $0 }"), "Shelf match actions must select the requested book")
require(!source.contains("onMatch: { _ in }"), "Native bookshelf must not discard match actions")

print("Native bookshelf Sasayaki match contract passed")
```

- [ ] **Step 2: Verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
```

Expected: failure stating that the native bookshelf does not own the selected match book.

### Task 2: Reconnect the existing match sheet

**Files:**
- Modify: `NativeMac/NativeReuseViews.swift`

- [ ] **Step 1: Add the selected-book state and sheet**

Add to `NativeBookshelfReuseView`:

```swift
@State private var sasayakiBook: BookMetadata?
```

Pass the binding to `NativeBookshelfSectionsView`:

```swift
sasayakiBook: $sasayakiBook,
```

Attach the existing sheet beside the shelf-management sheet:

```swift
.sheet(item: $sasayakiBook) { book in
    SasayakiMatchView(book: book, viewModel: viewModel)
}
```

- [ ] **Step 2: Connect sections to `ShelfView`**

Add to `NativeBookshelfSectionsView`:

```swift
@Binding var sasayakiBook: BookMetadata?
```

Replace the discarded callback with:

```swift
onMatch: { sasayakiBook = $0 }
```

- [ ] **Step 3: Verify GREEN and parse**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse NativeMac/NativeReuseViews.swift
```

Expected: contract prints `Native bookshelf Sasayaki match contract passed`; parser exits 0.

### Task 3: Update user-visible documentation

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md` only if it currently claims native bookshelf matching is missing

- [ ] **Step 1: Record the restored behavior**

Add this Unreleased entry:

```markdown
- Restored Sasayaki SRT matching from the native Bookshelf book context menu.
```

- [ ] **Step 2: Remove any now-stale TODO statement**

Search with:

```bash
rg -n -i "sasayaki|match" docs/TODO.md
```

Only update an existing status line if the implementation makes it false.

### Task 4: Build and actual-data UI verification

**Files:**
- Verify: exact DerivedData app produced by `script/build_and_run.sh`
- Protect: target book's existing `sasayaki_match.json`

- [ ] **Step 1: Build and launch the Light app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: bundle id `moe.shishamo.hoshi` and a verified full DerivedData executable path.

- [ ] **Step 2: Verify the UI with Computer Use**

Using the exact app path, verify:

1. Enable Sasayaki if needed without changing unrelated settings.
2. Right-click a local book and confirm “Match” appears.
3. Open the match sheet and confirm SRT picker, search window, disabled Match button before selection, and Done dismissal.
4. Close the sheet and confirm the bookshelf remains usable.

- [ ] **Step 3: Verify actual matching safely**

If a local SRT is available, back up the selected book's current `sasayaki_match.json`, run matching, confirm the match rate appears and Reader recognizes the result, then restore the original sidecar. Do not import, replace, or delete books. If no suitable SRT exists, report this exact coverage gap.

- [ ] **Step 4: Final verification**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
git diff --check
```

Expected: contract passes and `git diff --check` exits 0.

No commit, push, or release is included because the repository requires explicit user authorization.

### Task 5: Add a failing v0.5.0 match-sheet visual contract

**Files:**
- Modify: `script/test_native_bookshelf_sasayaki_match_contract.swift`
- Test: `Features/Sasayaki/SasayakiMatchView.swift`

- [ ] **Step 1: Require the shared card layout and custom header**

Add contract assertions for these production tokens:

```swift
require(matchView.contains("NativeSettingsForm("), "Match sheet must use the native grouped settings form")
require(matchView.contains("NativeSettingsSectionCard"), "Match sheet must use rounded native section cards")
require(matchView.contains("private var matchHeader: some View"), "Match sheet must own a centered v0.5.0-style header")
require(matchView.contains("SasayakiMatchLayout.sheetWidth"), "Match sheet must have an explicit stable width")
require(matchView.contains("SasayakiMatchLayout.sheetHeight"), "Match sheet must have an explicit stable height")
require(!matchView.contains("Form {"), "Match sheet must not fall back to the compressed macOS Form layout")
require(!matchView.contains("ToolbarItem(placement: .confirmationAction)"), "Done must remain in the top-right custom header")
```

- [ ] **Step 2: Verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
```

Expected: failure stating that the match sheet does not use the native grouped settings form.

### Task 6: Rebuild the sheet with native grouped cards

**Files:**
- Modify: `Features/Sasayaki/SasayakiMatchView.swift`

- [ ] **Step 1: Define stable sheet geometry**

Add:

```swift
private enum SasayakiMatchLayout {
    static let sheetWidth: CGFloat = 680
    static let sheetHeight: CGFloat = 620
}
```

- [ ] **Step 2: Replace `NavigationStack` and `Form` with the v0.5.0 hierarchy**

Use this root structure:

```swift
VStack(spacing: 0) {
    matchHeader
    NativeSettingsForm(horizontalPadding: 26, verticalPadding: 12, spacing: 24) {
        fileSection
        searchSection
        if let match {
            currentMatchSection(match)
        }
    }
}
.frame(width: SasayakiMatchLayout.sheetWidth, height: SasayakiMatchLayout.sheetHeight)
```

The header must center the title independently of the trailing button:

```swift
private var matchHeader: some View {
    ZStack {
        Text("Match")
            .font(.title3.weight(.semibold))
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 14)
}
```

- [ ] **Step 3: Build the three card groups**

Use these component boundaries while preserving the existing importer and matching methods:

```swift
private var fileSection: some View {
    NativeSettingsSectionCard("File") {
        NativeSettingsRow {
            fileNameView
        } accessory: {
            Button("Open") { isImporting = true }
        }
    }
}

private var searchSection: some View {
    NativeSettingsSectionCard {
        EmptyView()
    } content: {
        VStack(alignment: .leading, spacing: 12) {
            NativeSettingsRow {
                Text("Search Window")
            } accessory: {
                Text("\(Int(searchWindow))").fontWeight(.semibold)
            }
            Slider(value: $searchWindow, in: 50...1000, step: 50)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            NativeSettingsSeparator()
            NativeSettingsButtonRow {
                Button(action: matchFile) {
                    matchButtonLabel
                }
                .disabled(fileURL == nil || isMatching)
            }
        }
    }
}

private func currentMatchSection(_ match: SasayakiMatchData) -> some View {
    NativeSettingsSectionCard("Current Match") {
        NativeSettingsRow("Match Rate") {
            Text(matchRate(for: match))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}
```

Keep the existing progress label in `matchButtonLabel`, and keep `onAppear`, `fileImporter`, `matchFile`, `matchRate` and `fileNameView` behavior unchanged.

- [ ] **Step 4: Verify GREEN and parse**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse Features/Sasayaki/SasayakiMatchView.swift
```

Expected: contract passes; parser exits 0.

### Task 7: Synchronize native migration sources of truth

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md`
- Modify: `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`

- [ ] **Step 1: Update user-visible change wording**

Use:

```markdown
- Restored Sasayaki SRT matching from the native Bookshelf with the grouped v0.5.0-style match sheet.
```

- [ ] **Step 2: Add the current native state and validation command**

Record that the native Bookshelf owns the existing Sasayaki match flow and that the sheet uses native settings cards while preserving the v0.5.0 information hierarchy. Add `script/test_native_bookshelf_sasayaki_match_contract.swift` to the TODO validation entry points.

- [ ] **Step 3: Update the migration plan**

Mark the native Bookshelf Sasayaki context-menu match sheet as restored and validated; keep Catalyst historical-only and do not add a Catalyst build requirement.

### Task 8: Build and compare against the supplied reference

**Files:**
- Verify: exact DerivedData app produced by `script/build_and_run.sh`

- [ ] **Step 1: Build and launch**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: verified bundle id `moe.shishamo.hoshi` and exact running executable path.

- [ ] **Step 2: Computer Use comparison**

Open a real book's Match sheet and compare with the supplied v0.5.0 screenshot. Verify centered title, top-right Done button, stable large sheet, File card, combined search/slider/action card, Current Match card, rounded corners, section spacing and right-aligned values in both the current wide window and a narrower window.

- [ ] **Step 3: Confirm behavior and data safety**

Verify Open, disabled Match before file selection, search-window control, existing match-rate loading and Done dismissal. Do not re-run actual matching unless the original `sasayaki_match.json` is backed up and restored byte-for-byte.

- [ ] **Step 4: Final checks**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache swift script/test_native_bookshelf_sasayaki_match_contract.swift
git diff --check
```

Expected: contract passes and diff check exits 0.
