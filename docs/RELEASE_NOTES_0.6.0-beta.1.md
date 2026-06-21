# Hoshi Reader Mac v0.6.0-beta.1

## 中文

### Beta 1 修复

- 修复首个 0.6.0 Beta 的 GitHub 构建因缺少 Apple Silicon 所需的可执行签名而无法启动的问题。
- Light App、Video App 及内嵌 libmpv 依赖现在均执行 ad-hoc 签名和完整 bundle 校验。

### ⚠️ 重要：从 Mac Catalyst 迁移到原生 macOS

这是一次带有一定破坏性的架构升级，请谨慎升级。

`v0.5.0` 是 bundle id 为 `de.manhhao.hoshi` 的 Mac Catalyst App；`v0.6.0-beta.1` 已替换为 bundle id 为 `moe.shishamo.hoshi` 的原生 macOS App，并移除了 Catalyst target 与 Share Extension。窗口、文件打开、快捷键、输入焦点、全屏、生命周期及部分配置边界均已重建。

项目保留了书籍目录、阅读进度、bookmark、sidecar、词典、Anki 配置和 Google token 的兼容路径，但不同安装环境下仍可能出现配置需要重新选择、授权需要重新确认或少量界面行为变化。升级前建议备份书籍和配置，并保留 `v0.5.0` 安装包。升级后请先确认书籍、进度、词典、Sasayaki、同步和 Anki 字段映射正常，再删除旧数据或完全切换日常使用。

### 相比 v0.5.0 的主要新增与变化

#### 原生 macOS 体验

- App 完整迁移为 SwiftUI/AppKit 原生 macOS 实现，不再依赖 UIKit 或 Mac Catalyst。
- 重建原生侧边栏、窗口、菜单、文件/URL 打开、焦点、鼠标和统一快捷键分发。
- 改进 Reader 的窗口缩放、全屏、分页/连续滚动、竖排布局、安全区和图片预览。
- 恢复更紧凑的书架封面与进度显示、Sasayaki SRT 匹配，以及多项 Reader/Sasayaki 快捷键稳定性修复。

#### 全新 Video 构建

- 新增独立的 `Hoshi Reader Video` DMG，内置 universal libmpv；Light 构建不包含 mpv。
- 支持视频播放列表、拖放导入、音视频/字幕轨道、章节、字幕延迟、倍速、音量、循环、旋转、画面比例和播放位置恢复。
- 新增紧凑悬浮底栏、底栏 Profile 切换、单击播放/暂停、双击全屏以及统一 Video 快捷键。
- Hoshi 可解析 SRT/VTT 和选中的内嵌文字字幕，并提供可点击查词的字幕 overlay、完整字幕列表、字体/字号和模糊/隐藏遮罩。
- “挖卡历史 / 字幕列表 / 章节”合并为学习侧栏；支持字幕采集、跳转、复制、删除和跨视频恢复。
- Video 制卡支持 `{video-screenshot}` 与 `{video-audio-clip}`，可截取当前画面和字幕时间范围内的选定音轨。

#### Profile、词典与制卡

- 新增相互独立的 Profile 配置，内置 `Japanese EPUB` 与 `Japanese Video`，并支持为英语内容配置 Profile、书籍语言自动选择和单本覆盖。
- 每个 Profile 可分别保存词典、Reader 外观与 Anki 映射；词典备份兼容旧的单 Profile 格式。
- 新增英语单词/短语查词、撇号和连字符扫描、IPA 字段输出及近似词数进度。
- 新增小说/动漫两套默认 Anki 映射：小说使用 `{sasayaki-audio}` 与 `{book-cover}`，动漫使用 `{video-audio-clip}` 与 `{video-screenshot}`。
- 修复书封面、MKV 视频音频附件和上一句字幕跳转等问题。

### 安装说明

- 普通 EPUB 阅读请选择 `Hoshi-Reader-Mac-0.6.0-beta.1.dmg`。
- 视频学习请选择 `Hoshi-Reader-Mac-Video-0.6.0-beta.1.dmg`。
- 两个构建使用相同 App 身份和用户数据，请勿同时安装或同时运行。
- 当前 App 使用 ad-hoc 签名，但没有 Developer ID 签名或 Apple 公证。如果 macOS 阻止启动，请在 Finder 中右键 `Hoshi Reader.app` 并选择“打开”，或在“系统设置 → 隐私与安全性”中允许。
- Release 同时提供 `.sha256` 文件用于校验下载内容。

