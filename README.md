<div align="center">

# Hoshi Reader for Mac

![Language](https://img.shields.io/github/languages/top/W1ght/Hoshi-Reader)
![Platform](https://img.shields.io/badge/platform-macOS%20%28Mac%20Catalyst%29-lightgrey)
![License](https://img.shields.io/github/license/W1ght/Hoshi-Reader)

Hoshi Reader for Mac is a Mac Catalyst build of Hoshi Reader, a lightweight Japanese EPUB reader with Yomitan dictionary support for immersion learning.

This fork focuses on desktop reading, Mac keyboard interaction, AnkiConnect card creation, and keeping the original Hoshi Reader reading experience available on macOS.

<p align="center">
    <img src="Pictures/books.PNG" width="25%" alt="books">
    <img src="Pictures/reader.PNG" width="25%" alt="reader">
    <img src="Pictures/popup_dict.PNG" width="25%" alt="popup">
    <img src="Pictures/appearance.PNG" width="25%" alt="appearance">
    <img src="Pictures/anki_view.PNG" width="25%" alt="anki">
    <img src="Pictures/dictionary_view.PNG" width="25%" alt="dictionary">
</p>

## Download

Download the latest macOS build from the [GitHub Releases](https://github.com/W1ght/Hoshi-Reader/releases) page.

The Mac build is distributed as a `.dmg`. If macOS warns that the app cannot be opened because it is from an unidentified developer, open it from Finder with right click > Open, or allow it in System Settings > Privacy & Security.

## Mac Features

<div align="left">

- Native Mac Catalyst app bundle for macOS.
- Desktop reader layout with Mac-friendly top and bottom controls.
- Reader tabs remain reachable while reading: `Books`, `Dictionary`, and `Settings`.
- Click-to-lookup still works like the original touch flow.
- Hover a word and press `Shift` to look it up on Mac.
- Nested dictionary popups also support hover + `Shift` lookup.
- Configurable Mac keyboard shortcuts for page navigation and Sasayaki playback.
- `Esc` and `Cmd+W` close the reader.
- Non-blocking Anki card creation notifications with Liquid Glass-style top bubbles.
- Anki card creation on Mac uses AnkiConnect.
- DMG-based release packaging.

</div>

## Core Features

<div align="left">

- **Vertical** (縦書き) and horizontal (横書き) text.
- Yomitan-like pop-up dictionary with **deinflection support**.
- Support for Yomitan term, frequency, and pitch dictionaries.
- **Audio support** for Yomitan online and local audio sources.
- **AnkiConnect integration** with one-click mining on Mac.
- Support for core handlebars used by [Lapis](https://github.com/donkuri/lapis).
- **ッツ Reader sync**.
- **Reading statistics**.
- Dictionary search.
- Bookshelves.
- Custom themes, fonts, CSS, and separate light/dark Sasayaki highlight colors.

</div>

## Mac Setup

### AnkiConnect

Card creation on Mac uses AnkiConnect instead of the iOS AnkiMobile callback flow.

1. Install the AnkiConnect add-on in Anki.
2. Launch Anki on the same Mac.
3. Confirm AnkiConnect is reachable at `http://127.0.0.1:8765`.
4. Open Hoshi Reader > Settings > Advanced > AnkiConnect.
5. Connect, then fetch decks and note models from the Anki settings screen.

### Keyboard Shortcuts

Mac reader shortcuts can be configured at:

`Settings > Advanced > Keyboard Shortcuts`

Click a shortcut row, then press a single key or key combination. Defaults:

| Action | Default |
| :--- | :--- |
| Previous Page | `←` |
| Next Page | `→` |
| Previous Sasayaki Cue | `[` |
| Play/Pause Sasayaki | `P` |
| Next Sasayaki Cue | `]` |

### Lookup

- Click a word or character in the reader to look it up.
- Hover over a word and press `Shift` to look it up.
- Hold `Shift` while moving the pointer to continue hover lookup.
- The hover delay can be tuned in dictionary settings.

## Development

1. Clone the repository.
2. Open `Hoshi Reader.xcodeproj` in Xcode.
3. Build the `Hoshi Reader` scheme for Mac Catalyst.

For Mac Catalyst interaction notes, see [docs/mac-catalyst-interactions.md](docs/mac-catalyst-interactions.md).

The local build/run helper is:

```bash
./script/build_and_run.sh
```

Release verification uses:

```bash
xcodebuild -quiet -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader' -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Relationship To The Original Project

This Mac version is based on the original [Manhhao/Hoshi-Reader](https://github.com/Manhhao/Hoshi-Reader) project.

The goal of this fork is to adapt the app for macOS while preserving the original reader, dictionary, audio, sync, and mining ideas as much as possible.

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

* **[Manhhao/Hoshi-Reader](https://github.com/Manhhao/Hoshi-Reader)** - Thanks to the original Hoshi Reader project and its author for the foundation this Mac version builds on.
* **[TheMoeWay](https://learnjapanese.moe/)** - For helping make immersion learning approachable.
* **[Yomitan](https://github.com/yomidevs/yomitan)** - For serving as an invaluable tool and the primary inspiration for the pop-up dictionary.
* **[Ankiconnect Android](https://github.com/KamWithK/AnkiconnectAndroid)** - For providing a great mining experience on Android.
* **[ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader)** - For inspiring the core reading experience.
* **[星街すいせい (Hoshimachi Suisei)](https://www.youtube.com/@HoshimachiSuisei)** - For inspiring the project name (星読み).

## License

Distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for more information.

</div>
