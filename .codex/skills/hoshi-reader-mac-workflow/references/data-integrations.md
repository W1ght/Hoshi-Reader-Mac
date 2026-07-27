# Profiles, Anki, Sync, and Persistent State

Load this reference only when a task touches Profile resolution, AnkiConnect, Google Drive, tokens, sidecars, migration, or other durable user state.

## Required Context

- Read the current relevant state in `docs/TODO.md` and the `Profiles And Content Language`, `AnkiConnect`, or `Google Drive Sync` section of `docs/ARCHITECTURE_REFACTORING.md`.
- For dictionary backup or restore, inspect the current `ProfileDictionaryBackup` implementation and its focused contracts before changing merge semantics.

## Shared Data Rules

- Determine the owner of each value before changing it: global transport state, Profile configuration, UserDefaults, book sidecars, module catalogs, caches, and Keychain credentials have different lifecycles.
- `Settings > Profiles` is the only runtime Profile selector. Reader, Video, Manga, Dictionary, Popup, nested lookup, Suwayomi, and mining consume that active global Profile; opening or focusing content must not change it.
- Physical dictionary data and AnkiConnect transport are global. Dictionary enable/order/display, Reader appearance, and Anki mining mappings are Profile-owned.
- Profile-aware `.hoshi-profiles` dictionary restore merges dictionary-owned files only and must not overwrite Reader or Anki Profile files.
- Migrations are narrow, one-time, backward-compatible, and must not overwrite already valid current data. Do not delete credentials, configuration, progress, or sidecars to recover from an error.
- Use atomic writes and existing repositories/services. Cache cleanup must be scoped to rebuildable data and must not be used as a substitute for fixing ownership or invalidation.

## AnkiConnect

- macOS mining uses AnkiConnect, not AnkiMobile callbacks. Transport settings stay global; deck/model/field/tag/media choices follow the resolved Profile.
- Preserve still-valid deck, model, and field mappings during refresh. Connection recovery must work when Niratan starts before Anki.
- When card creation changes, cover success, duplicate, and failure behavior, including required media failures.

## Google Drive

- Sync protects reading progress and sidecar metadata, not just a numeric percentage. A timestamp/day or sidecar change can require sync even when the displayed progress is unchanged.
- OAuth and token callbacks return to the correct actor and refresh visible authentication state.
- Keep the account-only `googleDriveCredentials` Keychain item authoritative. Legacy split token values are migration inputs only when a real authentication or sync operation needs credentials.

## Verification

- Prefer injected stores, temporary directories, recorded network fixtures, and disposable Profiles/accounts.
- Do not inspect secret plaintext merely to render status or prove presence.
- If live Anki, Google, Keychain, or migration validation is unavailable, run the safe contracts and state exactly which live paths remain unverified.
