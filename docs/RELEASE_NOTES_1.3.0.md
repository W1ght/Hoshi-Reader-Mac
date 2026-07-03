### 中文

- 项目正式更名为 Niratan：App、Xcode 工程、Light/Video scheme、DMG 产物名、更新检查和发布说明都改用新名称。
- 保留 `moe.shishamo.hoshi` bundle id 以维持用户数据兼容；发布包同时附带旧文件名，旧版 App 右上角更新入口也可以过渡到 Niratan。
- Reader 新增歌词模式：完成 Sasayaki SRT 匹配并导入音频后，可进入沉浸式同步歌词层，支持当前行进度高亮、播放控制、查词弹窗、统计计数，并在退出时回到对应小说位置。
- 歌词模式新增“歌词遮罩”开关，播放时可柔化歌词，鼠标悬停或查词弹窗打开时恢复清晰文本，横排和竖排歌词都会自动填满可用空间。
- 修复歌词模式和全局查词的弹窗定位：歌词查词会贴近歌词上下方，竖排长歌词会自动分列换行，当前播放歌词更稳定可查词；全局查词会优先贴近高亮选词，并保持父子弹窗的分层关闭行为。
- Reader 横排分页新增可选的双栏页面布局，并修复双栏下图片页、短文本章末尾和跨章翻页可能卡住的问题。
- 设置页的下载推荐词典和更新词典现在会先打开可勾选列表；手动更新会全量检查可更新词典的远端版本，手动导入且可识别来源的词典也会参与检测，已经最新的词典不会再出现在更新列表中。
- 修复设置页进入词典折叠自定义后无法关闭的问题。
- 修复 Reader 跳转面板的标注列表在部分 EPUB 目录重复指向同一章节时可能闪退的问题。
- 修复 Sasayaki 手动上一句/下一句在跨图片页或跨章节时可能停住、清掉高亮或跳到错误位置的问题。

### English

- The project is now officially named Niratan. The app, Xcode project, Light/Video schemes, DMG artifact names, update checker, and release notes use the new name.
- The bundle id remains `moe.shishamo.hoshi` for user-data compatibility, and releases also include legacy filenames so older in-app updaters can transition to Niratan.
- Reader adds Lyrics Mode: after completing a Sasayaki SRT match and importing audio, you can enter an immersive synced lyrics layer with current-line progress highlighting, playback controls, lookup popups, statistics counting, and an exit path back to the matching novel position.
- Lyrics Mode now includes a Lyrics Mask toggle that softens playing lyrics, restores clear text on hover or while lookup popups are open, and lets both horizontal and vertical lyrics fill the available space.
- Fixed lookup popup placement in Lyrics Mode and global lookup: lyric lookups now appear above or below the lyric text, long vertical lyrics wrap into columns, the current playing lyric is more reliably lookupable, and global lookup prefers the highlighted selection while preserving parent/child popup dismissal behavior.
- Reader now offers an optional two-column horizontal page layout, with fixes for page turns that could stall on image pages, short chapter endings, and chapter boundaries.
- Recommended dictionary downloads and dictionary updates in Settings now open selectable lists; manual updates check all update-capable dictionaries, include manually imported dictionaries with a recognized source, and keep already-current dictionaries out of the update list.
- Fixed the dictionary collapse customization view in Settings so it can be closed after opening.
- Fixed a crash in the Reader Go To highlight list when some EPUB table-of-contents entries point to the same chapter.
- Fixed Sasayaki manual previous/next cue navigation getting stuck, clearing highlights, or landing at the wrong position across image pages or chapter boundaries.
