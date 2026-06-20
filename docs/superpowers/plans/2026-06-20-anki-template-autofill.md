# Anki Template Autofill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe default field mappings for Lapis, Kiku, and Senren, plus an explicit confirmed action that restores known novel mappings after the Video preset overwrote them.

**Architecture:** Keep template data, safe merge, and explicit reset behavior in `Models/Anki.swift`. Let `AnkiManager` own mutation and persistence timing. `AnkiView` exposes the destructive-to-mappings reset behind a confirmation alert. Mapping profiles are deferred without changing the current config schema.

**Tech Stack:** Swift, Foundation, AnkiConnect, Swift script tests, native macOS SwiftUI.

**Status (2026-06-20):** Implemented and verified in both Light and Video native variants. The selected Lapis configuration was explicitly restored through the confirmed UI action; no Anki card was created. Separately persisted EPUB/Video mapping profiles remain deferred to the follow-up recorded in `docs/TODO.md`.

**Regression addendum:** A real Hoshi-created Lapis note exposed that the Video preset had mapped `DefinitionPicture` to `{glossary}`. Task 6 removes only that confirmed harmful mapping and repairs only the user-authorized note.

---

### Task 1: Add failing behavior tests for field templates

**Files:**
- Create: `script/test_anki_field_templates.swift`
- Test: `Models/Anki.swift`

- [ ] **Step 1: Write tests for the upstream mappings and safe merge rules**

Create an `@main` test executable that calls `AnkiFieldTemplate.autofilledMappings(noteType:availableFields:existing:)` and asserts:

```swift
let lapis = AnkiFieldTemplate.autofilledMappings(
    noteType: "Lapis",
    availableFields: ["Expression", "MainDefinition", "Sentence", "UnknownField"],
    existing: [:]
)
precondition(lapis["Expression"] == Handlebars.expression.rawValue)
precondition(lapis["MainDefinition"] == Handlebars.glossaryFirst.rawValue)
precondition(lapis["Sentence"] == Handlebars.sentence.rawValue)
precondition(lapis["UnknownField"] == nil)

let custom = AnkiFieldTemplate.autofilledMappings(
    noteType: "Lapis",
    availableFields: ["Expression", "MainDefinition"],
    existing: ["Expression": "{custom-expression}", "MainDefinition": "   "]
)
precondition(custom["Expression"] == "{custom-expression}")
precondition(custom["MainDefinition"] == Handlebars.glossaryFirst.rawValue)

let kiku = AnkiFieldTemplate.autofilledMappings(
    noteType: "Kiku",
    availableFields: ["ExpressionAudio", "Picture"],
    existing: [:]
)
precondition(kiku["ExpressionAudio"] == Handlebars.audio.rawValue)
precondition(kiku["Picture"] == Handlebars.bookCover.rawValue)

let senren = AnkiFieldTemplate.autofilledMappings(
    noteType: "Senren",
    availableFields: ["word", "definition", "wordAudio"],
    existing: [:]
)
precondition(senren["word"] == Handlebars.expression.rawValue)
precondition(senren["definition"] == Handlebars.glossaryFirst.rawValue)
precondition(senren["wordAudio"] == Handlebars.audio.rawValue)

let unknown = ["Front": "{expression}"]
precondition(AnkiFieldTemplate.autofilledMappings(
    noteType: "Custom",
    availableFields: ["Front"],
    existing: unknown
) == unknown)
```

