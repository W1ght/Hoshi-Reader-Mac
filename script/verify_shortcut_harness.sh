#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMMON_SOURCES=(
  Core/Shortcuts/KeyboardShortcutBinding.swift
  Core/Shortcuts/ShortcutAction.swift
  Core/Shortcuts/ShortcutConfiguration.swift
  Core/Shortcuts/ShortcutConflictChecker.swift
  Core/Shortcuts/ShortcutDispatchResolver.swift
  Core/Shortcuts/ShortcutRegistry.swift
)

CATALOG_SOURCES=(
  Features/Reader/ReaderShortcutActions.swift
  Features/Dictionary/DictionaryShortcutActions.swift
  Features/Popup/PopupShortcutActions.swift
  Features/Sasayaki/SasayakiShortcutActions.swift
  Features/Settings/ApplicationShortcutRegistry.swift
)

echo "==> Checking Light shortcut registry"
swiftc \
  "${COMMON_SOURCES[@]}" \
  "${CATALOG_SOURCES[@]}" \
  script/test_shortcut_registry.swift \
  -o /tmp/test_shortcut_registry_light
/tmp/test_shortcut_registry_light

echo "==> Checking Video shortcut registry"
swiftc \
  -D HOSHI_VIDEO \
  "${COMMON_SOURCES[@]}" \
  "${CATALOG_SOURCES[@]}" \
  Features/Video/VideoShortcutActions.swift \
  script/test_shortcut_registry.swift \
  -o /tmp/test_shortcut_registry_video
/tmp/test_shortcut_registry_video

echo "==> Checking shortcut scope conflicts"
swiftc \
  "${COMMON_SOURCES[@]}" \
  script/test_shortcut_scope_resolution.swift \
  -o /tmp/test_shortcut_scope_resolution
/tmp/test_shortcut_scope_resolution

echo "==> Checking shortcut configuration migration"
swiftc \
  "${COMMON_SOURCES[@]}" \
  Features/Reader/ReaderShortcutActions.swift \
  script/test_shortcut_config_migration.swift \
  -o /tmp/test_shortcut_config_migration
/tmp/test_shortcut_config_migration

echo "==> Checking shortcut dispatch priority"
swiftc \
  "${COMMON_SOURCES[@]}" \
  script/test_shortcut_dispatch_resolution.swift \
  -o /tmp/test_shortcut_dispatch_resolution
/tmp/test_shortcut_dispatch_resolution

echo "Shortcut harness checks passed"
