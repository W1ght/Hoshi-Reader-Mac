# Hoshi Reader Mac Changelog

This changelog records user-visible changes only. Implementation details, investigation logs, and temporary experiments belong in commits, issues, or focused design docs.

## Unreleased

- Added bookshelf drag-and-drop for importing EPUB files and manually reordering local books.
- Added an optional two-column glossary layout with balanced dictionary cards for larger and full-width lookup popups.
- Fixed cross-App selected-text lookup falling back through a restored clipboard copy path so it works in more apps beyond browser accessibility selections.
- Fixed Dictionary settings reverting to an older Profile snapshot after relaunching the app.
- Fixed Reader image and SVG sizing in continuous and fullscreen views.
- Fixed game controller actions using different Reader and Sasayaki behavior from the matching keyboard shortcuts.
- Video subtitle options now customize the lookup-highlight text color separately from its background.

## 0.6.0 Beta 4

- Added experimental, opt-in cross-App selected-text lookup: press the configurable global shortcut to show the active Profile's Hoshi dictionary Popup near the pointer without copying text through the clipboard.
- Fixed Reader appearance settings reverting to an older Profile snapshot after relaunching the app.
- Fixed Dictionary and Audio source rows failing to reorder on macOS 26 by committing row drops through an AppKit pasteboard destination.
- Fixed Reader left/right shortcuts occasionally advancing two pages when AppKit rewrapped one key event before delivering it to the focused WebView.
- Reorganized Settings so Video has its own group, keyboard shortcuts and game controllers have a separate controls group, and Video Settings no longer duplicates the shortcut inventory.
- Video subtitles now support native mouse selection and copying while preserving click and Shift-hover lookup, and the matched lookup text remains highlighted until the Popup closes.
- Video subtitle options now customize both subtitle text color and lookup-highlight background color from Settings or the inspector.
- Mining History, Transcript and Chapters now use the same fully clickable Liquid Glass cards, with a brighter study sidebar in light appearance and the approved subtitle lookup highlight color as the default.
- Reader and Video Popup entries now offer a shared card-stacked context selector with independent add/rollback controls for preceding and following sentences; expanded Video context also expands the captured audio range.
- Opening Video from the main sidebar now chooses a media file first and presents it in one dedicated player window; choosing another file reuses that window, while closing it saves playback state and stops the player.
- Fixed videos opened from the main sidebar showing a black frame when the initial media request arrived before the libmpv render surface was ready.
- Moved Mining History and Open Video into the widened bottom playback bar, synchronized native traffic-light visibility with its two-second idle hide, and restored full-screen support for the dedicated Video window.
- Replaced windowed Video letterbox black with a restrained, current-frame Liquid Glass ambience while keeping full-screen letterboxing pure black and card screenshots unchanged.
- Video now restores both the last playback position and the selected embedded, external, or disabled subtitle state when reopening files or switching episodes from the inspector.
- Fixed the Video playback bar and top-left controls remaining visible indefinitely when the pointer stopped over them; both now hide after two seconds without pointer movement.

## 0.6.0 Beta 2

- Restored the Google Drive book refresh button in the native Bookshelf toolbar when sync is enabled and connected.
- Google Drive book downloads now stay in the background with per-book progress, allowing multiple books to download at the same time without blocking the Bookshelf.
- Audio sources in Settings can now be reordered by dragging any row, including the local audio source, and keep their lookup priority across launches.
- Fixed the selected Video Profile being overwritten by the global Profile after visiting Settings or switching app sections.
- Restored Shift-hover lookup in Reader and added the same configurable, continuous Shift-hover lookup to Video subtitles.
- Fixed dictionary rows in Settings no longer supporting drag-and-drop ordering after the native settings migration.

## 0.6.0 Beta 1

- Fixed GitHub release builds being terminated at launch on Apple Silicon by preserving a valid ad-hoc signature across the App and embedded libraries.

## 0.6.0 Beta

