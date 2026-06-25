# Video Library Smart Collections Design

## Goal

Make large local Video libraries easier to browse without moving, renaming, deleting, or guessing user files. V1 adds a lightweight virtual organization layer on top of the existing scanned catalog.

## Scope

- Add manual collections that remain backed by stored item paths.
- Add smart collections with simple, explainable match rules:
  - file name contains text
  - parent folder contains text
  - full path contains text
  - tag contains text
  - has bound subtitle
  - is unwatched, in progress, or finished
- Show smart collections in the existing Collections mode and selected item inspector.
- Provide a preview count/sample before saving a smart collection.
- Preserve the current Folders and Series modes.

## Non-Goals

- No internet metadata lookup.
- No TMDb, TVDb, AniDB, Python, Node, ML model, bundled anime database, or large ruleset.
- No automatic anime/season/episode grouping.
- No file moving, renaming, deleting, sidecar rewriting, or Finder tag syncing.
- No virtual playlist ordering in the player for V1.

## Architecture

`VideoLibraryCollection` becomes a small union-like model with `kind`, optional manual item paths, and optional smart rules. Existing collections decode as manual collections. `VideoLibraryViewModel` evaluates smart rules against already-built `VideoLibraryRow` values, so playback state, tags, subtitles, and file metadata remain in one place.

The UI reuses the existing Video library shell. Collections mode groups manual and smart collections in the main content. The inspector lets users add or edit collections and preview smart-rule matches before saving.

## Validation

- Extend store tests for legacy decode, smart collection persistence, manual collection path cleanup, and smart collection cleanup safety.
- Extend view-model tests for rule matching, preview behavior, collections mode sections, and manual/smart coexistence.
- Extend static contract tests for localized strings and no heavy dependency/runtime import.
- Build Video and verify Light remains free of Video-only dependencies.
