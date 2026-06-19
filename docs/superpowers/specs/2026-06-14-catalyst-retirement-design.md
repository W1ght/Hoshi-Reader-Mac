# Catalyst Retirement Design

## Goal

Retire the Mac Catalyst application and ShareExtension completely, make the native macOS application the only Xcode target and release product, and ship it as `Hoshi Reader.app` with the current bundle identifier `moe.shishamo.hoshi` while preserving user-data compatibility explicitly.

## Product Identity

- Rename the native target, scheme, product, process, and app bundle to `Hoshi Reader`.
- Change the native bundle identifier from the migration-only `de.manhhao.hoshi.native` identity to `moe.shishamo.hoshi`.
- Keep the `hoshi` URL scheme, EPUB and Anki package document declarations, version number, storage paths, sidecars, UserDefaults keys, and Keychain service behavior.
- Remove iOS-only Info.plist keys while retaining macOS document-opening and local-network permission metadata.

## Source And Project Cleanup

- Delete the Catalyst app target and the ShareExtension target from `project.pbxproj`.
- Delete the Catalyst shared scheme and replace it with a shared native `Hoshi Reader` scheme.
- Delete `App/`, `ShareExtension/`, Catalyst Reader shell/WebViews/fullscreen viewer, and Catalyst-only scripts.
- Keep shared Reader JavaScript, selection/highlight assets, popup rendering, models, services, and SwiftUI screens used by Native.
- Remove UIKit branches from shared files when the native AppKit implementation already exists.
- Preserve legacy `UIColor` decoding only as a data migration implementation isolated from the active UI path.

## Release Pipeline

- `script/package_mac.sh` builds the native macOS Release configuration without code signing.
- The package script verifies bundle name, bundle identifier, short version, executable presence, DMG integrity, and checksum.
- No Developer ID signing, notarization, stapling, certificate import, or signing secrets are required.
- GitHub Actions publishes only the DMG and SHA256 file and clearly states that the app is unsigned and must be opened from Finder with Control-click or right-click, then Open.
- `script/release_mac.sh` keeps its existing explicit main-branch, clean-tree, version, tag, push, and release-note safeguards, but uses a Conventional Commit version bump.

## Validation

- `xcodebuild -list` exposes only the native application target and scheme.
- Debug and Release native builds succeed with signing disabled.
- The built Release bundle is `Hoshi Reader.app`, bundle id is `moe.shishamo.hoshi`, and the requested version is embedded.
- Reader harness and Native Lab smoke/scenario capture pass.
- The generated DMG mounts, contains `Hoshi Reader.app` plus the Applications link, and passes `hdiutil verify`.
- Repository searches find no active Catalyst target, ShareExtension, Catalyst build script, UIKit Reader wrapper, or Catalyst release destination.

## Non-Goals

- This work does not sign or notarize the application.
- It does not publish a release, create a tag, or push changes.
- It does not redesign the native UI or change user-facing Reader behavior beyond removing dead Catalyst implementations.
