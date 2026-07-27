# Release

Load this reference only for versioning, tags, GitHub Actions, packaging, signing, release notes, or publishing.

## Authority and Preconditions

- A release, version bump, release commit, branch push, or tag push requires explicit user approval.
- Release from `main` with a clean worktree, the intended `MARKETING_VERSION`, and a tag that does not already exist.
- `script/release_mac.sh` mutates version control and remote state; run it only when the approved release scope matches what the script will do.

## Validation Boundary

- Development changes must complete their local affected-scope validation before entering release orchestration.
- Once an already validated release commit is tagged, `.github/workflows/release-mac.yml` is the release validation source of truth; do not repeat local builds or packaging merely for reassurance.
- If the release run exposes a code or packaging defect, leave release orchestration, fix and validate it as development work, then begin a new explicitly approved release attempt. This is not an exception allowing unvalidated code changes during release.

## Completion

- Monitor the tag-triggered workflow to a terminal state. Validation, build, and publish jobs must succeed.
- A release is complete only when the GitHub Release contains the intended `Niratan-Mac-<version>.dmg` and checksum. The current pipeline does not establish notarization unless its workflow and artifacts explicitly change.
- Do not describe a failed workflow, partial Release, missing asset, or locally built DMG as published.
- Release notes are user-facing and Chinese-first unless requested otherwise. Exclude CI mechanics, agent workflow, dependency management, and internal refactors.
- Keep DMG and checksum as the primary assets; do not add unnecessary app/source archives.

For changes to package contents, signing, dependencies, or runtime identity, also load `project-build.md`.
