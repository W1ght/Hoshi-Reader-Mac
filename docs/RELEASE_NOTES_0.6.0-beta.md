这是 Hoshi Reader 原生 macOS 版本的 0.6.0 Beta，包含 Light 与 Video 两种构建。

### 主要变化

- 新增独立 Profile：内置 `Japanese EPUB` 与 `Japanese Video`，分别保存词典、Reader 外观和 Anki 制卡配置，并支持日语/英语书籍自动选择。
- Video 新增字幕列表、章节与挖卡历史统一侧栏；支持外部及内嵌文字字幕、字幕采集、历史跳转和复制。
- Video 制卡可通过 `{video-screenshot}` 与 `{video-audio-clip}` 获取当前画面和字幕区间音频，并提供动漫默认字段映射。
- 重做 Video 播放控制与字幕交互，包括底栏 Profile 切换、字幕样式/遮罩、轨道切换、播放列表和快捷键。
- 小说默认字段映射支持 `{sasayaki-audio}` 与 `{book-cover}`，并修复书封面和视频音频附件缺失。
- 改进原生书架、Reader 版面、图片预览、Sasayaki 匹配以及多项快捷键稳定性。

### Beta 提示

- 建议升级前备份书籍与 Profile 配置。
- Video 功能仅包含在 `Hoshi-Reader-Mac-Video-0.6.0-beta.dmg`；Light 构建不包含 libmpv。
- 当前 DMG 未签名、未公证。如果 macOS 阻止启动，请在 Finder 中右键 App 并选择“打开”。
