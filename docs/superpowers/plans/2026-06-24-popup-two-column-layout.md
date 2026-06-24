# Popup Two-Column Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add upstream's optional glossary-card masonry layout to every native macOS popup surface while preserving Mac scaling, profiles, custom CSS, and native controls.

**Architecture:** Persist the preference in `UserConfig` and `DictionaryProfileSettings`, then inject it through the two existing popup payload builders into the shared `PopupWebView` renderer. `popup.js` groups glossary cards and uses CSS masonry when available or a scaled `ResizeObserver` fallback; `popup.css` provides the always-on upstream card styling.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WKWebView, JavaScript, CSS, String Catalogs, shell-driven Swift contract tests.

**Commit policy:** Do not create commits unless the user explicitly authorizes them. The repository currently contains unrelated Reader changes that must remain untouched.

---

## File map

- Create `script/test_popup_two_column_layout.swift`: focused source contract for persistence, settings, injection, masonry behavior, styling, localization, and changelog coverage.
- Modify `script/test_profile_repository.swift`: prove older dictionary profile JSON decodes without the new key.
- Modify `Models/Profile.swift`: backward-compatible optional profile field for the new dictionary preference.
- Modify `Core/UserConfig.swift`: runtime preference, UserDefaults persistence, and profile snapshot/apply mapping.
- Modify `Features/Settings/DictionaryView.swift`: localized toggle and guidance.
- Modify `Features/Settings/AppearanceView.swift`: extend the popup height range for the larger layout.
- Modify `Features/Popup/PopupView.swift`: inject the preference for Reader, Quick Lookup, and Video popup payloads.
- Modify `Features/Dictionary/DictionarySearchView.swift`: inject the preference for the Dictionary page payload.
- Modify `Features/Popup/popup.js`: shared glossary grouping and masonry engine.
- Modify `Features/Popup/popup.css`: upstream glossary-card appearance using Mac scale tokens.
- Modify `Dictionaries.xcstrings`: label and help-text translations.
- Modify `docs/CHANGELOG.md`: user-visible Unreleased entry.
- Verify, but do not otherwise modify, the user's current `NativeMac/NativeReaderView.swift`, `docs/READER_REGRESSION_TESTING.md`, and `script/test_reader_popup_sasayaki_regressions.swift` changes.

### Task 1: Add the failing popup contract

**Files:**
- Create: `script/test_popup_two_column_layout.swift`

- [ ] **Step 1: Create the source contract**

Create the file with the complete contract below:

```swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let profile = try source("Models/Profile.swift")
let userConfig = try source("Core/UserConfig.swift")
let dictionarySettings = try source("Features/Settings/DictionaryView.swift")
let appearanceSettings = try source("Features/Settings/AppearanceView.swift")
let popupView = try source("Features/Popup/PopupView.swift")
let dictionarySearch = try source("Features/Dictionary/DictionarySearchView.swift")
let popupScript = try source("Features/Popup/popup.js")
let popupStyles = try source("Features/Popup/popup.css")
let dictionariesCatalog = try source("Dictionaries.xcstrings")
let changelog = try source("docs/CHANGELOG.md")

require(
    profile.contains("var twoColumnLayout: Bool? = nil")
        && profile.contains("twoColumnLayout: false"),
    "dictionary profiles should decode the new preference compatibly and default it off"
)
require(
    userConfig.contains("var twoColumnLayout: Bool {")
        && userConfig.contains("Self.defaults.set(twoColumnLayout, forKey: \"twoColumnLayout\")")
        && userConfig.contains("self.twoColumnLayout = defaults.object(forKey: \"twoColumnLayout\") as? Bool ?? false")
        && userConfig.contains("twoColumnLayout: twoColumnLayout")
        && userConfig.contains("twoColumnLayout = settings.twoColumnLayout ?? false"),
    "UserConfig should persist and map the two-column profile preference"
)
require(
    dictionarySettings.contains("NativeSettingsToggle(\"Two-Column Layout\", isOn: $userConfig.twoColumnLayout)")
        && dictionarySettings.contains("Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens."),
    "Dictionary Settings should expose the localized toggle and guidance"
)
require(
    appearanceSettings.contains("in: 100...800, step: 10"),
    "popup height should support the upstream 800-point maximum"
)
require(
    popupView.contains(#"window.twoColumnLayout = \(userConfig.twoColumnLayout);"#)
        && dictionarySearch.contains(#"window.twoColumnLayout = \(userConfig.twoColumnLayout);"#),
    "every popup payload builder should inject the shared preference"
)
require(
    popupScript.contains("function layoutMasonry()")
        && popupScript.contains("function scheduleMasonry()")
        && popupScript.contains("function observeMasonry(root)")
        && popupScript.contains("className: 'glossary-sections'")
        && popupScript.contains("classList.toggle('single-section', dictNames.length === 1)")
        && popupScript.contains("new ResizeObserver(scheduleMasonry)")
        && popupScript.contains("window.twoColumnLayout && !document.getElementById('popup-two-column-layout')")
        && popupScript.contains("syncButtonFrames();"),
    "popup.js should implement upstream masonry with a resize fallback and button synchronization"
)
require(
    popupStyles.contains(".glossary-group {")
        && popupStyles.contains("border-radius: calc(8px * var(--popup-scale));")
        && popupStyles.contains("border: var(--popup-space-1) solid rgba(0, 0, 0, 0.14);")
        && popupStyles.contains(".glossary-sections > .glossary-group"),
    "glossary cards should use the scaled upstream presentation"
)
require(
    dictionariesCatalog.contains("\"Two-Column Layout\"")
        && dictionariesCatalog.contains("\"双栏布局\"")
        && dictionariesCatalog.contains("\"Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens.\"")
        && dictionariesCatalog.contains("\"将词典释义排列为两栏。建议仅在全宽或较大的查词框中使用。\""),
    "the new visible strings should include Simplified Chinese translations"
)
require(
    changelog.contains("two-column glossary layout"),
    "the user-visible popup layout should be recorded under Unreleased"
)

print("PASS: popup two-column layout contract")
```

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
swift script/test_popup_two_column_layout.swift
```

Expected: exit code `1` with `FAIL: dictionary profiles should decode the new preference compatibly and default it off`.

### Task 2: Persist and expose the preference

**Files:**
- Modify: `Models/Profile.swift:204-229`
- Modify: `Core/UserConfig.swift:154-166, 676-686, 899-926`
- Modify: `Features/Settings/DictionaryView.swift:428-451`
- Modify: `Features/Settings/AppearanceView.swift:319-324`
- Modify: `Features/Popup/PopupView.swift:595-603`
- Modify: `Features/Dictionary/DictionarySearchView.swift:377-385`
- Test: `script/test_popup_two_column_layout.swift`
- Test: `script/test_profile_repository.swift:16-35`

- [ ] **Step 1: Add a legacy-profile decoding assertion**

At the end of `testProfileSettingsDefaultsAndRoundTrip()`, add this legacy payload without the new key:

```swift
let legacyDictionaryData = Data(#"""
{
    "dictionaryTabDefault":false,
    "scanNonJapaneseText":true,
    "maxResults":16,
    "scanLength":16,
    "collapseMode":"Expand All",
    "expandFirstDictionary":false,
    "compactGlossaries":true,
    "showExpressionTags":false,
    "harmonicFrequency":false,
    "deduplicatePitchAccents":false,
    "compactPitchAccents":true,
    "customCSS":""
}
"""#.utf8)
let legacyDictionary = try JSONDecoder().decode(
    DictionaryProfileSettings.self,
    from: legacyDictionaryData
)
let legacyTwoColumn = Mirror(reflecting: legacyDictionary).children.first {
    $0.label == "twoColumnLayout"
}
precondition(legacyTwoColumn != nil)
precondition(String(describing: legacyTwoColumn!.value) == "nil")
```

- [ ] **Step 2: Run the profile test and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift \
  Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift \
  script/test_profile_repository.swift \
  -o /tmp/test_profile_repository && /tmp/test_profile_repository
```

Expected: the executable exits non-zero because the reflected legacy profile does not yet contain `twoColumnLayout`.

- [ ] **Step 3: Add backward-compatible profile storage**

Add the optional field after `expandFirstDictionary` so old `dictionary_settings.json` files decode without a custom decoder:

```swift
var expandFirstDictionary: Bool
var twoColumnLayout: Bool? = nil
var compactGlossaries: Bool
```

Set the explicit default in `DictionaryProfileSettings.defaults`:

```swift
expandFirstDictionary: false,
twoColumnLayout: false,
compactGlossaries: true,
```

- [ ] **Step 4: Add UserConfig persistence and profile mapping**

Add the runtime property beside the existing dictionary layout settings:

```swift
var twoColumnLayout: Bool {
    didSet { Self.defaults.set(twoColumnLayout, forKey: "twoColumnLayout") }
}
```

Initialize it immediately after `expandFirstDictionary`:

```swift
self.expandFirstDictionary = defaults.object(forKey: "expandFirstDictionary") as? Bool ?? false
self.twoColumnLayout = defaults.object(forKey: "twoColumnLayout") as? Bool ?? false
self.compactGlossaries = defaults.object(forKey: "compactGlossaries") as? Bool ?? true
```

Include it in `dictionaryProfileSettings()`:

```swift
expandFirstDictionary: expandFirstDictionary,
twoColumnLayout: twoColumnLayout,
compactGlossaries: compactGlossaries,
```

Apply missing legacy values as false in `apply(dictionaryProfileSettings:)`:

```swift
expandFirstDictionary = settings.expandFirstDictionary
twoColumnLayout = settings.twoColumnLayout ?? false
compactGlossaries = settings.compactGlossaries
```

- [ ] **Step 5: Add the settings control and guidance**

Change the Behaviour card to include the toggle first and use its footer for the upstream guidance:

```swift
NativeSettingsSectionCard {
    Text("Behaviour", tableName: "Dictionaries")
} content: {
    NativeSettingsToggle("Two-Column Layout", isOn: $userConfig.twoColumnLayout)
    NativeSettingsSeparator()
    NativeSettingsToggle("Compact Glossaries", isOn: $userConfig.compactGlossaries)
    NativeSettingsSeparator()
    NativeSettingsToggle("Show Expression Tags", isOn: $userConfig.showExpressionTags)
    NativeSettingsSeparator()
    NativeSettingsToggle("Harmonic Frequency", isOn: $userConfig.harmonicFrequency)
    NativeSettingsSeparator()
    NativeSettingsToggle("Deduplicate Pitch Accents", isOn: $userConfig.deduplicatePitchAccents)
    NativeSettingsSeparator()
    NativeSettingsToggle("Compact Pitch Accents", isOn: $userConfig.compactPitchAccents)
    NativeSettingsSeparator()
    NativeSettingsSliderRow(
        title: "Mac Hover Delay",
        value: "\(userConfig.desktopLookupHoverDelayMs) ms"
    ) {
        Slider(value: .init(
            get: { Double(userConfig.desktopLookupHoverDelayMs) },
            set: { userConfig.desktopLookupHoverDelayMs = Int($0) }
        ), in: 0...250, step: 5)
    }
} footer: {
    Text(
        "Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens.",
        tableName: "Dictionaries"
    )
}
```

- [ ] **Step 6: Expand the popup height range**

Change only the height slider range:

```swift
Slider(value: .init(
    get: { Double(userConfig.popupHeight) },
    set: { userConfig.popupHeight = Int($0) }
), in: 100...800, step: 10)
```

- [ ] **Step 7: Inject the preference through both payload builders**

In both `PopupView.buildContent` and `DictionarySearchView.buildPopupPayload`, insert:

```swift
window.expandFirstDictionary = \(userConfig.expandFirstDictionary);
window.twoColumnLayout = \(userConfig.twoColumnLayout);
window.collapsedDictionaries = \(collapsedDictionaries);
```

- [ ] **Step 8: Run the contract and observe the next expected failure**

Run:

```bash
swift script/test_popup_two_column_layout.swift
```

Expected: configuration assertions pass; exit code `1` at `FAIL: popup.js should implement upstream masonry with a resize fallback and button synchronization`.

- [ ] **Step 9: Verify profile encoding compatibility**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift \
  Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift \
  script/test_profile_repository.swift \
  -o /tmp/test_profile_repository && /tmp/test_profile_repository
```

Expected: `Profile repository tests passed`.

### Task 3: Implement shared masonry rendering and card styling

**Files:**
- Modify: `Features/Popup/popup.js:1680-1825`
- Modify: `Features/Popup/popup.css:70-80, 335-365`
- Test: `script/test_popup_two_column_layout.swift`

- [ ] **Step 1: Add the masonry scheduler before `window.renderPopup`**

Insert:

```javascript
const HAS_NATIVE_MASONRY = CSS.supports('display', 'grid-lanes');
let masonryRaf = null;
let masonryObserver = null;

function masonryGap() {
    const value = parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue('--popup-space-5')
    );
    return Number.isFinite(value) ? value : 5;
}

function layoutMasonry() {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY) {
        return;
    }
    const gap = masonryGap();
    document.querySelectorAll('#entries-container .glossary-sections:not(.single-section)').forEach(section => {
        const columnWidth = (section.clientWidth - gap) / 2;
        const columnHeights = [0, 0];
        [...section.children].forEach(item => {
            const column = columnHeights[0] <= columnHeights[1] ? 0 : 1;
            const x = column * (columnWidth + gap);
            const y = columnHeights[column];
            item.style.width = `${columnWidth}px`;
            item.style.transform = `translate(${x}px, ${y}px)`;
            item.style.visibility = 'visible';
            columnHeights[column] += item.offsetHeight + gap;
        });
        section.style.height = `${Math.max(columnHeights[0], columnHeights[1]) - gap}px`;
    });
}

function scheduleMasonry() {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY || masonryRaf) {
        return;
    }
    masonryRaf = requestAnimationFrame(() => {
        masonryRaf = null;
        layoutMasonry();
        syncButtonFrames();
    });
}

function observeMasonry(root) {
    if (!window.twoColumnLayout || HAS_NATIVE_MASONRY || root.classList.contains('single-section')) {
        return;
    }
    masonryObserver ??= new ResizeObserver(scheduleMasonry);
    [...root.children].forEach(item => masonryObserver.observe(item));
    scheduleMasonry();
}

window.addEventListener('resize', () => {
    requestAnimationFrame(syncButtonFrames);
    scheduleMasonry();
});

document.addEventListener('toggle', () => {
    requestAnimationFrame(syncButtonFrames);
    scheduleMasonry();
}, true);
```

Remove the existing standalone resize/toggle listeners near `syncButtonFrames()` so each event has one listener. Keep the existing scroll listener unchanged.

- [ ] **Step 2: Group glossary cards during incremental rendering**

After appending `entryDiv`, create the shared container:

```javascript
const glossarySections = el('div', { className: 'glossary-sections' });
entryDiv.appendChild(glossarySections);
```

Replace the dictionary loop with:

```javascript
const dictNames = Object.keys(grouped);
glossarySections.classList.toggle('single-section', dictNames.length === 1);
for (let dictIdx = 0; dictIdx < dictNames.length; dictIdx++) {
    glossarySections.appendChild(
        createGlossarySection(dictNames[dictIdx], grouped[dictNames[dictIdx]], dictIdx === 0, idx)
    );
    if (idx === 0) {
        scheduleMasonry();
        await new Promise(r => requestAnimationFrame(r));
    }
}
observeMasonry(glossarySections);
```

In `restore(_:)`, schedule a reflow after restoring nodes:

```javascript
requestAnimationFrame(syncButtonFrames);
scheduleMasonry();
requestAnimationFrame(() => {
    document.scrollingElement.scrollTop = s.scrollTop;
});
```

- [ ] **Step 3: Inject the upstream layout style**

Before the compact-glossaries style block in `window.renderPopup`, add:

```javascript
if (window.twoColumnLayout && !document.getElementById('popup-two-column-layout')) {
    const layoutStyle = document.createElement('style');
    layoutStyle.id = 'popup-two-column-layout';
    layoutStyle.textContent = `
        .glossary-sections {
            ${HAS_NATIVE_MASONRY
            ? `display: grid-lanes;
            grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
            gap: var(--popup-space-5);
            align-items: start;`
            : `position: relative;`}
            margin-top: var(--popup-space-8);
        }
        .glossary-sections > .glossary-group {
            margin-top: 0;
        }
        ${HAS_NATIVE_MASONRY ? '' : `
        .glossary-sections:not(.single-section) > .glossary-group {
            position: absolute;
            left: 0;
            top: 0;
            visibility: hidden;
        }
        `}
        .glossary-sections.single-section {
            display: block;
        }
    `;
    document.body.appendChild(layoutStyle);
}
```

- [ ] **Step 4: Port the scaled glossary-card style**

Change body and entry spacing:

```css
body {
    overflow-x: hidden;
    font-size: var(--popup-body-font-size);
    line-height: var(--line-height);
    padding: 0 var(--popup-space-18) 0 var(--popup-space-5);
}

.entry {
    position: relative;
    padding: var(--popup-space-4) 0 var(--popup-space-5);
}
```

Replace the `.glossary-group` rule and add its dark-mode variant:

```css
.glossary-group {
    position: relative;
    margin-top: var(--popup-space-5);
    min-width: 0;
    padding: var(--popup-space-6) var(--popup-space-8);
    border-radius: calc(8px * var(--popup-scale));
    border: var(--popup-space-1) solid rgba(0, 0, 0, 0.14);
    box-shadow:
        inset 0 0 0 var(--popup-space-1) rgba(255, 255, 255, 0.42),
        0 0 0 var(--popup-space-1) rgba(255, 255, 255, 0.22),
        0 var(--popup-space-1) var(--popup-space-2) rgba(0, 0, 0, 0.1);
}

.glossary-sections > .glossary-group {
    margin-top: 0;
}

@media (prefers-color-scheme: dark) {
    .glossary-group {
        border-color: rgba(255, 255, 255, 0.09);
        box-shadow: 0 var(--popup-space-1) var(--popup-space-1) rgba(0, 0, 0, 0.36);
    }
}
```

- [ ] **Step 5: Run focused renderer verification**

Run:

```bash
swift script/test_popup_two_column_layout.swift
```

Expected: masonry and CSS assertions pass; the next failure is localization or changelog coverage.

Run:

```bash
/Users/wight/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --check Features/Popup/popup.js
swift script/test_popup_duplicate_button_rendering.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library script/test_mining_context_ui_contract.swift \
  -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
```

Expected: JavaScript syntax check exits `0`; both Swift contracts print `PASS`.

### Task 4: Localize and document the user-visible change

**Files:**
- Modify: `Dictionaries.xcstrings`
- Modify: `docs/CHANGELOG.md:5-8`
- Test: `script/test_popup_two_column_layout.swift`

- [ ] **Step 1: Add the label translation**

Add this sorted string-catalog entry:

```json
"Two-Column Layout" : {
  "comment" : "Context: Settings > Dictionaries > Behaviour. Enables the optional two-column glossary-card layout.",
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "双栏布局"
      }
    },
    "zh-Hant" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "雙欄佈局"
      }
    }
  }
}
```

- [ ] **Step 2: Add the guidance translation**

Add:

```json
"Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens." : {
  "comment" : "Context: Settings > Dictionaries > Behaviour. Guidance for the optional two-column glossary-card layout.",
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "将词典释义排列为两栏。建议仅在全宽或较大的查词框中使用。"
      }
    },
    "zh-Hant" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "將詞典釋義排列為兩欄。建議僅在全寬或較大的查詞框中使用。"
      }
    }
  }
}
```

- [ ] **Step 3: Add the Unreleased changelog entry**

Under `## Unreleased`, add:

```markdown
- Added an optional two-column glossary layout with balanced dictionary cards for larger and full-width lookup popups.
```

- [ ] **Step 4: Verify catalogs and complete contract**

Run:

```bash
jq empty Dictionaries.xcstrings Localizable.xcstrings
swift script/test_popup_two_column_layout.swift
git diff --check
```

Expected: both catalogs parse, the contract prints `PASS: popup two-column layout contract`, and `git diff --check` exits `0`.

### Task 5: Build and manually verify the exact native app

**Files:**
- Verify all files above.
- Do not modify user books, bookmarks, sidecars, Reader settings, or reading progress for test setup.

- [ ] **Step 1: Run the complete focused test set**

Run:

```bash
swift script/test_popup_two_column_layout.swift
swift script/test_popup_duplicate_button_rendering.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library script/test_mining_context_ui_contract.swift \
  -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
/Users/wight/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --check Features/Popup/popup.js
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Models/Anki.swift Models/Book.swift Models/Profile.swift Models/Dictionary.swift \
  Core/ProfileRepository.swift Core/ProfileDictionaryBackup.swift \
  script/test_profile_repository.swift \
  -o /tmp/test_profile_repository && /tmp/test_profile_repository
```

Expected: every command exits `0` with its PASS message.

- [ ] **Step 2: Build and launch the exact Light app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build succeeds; the script verifies bundle identifier `moe.shishamo.hoshi` and the running executable path inside this build's DerivedData product.

- [ ] **Step 3: Verify Dictionary popup behavior**

Using the exact running app, check:

- Toggle off: existing single-column layout remains usable.
- Toggle on with one dictionary: the card remains full width.
- Toggle on with multiple dictionaries: cards balance into two columns.
- Collapse and expand cards: columns reflow without overlap or stale blank space.
- Resize and full-width modes: widths and positions recompute.
- Back/forward entry navigation, keyboard current-entry navigation, nested lookup, images, custom CSS, audio, and Anki buttons remain usable.

Expected: no horizontal overflow, clipped cards, overlapping cards, misplaced native buttons, or lost selection.

- [ ] **Step 4: Verify Reader popup behavior without altering user data**

With an already available EPUB only, check normal and full-screen Reader popups, nested lookup, popup dismissal, and return to reading. If no safe existing EPUB or multi-dictionary result is available, skip this step and record the exact uncovered scenarios.

- [ ] **Step 5: Review scope and report limitations**

Run:

```bash
git status --short --branch
git diff --stat
git diff --check
git diff -- \
  Models/Profile.swift Core/UserConfig.swift \
  Features/Settings/DictionaryView.swift Features/Settings/AppearanceView.swift \
  Features/Popup/PopupView.swift Features/Dictionary/DictionarySearchView.swift \
  Features/Popup/popup.js Features/Popup/popup.css \
  Dictionaries.xcstrings docs/CHANGELOG.md \
  script/test_popup_two_column_layout.swift \
  docs/superpowers/specs/2026-06-24-popup-two-column-layout-design.md \
  docs/superpowers/plans/2026-06-24-popup-two-column-layout.md
```

Expected: only planned files plus the pre-existing unrelated Reader changes appear. Final reporting must separate automated verification from visually verified scenarios and explicitly list anything not tested.