- [ ] **Step 2: Verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc Models/Anki.swift script/test_anki_field_templates.swift -o /tmp/test_anki_field_templates && /tmp/test_anki_field_templates
```

Expected: compile failure because `AnkiFieldTemplate` does not exist.

### Task 2: Implement the pure templates and merge behavior

**Files:**
- Modify: `Models/Anki.swift`
- Test: `script/test_anki_field_templates.swift`

- [ ] **Step 1: Add `AnkiFieldTemplate`**

Port the exact Lapis, Kiku, and Senren dictionaries from upstream commit `8ffca617204c357e69573741c70c8d57a463bfd5`, then add:

```swift
static func autofilledMappings(
    noteType: String,
    availableFields: [String],
    existing: [String: String]
) -> [String: String] {
    guard let template = templates.first(where: { $0.noteType == noteType }) else {
        return existing
    }

    let available = Set(availableFields)
    var result = existing.filter { available.contains($0.key) }
    for field in availableFields {
        guard let defaultValue = template.mappings[field] else { continue }
        if result[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            result[field] = defaultValue
        }
    }
    return result
}
```

- [ ] **Step 2: Verify GREEN**

Run the Task 1 command. Expected: `Anki field template tests passed` and exit 0.

### Task 3: Apply defaults at every selected-model boundary

**Files:**
- Modify: `Core/AnkiManager.swift`
- Modify: `Features/Settings/AnkiView.swift`
- Modify: `script/test_anki_field_templates.swift`

- [ ] **Step 1: Add the manager orchestration method**

```swift
@discardableResult
func autofillFieldMappings() -> Bool {
    guard let selectedNoteType,
          let noteType = availableNoteTypes.first(where: { $0.name == selectedNoteType }) else {
        return false
    }
    let updated = AnkiFieldTemplate.autofilledMappings(
        noteType: selectedNoteType,
        availableFields: noteType.fields,
        existing: fieldMappings
    )
    guard updated != fieldMappings else { return false }
    fieldMappings = updated
    return true
}
```

- [ ] **Step 2: Wire config load and AnkiConnect refresh**

After `load()` and `ensureAnkiConnectURL()` in `init`, save only if autofill changed mappings. In `applyFetchedAnkiMetadata`, call `autofillFieldMappings()` after selecting/pruning the current note type; the existing outer `fetchAnkiConnect()` save persists the result.

- [ ] **Step 3: Wire selected model changes**

Change the Model picker handler to:

```swift
.onChange(of: ankiManager.selectedNoteType) { _, _ in
    ankiManager.autofillFieldMappings()
    ankiManager.save()
}
```

- [ ] **Step 4: Lock orchestration with static contract checks**

Extend the test script to read `Core/AnkiManager.swift` and `Features/Settings/AnkiView.swift`, requiring the manager method, load/refresh calls, and picker call.

- [ ] **Step 5: Parse and run tests**

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc Models/Anki.swift script/test_anki_field_templates.swift -o /tmp/test_anki_field_templates && /tmp/test_anki_field_templates
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse Core/AnkiManager.swift Features/Settings/AnkiView.swift
```

Expected: tests pass and parser exits 0.

### Task 4: Update source-of-truth documentation