- Added Japanese and English Profiles with independent dictionary, Reader appearance and Anki mining settings, automatic EPUB language selection, per-book override and separate built-in `Japanese EPUB` / `Japanese Video` defaults.
- Added English word and phrase lookup, apostrophe/hyphen-aware scanning, IPA output for Lapis/Yomitan-compatible Anki fields and approximate word-count progress.
- Updated dictionary backup and restore to preserve Profile dictionary configuration while remaining compatible with older single-Profile backups.
- Added Video media mining that captures the current frame and encodes the selected audio track over the subtitle range for normal Anki field mappings.
- Added Video pointer-revealed playback chrome that auto-hides on idle or app/window exit, uses a compact IINA-like draggable control surface, single-click play/pause, double-click full screen, subtitle, volume, track, and shortcut-summary controls.
- Changed the macOS app bundle identifier to `moe.shishamo.hoshi`.
- Raised default Video subtitle placement so captions are not covered by the compact playback controls.
- Added Video drag-and-drop import for media and SRT/VTT subtitle files, and preserved playback when switching from Video to other sidebar sections and back.
- Added Video subtitle appearance controls for font and size, with asbplayer-style defaults, plus mask controls for blurring or hiding text subtitles until pointer hover.
- Added an asbplayer-style Video Mining History that saves the current subtitle independently of Anki, supports configurable retention, and can reopen the source video/subtitle for later lookup and card creation.
- Moved the Video subtitle list beside Mining History with a segmented switch, and made selected embedded text tracks populate the complete list without requiring a separate subtitle import.
- Moved Video chapter navigation into the same segmented study sidebar as Mining History and the subtitle list, with current-chapter highlighting.
- Fixed SVG and other Reader images being cropped or rendered incorrectly in the native macOS full-screen image preview.
- Restored Catalyst-style Reader layout so text uses the full available viewport and only applies the reader margins chosen in Appearance.
- Expanded the native Reader into the top safe area so vertical pages can use the titlebar band instead of leaving a large blank strip.
- Fixed Reader previous/next shortcuts changing chapters before the final partial page had been displayed.
- Fixed Sasayaki playback shortcuts so `P` continues to play/pause while the Sasayaki panel is open.
- Fixed Reader previous/next shortcuts firing twice when the focused WebView also received the same key event.
- Fixed Reader and Sasayaki shortcuts crashing on macOS 27 when a key event was successfully handled.
- Restored the Bookshelf cover size and compact progress bars to the denser v0.5.0 Catalyst-style layout.
- Fixed the nested Dictionary Settings page trapping the main sidebar, and placed its lookup/display options directly on the Dictionary settings page.
- Restored Sasayaki SRT matching from the native Bookshelf with the grouped v0.5.0-style match sheet.
- Added safe novel and anime default Anki mappings for Lapis, Kiku, and Senren. Novel `SentenceAudio`/`Picture` use Sasayaki audio and book covers; anime defaults use Video audio clips, screenshots, and subtitle-time source info, with separate confirmed restore actions.
- Moved the Video Profile selector from the top-right overlay into the bottom playback controls where the active Profile name remains visible.
- Fixed Reader `{book-cover}` cards omitting the active book cover and Video `{video-audio-clip}` cards silently losing audio for formats such as MKV.
- Fixed Video Previous Subtitle restarting the current subtitle instead of seeking to the preceding cue.

## 0.4.2

- Fixed vertical reading pages where some EPUBs could show text from adjacent pages stuck together or overlapping at pagination boundaries.
- Aligned vertical reader page sizing and bottom spacing with upstream behavior while preserving Mac horizontal overflow protection.
- Restored direct switching between Books, Dictionary, and Settings from the reader so returning to Books can continue the current reading session.

## 0.4.1

- Added dictionary entry navigation shortcuts for lookup results.
- Added shortcut settings for previous and next dictionary entry navigation.
- Improved highlighting and scrolling for the current dictionary entry in popup and nested popup results.

## 0.4.0

- Merged recent upstream reader and dictionary behavior with Mac Catalyst adaptations.
- Improved reader full-screen and chrome layout so the reading area uses more of the window.
- Fixed reader white-screen and vertical pagination display regressions.
- Added right-click delete actions for highlights and dictionary entries to match trackpad swipe delete behavior.
- Improved localization coverage for new settings surfaces.
- Improved Google Drive progress sync behavior around unchanged progress across days.
