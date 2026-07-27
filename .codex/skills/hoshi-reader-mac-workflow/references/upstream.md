# Upstream Sync

Load this reference only when comparing, porting, merging, or documenting changes from `upstream/develop`.

## Workflow

- Fetch and inspect the exact upstream diff before choosing commits or files to port.
- Treat upstream behavior as a reference. Preserve established native macOS windowing, Reader geometry, input, Popup, AnkiConnect, audio, sync, Video, and Manga behavior unless the user explicitly chooses a different product behavior.
- Check whether the native App already has an equivalent settings entry or Mac-specific implementation before adding another path.
- Reader WebView, Popup/Dictionary CSS, image/media handling, Sasayaki, sync, profiles, and module build boundaries require the matching domain reference and focused regression evidence.
- Prefer a narrow port over wholesale file replacement. Keep unrelated local and working-tree changes intact.
- Update `docs/UPSTREAM_SYNC_QUEUE.md` only when the evaluated queue state actually changes.
