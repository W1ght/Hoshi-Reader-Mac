<div align="center">

# Hoshi Reader Mac

[English](README.md) | [简体中文](README.zh-CN.md)

![Language](https://img.shields.io/github/languages/top/W1ght/Hoshi-Reader-for-Mac)
![Platform](https://img.shields.io/badge/platform-macOS%20%28Mac%20Catalyst%29-lightgrey)
![License](https://img.shields.io/github/license/W1ght/Hoshi-Reader-for-Mac)

Hoshi Reader Mac is a lightweight Japanese EPUB reader with Yomitan dictionary support, adapted for desktop immersion learning on macOS.

This Mac build keeps the reading, dictionary, audio, sync, and mining experience of the original Hoshi Reader, while adding Mac-friendly interaction, AnkiConnect support, keyboard shortcuts, local audio, and DMG releases.

<p align="center">
    <img src="Pictures/books_mac.png" width="32%" alt="Bookshelf">
    <img src="Pictures/reader_mac.png" width="32%" alt="Reader">
    <img src="Pictures/popup_dict_mac.png" width="32%" alt="Popup dictionary">
</p>
<p align="center">
    <img src="Pictures/dictionary_view_mac.png" width="32%" alt="Dictionary">
    <img src="Pictures/appearance_mac.png" width="32%" alt="Appearance settings">
    <img src="Pictures/anki_view_mac.png" width="32%" alt="Anki settings">
</p>

## Download

Download the latest macOS build from [GitHub Releases](https://github.com/W1ght/Hoshi-Reader-for-Mac/releases).

Hoshi Reader Mac is distributed as a `.dmg`. If macOS blocks the unsigned app, open it from Finder with right click > Open, or allow it in System Settings > Privacy & Security.

The app also includes an update checker on the bookshelf so you can jump to the latest release without manually searching for it.

## Features

<div align="left">

- **Vertical** (縦書き) and horizontal (横書き) EPUB reading
- Desktop bookshelf layout with reading progress, sorting, import, and library management
- Yomitan-like pop-up dictionary with **deinflection support**
- Support for Yomitan term, frequency, and pitch dictionaries
- Dictionary search page with the same rendering engine as reader popups
- Click-to-lookup, text selection, and nested lookup inside dictionary popups
- Mac hover lookup: hover a word and press `Shift` to scan from the pointer position
- Configurable keyboard shortcuts for page turns and Sasayaki playback
- Local audio database support for offline word audio
- Sasayaki audiobook support with cue matching, sentence highlighting, and play/pause controls
- AnkiConnect card creation on Mac, including duplicate checks, media fields, local word audio, and Sasayaki audio fields
- Non-blocking mining notifications shown as top toast bubbles
- Reading statistics and ッツ Reader-compatible sync
- Google Drive sync for books, progress, statistics, and audio-related reading data
- Custom themes, fonts, vertical spacing, reader chrome, and native custom CSS for dictionary rendering
- Separate light/dark Sasayaki highlight colors

</div>

</div>

## Mac Interaction

Hoshi Reader Mac is still built from the shared Hoshi Reader codebase, but the Mac build adds desktop-oriented behavior:

- `Books`, `Dictionary`, and `Settings` stay available from the top navigation while you are using the app.
- In the reader, `Esc` and `Cmd+W` return to the bookshelf.
- Full-screen reading hides the top navigation until the pointer reaches the top edge.
- Trackpad swipe gestures are not used for page turning, avoiding accidental macOS back navigation.
- Paged and continuous reading both respect Mac Catalyst safe areas and window resizing.

See [docs/mac-catalyst-interactions.md](docs/mac-catalyst-interactions.md) for implementation notes.

## Anki On Mac

Card creation on macOS uses [AnkiConnect](https://ankiweb.net/shared/info/2055492159). The iOS AnkiMobile callback flow is not used on Mac.

1. Install Anki and the AnkiConnect add-on.
2. Start Anki on the same Mac.
3. Open Hoshi Reader > Settings > Anki.
4. Connect to `http://127.0.0.1:8765`.
5. Fetch decks and note models from AnkiConnect, then map your fields.

Hoshi Reader automatically retries the AnkiConnect connection, so opening Hoshi before Anki should recover once Anki is running.

## Keyboard Shortcuts

Keyboard shortcuts can be configured in Settings > Advanced > Keyboard Shortcuts.

| Action | Default |
| :--- | :--- |
| Previous page | `←` |
| Next page | `→` |
| Previous Sasayaki cue | `[` |
| Play / pause Sasayaki | `P` |
| Next Sasayaki cue | `]` |
| Close reader | `Esc` / `Cmd+W` |
| Focus mode | `F` |

Click a shortcut row, then press a single key or a key combination.

## Local Audio And Sasayaki

Hoshi Reader Mac can use a local audio database for word audio. Enable it in Settings > Advanced > Audio, then import an `android.db` compatible with Ankiconnect Android-style local audio.

Sasayaki is for full audiobook playback. Import local audiobook audio and matching cue data from the reader's Sasayaki panel, then use the reader controls or keyboard shortcuts to play, pause, and jump between cues.

## Dictionary CSS

Custom CSS is injected as native CSS into the dictionary WebView after dictionary content is rendered. Hoshi Reader does not rewrite unsupported CSS properties. If a property behaves inconsistently in Mac Catalyst's `WKWebView`, prefer explicit selectors such as:

```css
[data-dictionary="明鏡国語辞典 第三版"] .glossary-content {
    font-size: 18px;
    line-height: 1.65;
}

.dict-label {
    font-size: 11px;
}
```

## Development

1. Clone the repository.
2. Open `Hoshi Reader.xcodeproj` in Xcode.
3. Build the `Hoshi Reader` scheme Mac Catalyst.

The local build/run helper is:

```bash
./script/build_and_run.sh
```

Unsigned build verification:

```bash
xcodebuild -quiet -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader' -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Releases are produced from tags through GitHub Actions and published as DMG artifacts.

## Relationship To The Original Project

This repository is an independent Mac-focused fork based on the original [Manhhao/Hoshi-Reader](https://github.com/Manhhao/Hoshi-Reader) project.

The goal is to preserve Hoshi Reader's iOS reading model and dictionary pipeline while making the app practical as a daily desktop reader on macOS.

## Libraries

| Name | License |
| :--- | :--- |
| [hoshidicts](https://github.com/Manhhao/hoshidicts) | GPLv3 |
| [EPUBKit](https://github.com/witekbobrowski/EPUBKit) | MIT |
| [SwiftUI Introspect](https://github.com/siteline/swiftui-introspect) | MIT |

## Attribution

| Name | Description | License |
| :--- | :--- | :--- |
| [Hoshi Reader](https://github.com/Manhhao/Hoshi-Reader) | Original project this Mac build is based on | GPLv3 |
| [Ankiconnect Android](https://github.com/KamWithK/AnkiconnectAndroid) | Local Audio implementation | GPLv3 |
| [Yomitan](https://github.com/yomidevs/yomitan) | Various code from pop-up dictionary | GPLv3 |
| [ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader) | Statistics | BSD-3 |
| [JMdict for Yomitan](https://github.com/yomidevs/jmdict-yomitan) | Recommended term dictionary | CC-BY-SA-4.0 |
| [Jiten](https://github.com/Sirush/Jiten) | Recommended frequency dictionary | Apache-2.0 |
| [Kanji alive](https://github.com/kanjialive/kanji-data-media) | Default audio source | CC-BY-4.0 |
| [Tofugu/WaniKani Audio](https://github.com/tofugu/japanese-vocabulary-pronunciation-audio) | Default audio source | CC-BY-SA-4.0 |

## Special Thanks

* **[Manhhao/Hoshi-Reader](https://github.com/Manhhao/Hoshi-Reader)** - Thank you to the original Hoshi Reader project and its author for the foundation this Mac version builds on.
* **[TheMoeWay](https://learnjapanese.moe/)** - For making immersion learning more approachable.
* **[Yomitan](https://github.com/yomidevs/yomitan)** - For serving as an invaluable tool and the primary inspiration for the pop-up dictionary.
* **[Ankiconnect Android](https://github.com/KamWithK/AnkiconnectAndroid)** - For providing a great mining and local audio experience on Android.
* **[ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader)** - For inspiring the core reading experience.
* **[星街すいせい (Hoshimachi Suisei)](https://www.youtube.com/@HoshimachiSuisei)** - For inspiring the project name (星読み).

## License

Distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for more information.
