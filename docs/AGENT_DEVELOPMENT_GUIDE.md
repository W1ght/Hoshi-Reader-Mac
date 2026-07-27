# Niratan Mac Agent Development Guide

This file is a navigation index, not a second instruction hierarchy.

## Context Ownership

Each kind of information has one owner:

- `AGENTS.md`: cross-task product boundaries, high-consequence invariants, repository-specific gotchas, and the completion contract.
- `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`: task routing and the common verification contract.
- Skill references: operational guidance that is loaded only for the affected domain.
- Architecture documents: durable design and module ownership.
- `docs/TODO.md`: current state, next actions, blockers, and validation entry points.
- Regression documents and tests: acceptance matrices and executable invariants.
- `docs/CHANGELOG.md`: user-visible changes only.

Do not resolve conflicting guidance by accumulating another rule. Identify the owner above, correct that source, and remove stale duplicates.

## Product

Niratan is one native macOS 26+ App with Reader, Video, and Manga modules. Mac user-visible behavior is authoritative; upstream mobile implementations are references rather than automatic replacements.

## Task Routing

Start with the root `AGENTS.md`. For implementation, debugging, validation, upstream, build, or release work, `.codex/skills/hoshi-reader-mac-workflow/SKILL.md` is the sole routing table. Follow it to only the references matching the task; do not copy that table into another document or preload every reference.

## Truth Sources

- `docs/ARCHITECTURE_REFACTORING.md`: cross-module and long-term architecture.
- `docs/TODO.md`, current Video code, and focused contracts: current Video behavior.
- `docs/READER_REGRESSION_TESTING.md`: Reader and Manga actual-data validation and data safety.
- `docs/READER_PERSISTENCE_DEBUGGING.md`: Reader sidecar/persistence diagnosis.
- `docs/UPSTREAM_SYNC_QUEUE.md`: evaluated upstream queue.
- `.github/workflows/release-mac.yml` and release scripts: executable release behavior.

Load these only when the current task needs them. Code, contracts, and scripts are preferable references for facts they already express precisely.