**Files:**
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md`
- Modify: `docs/ARCHITECTURE_REFACTORING.md`
- Modify: `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`
- Modify: `docs/UPSTREAM_SYNC_QUEUE.md`

- [ ] **Step 1: Record the user-visible fix**

Add:

```markdown
- Added safe default Anki field mappings for Lapis, Kiku, and Senren while preserving existing custom mappings.
```

- [ ] **Step 2: Record architecture and migration state**

State that template defaults live in the Anki model boundary, the manager owns merge/persistence timing, refresh preserves valid custom values, and real card creation remains intentionally untested without a disposable deck.

- [ ] **Step 3: Record upstream provenance and validation**

Mark upstream commit `8ffca617204c357e69573741c70c8d57a463bfd5` as adapted for native Mac safe-merge semantics and add the field-template test command to TODO validation entries.

### Task 4A: Add explicit note-type default restoration

**Files:**
- Modify: `script/test_anki_field_templates.swift`
- Modify: `Models/Anki.swift`
- Modify: `Core/AnkiManager.swift`
- Modify: `Features/Settings/AnkiView.swift`
- Modify: `Dictionaries.xcstrings`

- [ ] **Step 1: Write failing tests**

Require `appliedDefaultMappings` to overwrite known Lapis template fields, preserve template-external current fields, and leave unknown note types unchanged. Add static contracts for the manager action and confirmed settings UI.

- [ ] **Step 2: Verify RED**

Run the field-template test and confirm it fails because explicit default application is absent.

- [ ] **Step 3: Implement the pure reset and manager action**

Add the pure helper and `AnkiManager.applyDefaultFieldMappings()`. The manager only operates on the selected, currently available note type and saves only when the mapping changes.

- [ ] **Step 4: Add localized confirmed UI**

Add a button in the Fields section for known templates. Show a confirmation alert naming the selected note type, then apply and persist defaults. Localize all new visible text in English and Simplified Chinese.

- [ ] **Step 5: Verify GREEN**

Run the behavior/static contract and Swift parser checks.

### Task 5: Build and verify without mutating the Anki collection

**Files:**
- Protect: `~/Library/Application Support/anki_config.json`
- Verify: exact DerivedData App from `script/build_and_run.sh`

- [ ] **Step 1: Back up config and record existing custom mappings**

Copy `anki_config.json` to `/tmp/hoshi-anki-config-before-autofill.json` and record its SHA-256. Read only mapping keys/values needed to prove custom fields are preserved; do not expose tokens or unrelated configuration.

- [ ] **Step 2: Build and launch**

```bash
./script/build_and_run.sh --verify
```

Expected: verified bundle id `moe.shishamo.hoshi` and exact running executable path.

- [ ] **Step 3: Computer Use verification**

Open Settings → Anki in the exact app. Use the confirmed default action for the selected Lapis model. Confirm the fields that had Video values now show the upstream novel defaults and template-external fields remain present. Do not press Add to Anki or create a card.

- [ ] **Step 4: Verify persisted config safely**

Inspect only `selectedNoteType` and `fieldMappings` from the post-launch config. Confirm supported missing fields were added, custom non-empty values from the backup are unchanged, and no unrelated top-level config keys changed because of this feature.

- [ ] **Step 5: Final checks**

Run field-template tests, existing bookshelf/settings contracts, `git diff --check`, and `./script/build_and_run.sh --verify`. Do not commit, push, release, or create an Anki card.

### Task 6: Prevent and repair Lapis `DefinitionPicture` glossary overflow

**Files:**
- Modify: `script/test_anki_field_templates.swift`
- Modify: `Models/Anki.swift`
- Modify: `Features/Settings/AnkiView.swift`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/TODO.md`
- Protect: `~/Library/Application Support/anki_config.json`
- Repair: Anki note `1781894179856`

- [ ] **Step 1: Write the failing regression test**

Add a Lapis reset case with available fields `Expression`, `DefinitionPicture`, and `CustomField`. Require `Expression` to use its default, `DefinitionPicture` to be absent, and `CustomField` to remain unchanged. Require `AnkiFieldTemplate.clearsMapping(noteType:field:)` to return true only for `Lapis` + `DefinitionPicture`. Add a source contract requiring the Video preset to call this helper before its broad matcher.

- [ ] **Step 2: Verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc Models/Anki.swift script/test_anki_field_templates.swift -o /tmp/test_anki_field_templates && /tmp/test_anki_field_templates
```

Expected: compile failure because `clearsMapping(noteType:field:)` does not exist, or assertion failure because `DefinitionPicture` remains mapped.

- [ ] **Step 3: Implement the minimal mapping rule**

Add a Lapis-only cleared-field rule in `AnkiFieldTemplate`. Apply it after filtering available fields in `appliedDefaultMappings`. In `applyAnimeCardPreset`, remove any field identified by the same helper before calling `animeCardHandlebar(for:)`. Preserve every other template-external field.

- [ ] **Step 4: Verify GREEN and parse**

Run the field-template command, parse `Models/Anki.swift` and `Features/Settings/AnkiView.swift`, validate `Dictionaries.xcstrings`, and run `git diff --check`.

- [ ] **Step 5: Back up and repair user state**

Save the full `notesInfo` response for note `1781894179856` to `/tmp/hoshi-anki-note-1781894179856-before-definition-picture-fix.json`. Back up `anki_config.json`. Build with `./script/build_and_run.sh --verify`, then use the exact DerivedData App to apply Lapis defaults so the persisted `DefinitionPicture` mapping is removed. Use AnkiConnect `updateNoteFields` to set only that note's `DefinitionPicture` to an empty string.

- [ ] **Step 6: Verify actual note rendering and variants**

Confirm `notesInfo` reports an empty `DefinitionPicture`, `cardsInfo` no longer contains `def-image tappable`, and all other note fields/tags/model/card IDs match the backup. Run the focused contracts, `./script/verify_video_variant_contract.sh`, `./script/build_and_run.sh --video --verify`, then finish with `./script/build_and_run.sh --verify` so Light remains running. Do not create or delete any card.