---

## English

### Beta 1 fix

- Fixed the first 0.6.0 Beta GitHub builds failing to launch because Apple Silicon executables had no usable code signature.
- The Light app, Video app, and bundled libmpv dependencies are now ad-hoc signed and verified as complete bundles.

### ⚠️ Important: Mac Catalyst to native macOS migration

This is a potentially breaking architectural upgrade. Please upgrade with care.

`v0.5.0` was a Mac Catalyst app with bundle identifier `de.manhhao.hoshi`. `v0.6.0-beta.1` replaces it with a native macOS app using `moe.shishamo.hoshi`, and removes the Catalyst target and Share Extension. Windowing, file opening, shortcuts, input focus, full screen, lifecycle handling, and parts of the configuration boundary have been rebuilt.

Compatibility paths remain for the book library, reading progress, bookmarks, sidecars, dictionaries, Anki configuration, and Google tokens. However, some installations may still require settings to be selected again, authorization to be confirmed, or adjustments to changed UI behavior. Back up your books and configuration before upgrading, and keep the `v0.5.0` installer. After upgrading, verify your books, progress, dictionaries, Sasayaki, sync, and Anki field mappings before deleting old data or fully switching your daily workflow.

### Major additions and changes since v0.5.0

#### Native macOS experience

- Fully migrated the app to native SwiftUI/AppKit macOS code, without UIKit or Mac Catalyst.
- Rebuilt native sidebars, windows, menus, file/URL opening, focus handling, mouse interaction, and unified shortcut dispatch.
- Improved Reader window resizing, full screen, paged/continuous reading, vertical layout, safe areas, and image preview.
- Restored the denser bookshelf layout and Sasayaki SRT matching, with multiple Reader and Sasayaki shortcut stability fixes.

#### New Video build

- Added a separate `Hoshi Reader Video` DMG with bundled universal libmpv; the Light build contains no mpv libraries.
- Added playlists, drag-and-drop import, video/audio/subtitle tracks, chapters, subtitle and audio delay, speed, volume, loops, rotation, aspect ratio, and playback-position restore.
- Added compact floating playback controls, bottom-bar Profile switching, single-click play/pause, double-click full screen, and unified Video shortcuts.
- Hoshi can parse SRT/VTT and selected embedded text tracks, with a clickable lookup overlay, full transcript, font/size controls, and blur/hidden subtitle masks.
- Mining History, Transcript, and Chapters now share one study sidebar with subtitle capture, seek, copy, delete, and cross-video restoration.
- Video mining supports `{video-screenshot}` and `{video-audio-clip}` for the current frame and selected audio track over the subtitle range.

#### Profiles, dictionaries, and mining

- Added independent Profiles, including built-in `Japanese EPUB` and `Japanese Video`, support for English-content Profiles, automatic book-language selection, and per-book overrides.
- Each Profile can store separate dictionaries, Reader appearance, and Anki mappings; dictionary backups remain compatible with the older single-Profile format.
- Added English word and phrase lookup, apostrophe/hyphen-aware scanning, IPA field output, and approximate word-count progress.
- Added separate novel and anime default Anki mappings: novels use `{sasayaki-audio}` and `{book-cover}`; anime uses `{video-audio-clip}` and `{video-screenshot}`.
- Fixed missing book covers, missing MKV video audio attachments, and Previous Subtitle seeking to the current cue instead of the preceding cue.

### Installation

- Choose `Hoshi-Reader-Mac-0.6.0-beta.1.dmg` for EPUB reading.
- Choose `Hoshi-Reader-Mac-Video-0.6.0-beta.1.dmg` for video learning.
- Both builds share the same app identity and user data. Do not install or run both at the same time.
- The app is ad-hoc signed but does not have a Developer ID signature or Apple notarization. If macOS blocks it, right-click `Hoshi Reader.app` in Finder and choose **Open**, or allow it in **System Settings → Privacy & Security**.
- Matching `.sha256` files are included for download verification.
