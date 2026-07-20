# Niratan Mac Changelog

This changelog records user-visible changes only. Implementation details, investigation logs, and temporary experiments belong in commits, issues, or focused design docs.

## Unreleased

### 中文

- 游戏手柄设置现在与键盘快捷键使用相同的完整动作列表和分类；Video 版可为全部播放、字幕、音频、循环、Transcript 与全屏动作录制手柄按键，并保留旧有 Reader / Sasayaki 映射。
- Anki 字段映射现在使用合并的可编辑下拉输入框，整项只绘制一层 macOS 26 Liquid Glass，不再在原生玻璃外叠加旧式灰色 material；App 升级后仍会保留自定义及明确清空的字段映射。
- 修复从查词框点击放大镜时 Reader 仍停留在最前方，以及 Anki 首次创建浏览器窗口时可能显示上一次搜索的问题；现在会先把前台交给 Anki，再由 Anki 通过单次查询创建或更新浏览器窗口。
- 设置页的文本与密码输入框现在统一采用 macOS 26 风格的交互式玻璃胶囊外观，并保留清晰的键盘焦点提示；音频来源的添加按钮也改为配套的原生圆形玻璃按钮。
- 视频库会根据窗口宽度自动收纳搜索、排序、布局和来源操作；列表与海报模式也统一使用更易点击的分组展开/折叠标题，并改善侧栏与内容背景的玻璃层次。

### English

- Game Controller settings now expose the same complete action list and categories as Keyboard Shortcuts. Video builds can bind every playback, subtitle, audio, loop, transcript, and full-screen action while preserving existing Reader and Sasayaki mappings.
- Anki field mappings now use one combined editable menu field with a single macOS 26 Liquid Glass surface instead of layering native glass around the older gray material control. App upgrades continue to preserve custom and explicitly cleared mappings.
- Fixed the Reader remaining in front after the lookup magnifying-glass action and Anki's newly created Browser sometimes showing its previous search. Niratan now hands the foreground to Anki before one Browser request creates or updates the matching-note view.
- Settings text and secure fields now share a macOS 26-style interactive glass capsule appearance with a clear keyboard focus indication, and the audio-source add action now uses the matching native circular glass button.
- The Video library now condenses search, sort, layout, and source actions as the window narrows. List and poster layouts also share easier-to-click collapsible section headers with improved glass layering across the sidebar and content.

## 1.4.1

### 中文

- 主界面、书架、词典和设置统一采用 macOS 26 Liquid Glass 背景与原生玻璃控件，在浅色、深色和自定义主题下保持一致的桌面层次。
- Reader 新增书内图片库，可按正文顺序通过自适应多列网格浏览 EPUB 图片；尚未读到的插画会按字符进度保持模糊，打开大图后需再次点击才会解锁，预览支持按钮及左右方向键连续切换并保留图库位置。
- 合并内置“日语 EPUB”和“日语视频”为唯一的“日语” Profile；同一套 Anki 默认映射现在同时服务小说与视频，`{book-cover}` / `{sasayaki-audio}` 在视频制卡时会自动生成当前画面截图和字幕音频，因此 Anki 设置只保留一个默认映射按钮。
- Profile 现在统一由“设置 > Profiles”全局控制；书架、Reader 和 Video 不再提供各自的 Profile 切换，也不会因打开内容或切换窗口而隐式更换配置，从而避免重复加载词典与制卡设置。
- 修复启用英语 Profile 后 Video 字幕仍从点击字符按日语方式扫描的问题；现在点击英文单词中间也会从完整单词开头查词，与 Reader 一致。
- 修复大型内嵌 ASS 字幕可能让 Video 播放器卡死，以及 ASS 主台词高度与查词位置不一致的问题；字幕扫描、去重和时间线构建改为可取消的后台任务，普通底部主台词现在由同一个可见文本层负责显示、拖选、查词、高亮和弹窗定位，并会实时跟随字幕高度设置；切换 ASS 轨时不再先闪现完整 libass 字幕，作者定位文字、歌词、卡拉 OK、绘图和多层特效仍由内置 libass 保持原位渲染。
- 修复 Video 播放过程中保存进度可能引起周期性 CPU 升高的问题；现有播放位置、恢复选项和字幕选择会无损迁移，视频书架也不再因无关设置变化反复刷新。
- 修复部分 YouTube 历史视频没有字幕，以及逐词字幕把时间戳和 `<c>` 标签显示成正文的问题；现在优先使用发布者字幕，在没有发布者字幕时回退到自动字幕，并会重试此前缓存为空的字幕信息。
- Video 设置与播放器“视频”侧边栏新增 Anime4K 超分辨率，可选择关闭、快速或高画质；着色器按需下载并校验，默认关闭。
- Video 播放时，鼠标静止后光标会与底部控制栏同时隐藏；移动鼠标、离开播放器、打开学习界面或切换窗口后会恢复。
- Video Transcript 侧边栏新增“上一条 / 下一条”字幕对齐按钮，可将播放头左侧最近已结束或右侧最近未开始的字幕对齐到当前时间；默认快捷键为 `Shift+← / Shift+→`，并可在统一快捷键设置中修改。
- 修复查词框已检测到 Anki 重复卡片时放大镜仍为灰色的问题；现在会按当前重复检查范围找到已有笔记，点击放大镜即可在 Anki 中打开。
- 修复从查词框点击放大镜跳转 Anki 时，macOS 输入法与 WebView 焦点交接可能导致 Niratan 闪退的问题。

### English

- The main window, Bookshelf, Dictionary, and Settings now share a macOS 26 Liquid Glass background and native glass controls across light, dark, and custom themes.
- Reader now includes an in-book image gallery that lists EPUB images in reading order and opens any thumbnail in the existing full-screen image viewer.
- Merged the built-in Japanese EPUB and Japanese Video Profiles into one Japanese Profile. The same Anki defaults now serve books and videos: `{book-cover}` and `{sasayaki-audio}` automatically produce the current frame and subtitle audio during Video mining, so Anki Settings has one defaults action.
- Profiles are now controlled globally from Settings > Profiles. Bookshelf, Reader, and Video no longer switch Profiles independently or implicitly when content opens or window focus changes, avoiding redundant dictionary and mining-settings reloads.
- Fixed Video subtitles continuing to scan from the clicked character as Japanese after the English Profile was enabled. Clicking inside an English word now looks up from the full word's beginning, matching Reader behavior.
- Fixed large embedded ASS tracks potentially freezing the Video player and ASS primary dialogue drifting away from its lookup target. Subtitle scanning, deduplication, and timeline preparation now run as cancellable background work. Ordinary bottom dialogue uses one visible layer for rendering, selection, lookup, highlighting, popup anchoring, and live vertical-position changes. Switching ASS tracks no longer flashes the complete libass track first, while authored positioning, lyrics, karaoke, drawings, and layered effects remain fixed and rendered by bundled libass.
- Fixed periodic CPU spikes while Video saved playback progress. Existing positions, resume options, and subtitle selections migrate without data loss, and unrelated preference changes no longer refresh the video library.
- Fixed missing captions on some YouTube history items and karaoke captions rendering timestamps and `<c>` tags as text. Publisher captions remain preferred, automatic captions are used when needed, and previously empty caption metadata is retried.
- Video Settings and the player Video sidebar now offer optional Anime4K upscaling with Off, Fast, and High Quality presets. Verified shaders download on demand, and the feature defaults to Off.
- During Video playback, the pointer now hides together with the bottom controls after the same idle delay and returns on pointer movement, player exit, study overlays, or window deactivation.
- The Video Transcript sidebar now aligns the closest ended or upcoming subtitle to the current playback time with Previous/Next buttons. The default shortcuts are `Shift+Left/Right` and remain configurable in the unified shortcut settings.
- Fixed the lookup magnifying-glass button remaining disabled after an existing Anki card was detected. Duplicate checks now resolve matching note IDs in the configured scope so the notes can be opened in Anki.
- Fixed a possible Niratan crash during the macOS input-method and WebView focus handoff when the lookup magnifying-glass button opens Anki.

## 1.4.0

### 中文

- 查词框制卡成功后会在对应词条内显示放大镜按钮，点击即可让 Anki 打开并定位到刚添加的笔记；Reader、词典页和 Video 查词共用这一行为。

### English

- After a card is added, its lookup entry now shows a magnifying-glass button that opens Anki directly on the newly added note. Reader, Dictionary, and Video lookup surfaces share this behavior.

## 1.3.11

### 中文

- Reader 窗口会在关闭或正常退出 Niratan 前显式保存最后的普通窗口大小和位置；反复关闭、重新打开或重启 App 后打开书籍仍会恢复，并避免关闭过程中收缩的临时窗口覆盖记录。全屏状态不会覆盖普通窗口记录。

### English

- The Reader now explicitly saves its last windowed size and position before closing or quitting Niratan, restores them across repeated reopen and relaunch cycles, and prevents a transient teardown-sized window or full screen from overwriting the windowed frame.

## 1.3.10

### 中文

- 修复 Anki 设置在重启后丢失的问题：AnkiConnect 地址与 API Key、字段映射和标签现在会在编辑时立即保存；从非默认 Profile 修改全局连接设置时，也不会再覆盖默认 Profile 的牌组、模型、字段映射和重复检查选项。
- 修复手动清空 Anki 字段映射后，重启、重连或刷新牌组/模型信息时该字段可能被默认模板重新填入的问题；明确清空的映射现在会保持禁用。

### English

- Fixed Anki settings being lost after restarting the app. The AnkiConnect address and API key, field mappings, and tags now save immediately while editing. Updating global connection settings from a non-default Profile no longer overwrites the default Profile's deck, note type, field mappings, or duplicate-check options.
- Fixed manually cleared Anki field mappings being restored from default templates after restarting, reconnecting, or refreshing deck and note-type metadata. Explicitly cleared mappings now remain disabled.

## 1.3.9

### 中文

- Video 现在可直接添加或打开 YouTube 链接，支持在可用画质间切换、保存资料库与播放进度、字幕查词和视频制卡；字幕列表只显示视频发布者提供的原生字幕，不再下载自动生成字幕。“添加链接”窗口会明确标注此功能仍处于实验阶段。
- 修复通过“添加链接”打开 YouTube 时播放器窗口可能闪退，以及发布者字幕虽已列出却因空响应无法显示的问题。
- 修复 Video 窗口可被自由拉伸而产生黑边的问题；普通窗口现在始终按当前视频比例缩放，打开学习侧栏时仍保持视频画面比例，并避开原生全屏切换期间的窗口约束。
- 改进 Video 字幕与播放控制稳定性：字幕垂直位置现在使用相对实际视频画面的无数字顶部到底部滑杆，在字幕块能够容纳时可完整贴齐画面顶部或底部，并在窗口、全屏、不同显示尺寸及控制栏布局间保持相对位置；Compact Bottom 控制栏始终贴底，播放与倍速按钮不再叠加独立玻璃背景，点击视频其他位置可关闭倍速面板。
- Video 字幕调轴现在允许通过按钮或直接输入调整到 `-60000～60000 ms`，拖动条仍保留精调所需的 `-10000～10000 ms` 范围；超出拖动范围的偏移可以正确保存并在重开视频后恢复。

### English

- Video can now add or open YouTube links with available-quality switching, library and playback-history persistence, subtitle lookup, and video mining. Subtitle choices include only publisher-provided tracks and no longer download auto-generated captions. The Add Link sheet clearly labels this feature as experimental.
- Fixed a possible crash when Add Link opened the YouTube player, and publisher subtitles being listed but failing to display after an empty caption response.
- Fixed the Video window being freely stretched into letterboxing. Windowed resizing now follows the current video aspect ratio, keeps the video surface aspect-correct with the study sidebar open, and avoids window constraints during native full-screen transitions.
- Improved Video subtitle and playback-control stability: vertical placement now uses an unlabeled top-to-bottom slider relative to the fitted video picture, can align the complete subtitle stack with either edge when it fits, and preserves that relative position across windowed, full-screen, display-size, and control-layout changes; Compact Bottom stays anchored, play and speed no longer add separate glass backgrounds, and clicking elsewhere on the video dismisses the speed panel.
- Video subtitle timing now supports `-60000...60000 ms` through buttons or direct input while keeping the slider focused on `-10000...10000 ms`; offsets outside the slider range persist and restore when reopening the video.

## 1.3.6

### 中文

- 修复 Reader 查词弹窗内词典交叉引用无法用鼠标点击跳转的问题；跳转后即使关闭了常驻操作栏也会显示前进/后退控制，有声书播放控制存在时会合并为同一行并保持无底色的大点击区域。
- 修复 Reader 查词弹窗内选中文本后，鼠标移回阅读区会取消选区的问题；释义拖选越过弹窗边界后松开也会保留选中内容，Shift 悬停查词不受影响。
- 提升 Video 播放画质：Retina 屏幕现在按物理像素渲染，减少系统二次放大造成的发软；同时改进 10-bit、SDR 显示器色彩配置、可选 HDR/EDR 输出和屏幕刷新同步，并在硬件不支持时自动回退。
- 修复 Reader 统计在离开阅读窗口或统计面板后仍继续计时的问题；统计面板现在会实时刷新，并在面板处于焦点时继续计时，切到其他窗口或 App 后暂停且不会补算离开时间。
- 改进 Video 字幕在复杂画面上的可读性：字幕外观现在提供简洁的边缘样式与强度控制，可选择更深的柔和阴影、清晰描边或更强的高对比度描边，并为新用户默认启用高对比度样式。
- 修复多次打开和关闭 Reader 后，旧 Reader 实例可能在关闭时覆盖较新的阅读统计，导致当天已读字符数回退的问题。
- 修复按 Esc 关闭 Reader 窗口时，强制销毁 SwiftUI Hosting View 可能导致整个 App 崩溃的问题。

### English

- Fixed dictionary cross-references in Reader lookup popups not responding to normal mouse clicks. Redirect history controls now appear after a jump even when the persistent action bar is off, and share one background-free, generously clickable row with Sasayaki controls when audio is available.
- Fixed Reader lookup popup text selections being cleared when the pointer returned to the reading surface. Selections now also survive definition drags released beyond the popup boundary, without affecting Shift-hover lookup.
- Improved Video playback quality: Retina displays now render at physical-pixel resolution to avoid softness from an extra system upscale, with better 10-bit precision, calibrated SDR display color, optional HDR/EDR output, and display-synchronized presentation with automatic capability fallbacks.
- Fixed Reader statistics continuing after leaving the Reader window or Statistics sheet. The open Statistics sheet now updates live and keeps counting while focused, then pauses without backfilling inactive time after switching to another window or app.
- Improved Video subtitle readability on busy footage with compact Edge Style and Edge Strength controls for a darker Soft Shadow, Clear Outline, or a stronger High Contrast outline, which is now the default for new users.
- Fixed stale Reader instances overwriting newer reading statistics during window close after repeatedly opening and closing the Reader, which could make the day's character count move backwards.
- Fixed the app potentially crashing when Escape closed a Reader window while its SwiftUI hosting view was being torn down.

## 1.3.0

### 中文

- 项目正式更名为 Niratan，App、Xcode 工程、Light/Video scheme、DMG 产物名、更新检查和发布说明都改用新名称；bundle id 继续保留为 `moe.shishamo.hoshi` 以维持用户数据兼容，发布包会同时附带旧文件名以便旧版 App 内更新入口过渡。
- Reader 新增歌词模式：在已完成 Sasayaki SRT 匹配并导入音频后，可从 Reader 进入沉浸式同步歌词层；歌词视觉层使用 macOS Metal 渲染边界，支持无背景的当前行进度高亮、播放控制、查词弹窗、统计计数，并在退出时回到当前歌词对应的小说位置。
- 歌词模式新增“歌词遮罩”开关，播放时可把歌词柔化为模糊遮罩，并在鼠标悬停或查词弹窗打开时恢复清晰文本，横排和竖排歌词都会自动填满可用空间。
- 修复歌词模式和全局查词的弹窗定位：歌词查词会贴近歌词上下方，竖排长歌词会自动分列换行，当前播放歌词更稳定可查词；全局查词会优先贴近高亮选词，并保持父子弹窗的分层关闭行为。
- Reader 横排分页新增可选的双栏页面布局，并修复双栏下图片页、短文本章末尾和跨章翻页可能卡住的问题。
- 设置页的下载推荐词典和更新词典现在会先打开可勾选列表；手动更新会全量检查可更新词典的远端版本，手动导入且可识别来源的词典也会参与检测，并在更新后刷新候选状态，已经最新的词典不会再出现在更新列表中。
- 修复设置页进入词典折叠自定义后无法关闭的问题。
- 修复 Reader 和 Video 查词弹窗没有跟随词典双栏布局开关的问题，并保留弹窗内鼠标选中文本且不带振假名。
- Video 新增“快进字幕空档”开关，可按自定义速度在两句字幕之间临时加速播放，并在接近下一句字幕时恢复原播放速度。
- 修复 Video 大字号字幕在自动换成多行时底部文字可能被裁掉的问题。
- 修复 Reader 跳转面板的标注列表在部分 EPUB 目录重复指向同一章节时可能闪退的问题。
- 修复 Sasayaki 手动上一句/下一句在跨图片页或跨章节时可能停住、清掉高亮或跳到错误位置的问题。

### English

- The project is now officially named Niratan. The app, Xcode project, Light/Video schemes, DMG artifact names, update checker, and release notes use the new name, while the bundle id remains `moe.shishamo.hoshi` for user-data compatibility and release assets keep legacy filename aliases for older in-app updaters.
- Reader adds Lyrics Mode: after completing a Sasayaki SRT match and importing audio, you can enter an immersive synced lyrics layer; the lyrics visual layer now uses a macOS Metal render boundary with background-free current-line progress highlighting, playback controls, lookup popups, statistics counting, and an exit path back to the matching novel position.
- Lyrics Mode now includes a Lyrics Mask toggle that softens playing lyrics into a blurred mask, restores clear text on hover or while lookup popups are open, and lets both horizontal and vertical lyrics fill the available space.
- Fixed lookup popup placement in Lyrics Mode and global lookup: lyric lookups now appear above or below the lyric text, long vertical lyrics wrap into columns, the current playing lyric is more reliably lookupable, and global lookup prefers the highlighted selection while preserving parent/child popup dismissal behavior.
- Reader now offers an optional two-column horizontal page layout, with fixes for page turns that could stall on image pages, short chapter endings, and chapter boundaries.
- Recommended dictionary downloads and dictionary updates in Settings now open selectable lists; manual updates now check all update-capable dictionaries, include manually imported dictionaries with a recognized source, and refresh candidates afterward, so already-current dictionaries no longer appear in the update list.
- Fixed the dictionary collapse customization view in Settings so it can be closed after opening.
- Fixed Reader and Video lookup popups not following the Dictionary two-column layout toggle, while preserving mouse text selection inside popup entries without ruby annotation text.
- Video adds a Fast-forward Subtitle Gaps toggle that temporarily speeds playback at a configurable speed between subtitle lines, then restores the original speed near the next subtitle.
- Fixed Video subtitles with large font sizes being clipped at the bottom after wrapping into multiple visual lines.
- Fixed a crash in the Reader Go To highlight list when some EPUB table-of-contents entries point to the same chapter.
- Fixed Sasayaki manual previous/next cue navigation getting stuck, clearing highlights, or landing at the wrong position across image pages or chapter boundaries.

## 1.1.0

### 中文

- 书架右上角新增“统计”入口，可在书架内查看全局统计 Dashboard，包含今日、本周、阅读日历、趋势、书籍排行和书架对比。
- 统计 Dashboard 可直接调整每日字数/时长目标和每周达标天数，并用于进度和连续达标计算。
- 统计 Dashboard 新增书籍排行、速度摘要和书架对比；趋势图支持字数、时长、速度指标、柱状/折线样式，以及独立的日/周/月趋势粒度。
- 趋势图的柱状图和折线图支持悬停查看日期、指标值、字数、时长、速度和主要贡献书籍。
- 进入统计 Dashboard 时会先展示界面骨架，优先复用缓存快照，并在后台刷新本地统计数据，减少进入等待感。

### English

- Bookshelf now has a top-right Statistics entry that opens a global dashboard in Bookshelf, covering today, this week, the reading calendar, trends, book rankings, and shelf comparison.
- The Statistics dashboard now lets you adjust daily character/time goals and weekly target days directly for progress and streak calculations.
- The Statistics dashboard now includes book rankings, speed insights, and shelf comparison, and the trend chart supports character, duration, and speed metrics, bar/line styles, and independent day/week/month grains.
- Trend bars and line points now show hover details with date, metric value, characters, duration, speed, and top contributing books.
- Opening the Statistics dashboard now shows the dashboard skeleton immediately, reuses cached snapshots first, and refreshes local statistics in the background.

## 1.0.1

### 中文

- 全局查词的连续查词和嵌套弹窗现在会在独立面板中打开，减少覆盖或挤压主查词窗口的情况。
- Reader 打开本地书籍时不再短暂显示“无法打开书籍”，也不会因此把独立阅读窗口缩成小尺寸。

### English

- Global lookup follow-up searches and nested popup stacks now open in separate panels, reducing cases where they cover or squeeze the main lookup window.
- Reader no longer briefly shows the failed-open state while loading local books, preventing that transient state from shrinking the dedicated Reader window.

## 1.0.0

### 中文

- Niratan Mac 进入首个原生 macOS 稳定正式版，继续提供 Light 和 Video 双安装包，覆盖小说阅读、查词、Google Drive 同步、Anki 制卡和 Video 学习播放器。
- Google Drive 登录凭据现在合并为单个钥匙串项，设置页和自动同步状态刷新不再反复读取 token 明文，减少连续出现 macOS 钥匙串授权弹窗的情况。

### English

- Niratan Mac is now the first stable native macOS release, continuing to provide separate Light and Video installers for novel reading, lookup, Google Drive sync, Anki card creation, and the Video study player.
- Google Drive credentials are now bundled into one Keychain item, and Settings/auto-sync state refreshes no longer repeatedly read token secrets, reducing repeated macOS Keychain permission prompts.

## 0.6.6

### 中文

- Google Drive 登录凭据现在合并为单个钥匙串项，设置页和自动同步状态刷新不再反复读取 token 明文，减少连续出现 macOS 钥匙串授权弹窗的情况。

### English

- Google Drive credentials are now bundled into one Keychain item, and Settings/auto-sync state refreshes no longer repeatedly read token secrets, reducing repeated macOS Keychain permission prompts.

## 0.6.5

### 中文

- Reader 会迁移旧版过小或离屏的窗口尺寸记录，重新打开时优先回到当前屏幕的可见区域。
- Google Drive 登录凭据存储对齐当前 macOS App 身份和上游账号键名，减少升级或重连后认证状态不一致的情况。

### English

- Reader now migrates outdated tiny or off-screen saved window frames so reopening a book returns to the current display's visible area.
- Google Drive credential storage now follows the current macOS app identity and upstream account-only keys, reducing inconsistent auth state after upgrades or reconnecting.

## 0.6.4

### 中文

- Video 悬浮与贴底控制栏继续打磨按钮、菜单、时间轴预览和紧凑布局表现，让两种布局使用同一套播放状态与交互管线。
- 设置页的词典和音频来源排序改为列表内拖拽手势，修复部分 macOS 26 环境下拖动排序不稳定的问题。
- Reader 新窗口默认位置会落在当前可见屏幕内，减少外接显示器切换后窗口出现在屏幕外的情况。

### English

- Video floating and compact-bottom controls have been polished across buttons, menus, timeline previews, and compact layout behavior while sharing the same playback state and interaction pipeline.
- Dictionary and audio-source ordering in Settings now uses in-list drag gestures, fixing unreliable reorder behavior on some macOS 26 setups.
- New Reader windows now default to a visible screen frame, reducing cases where windows appear off-screen after external display changes.

## 0.6.3

### 中文

- Video 设置新增控制栏布局选项，可在默认悬浮控制栏和贴底紧凑控制栏之间切换。
- 贴底紧凑控制栏减少播放画面中央遮挡，并同步调整字幕、弹窗和时间轴预览的底部避让距离。

### English

- Video settings now include a control bar layout option for switching between the default floating controls and a compact bottom-aligned control bar.
- The compact bottom control bar reduces obstruction in the center of the video and adjusts subtitle, popup, and timeline-preview bottom clearances accordingly.

## 0.6.2

### 中文

- 检查更新入口恢复为可见按钮；发现新版本后可直接在 App 内下载对应 Light 或 Video DMG，校验后打开安装包，不再需要手动去 GitHub Releases 查找。
- Reader 独立窗口会记住上次关闭时的大小和位置，再次打开书籍时不再每次重置为默认窗口。
- 修复横排 Reader 查词弹窗在窗口边缘附近定位不稳定的问题，减少弹窗贴边或偏离选中文本的情况。

### English

- Restored a visible update-check entry. When a new version is available, Niratan can now download the matching Light or Video DMG in-app, verify it, and open the installer instead of sending users to GitHub Releases.
- Reader windows now remember their last size and position instead of resetting to the default frame every time a book is opened.
- Fixed unstable lookup popup placement near window edges in horizontal Reader layout, reducing cases where the popup hugs an edge or drifts away from the selected text.

## 0.6.1

### 中文

- Video 字幕导入新增 ASS/SSA 支持，可提取 Dialogue 文本用于字幕列表、查词和挖卡，样式渲染仍交由 mpv 处理。
- Video 资料库的列表和海报视图会为可见条目补齐缺失缩略图，播放窗口打开期间则暂停后台缩略图生成，减少播放和打开视频时的磁盘抢占。
- Video 制卡截图和音频片段导出共用一次后台媒体生成窗口，制卡可更快返回，并在导出完成后自动恢复资料库缩略图任务。
- 使用稳定发布证书签名的 DMG 更新后，更容易保留 macOS 全局查词所需的无障碍授权，减少升级后重新授权的情况。

### English

- Video subtitle import now supports ASS/SSA files and extracts Dialogue text for transcripts, lookup, and card mining while leaving styled rendering to mpv.
- Video library list and poster views now fill in missing thumbnails for visible items, while background thumbnail generation pauses for the duration of an open player window to reduce disk contention during playback and video opening.
- Video card mining now shares one background media-generation window for screenshots and audio clips, returns to card creation faster, and resumes library thumbnail work after export finishes.
- DMG updates signed with the stable release certificate are more likely to preserve the macOS Accessibility permission used by global lookup, reducing the need to reauthorize after upgrading.

## 0.6.0

### 中文

- 正式完成从 Mac Catalyst 到原生 macOS App 的迁移，保留书籍、进度、bookmark、sidecar、词典、Anki 配置和 Google token 的升级兼容路径，并继续使用 `moe.shishamo.hoshi` 作为 App 身份。
- 新增 Light 和 Video 两个原生构建。Video 版本内置 universal libmpv，Light 版本不包含 mpv；两个版本共享用户数据，但不要同时运行。
- 新增独立 Profile、日英内容配置、书籍语言自动选择、Profile 独立词典/Reader 外观/Anki 映射，以及兼容旧备份的词典备份恢复。
- 新增英语单词和短语查词、撇号/连字符扫描、IPA 字段输出、近似词数进度，以及小说/动漫两套默认 Anki 映射。
- Reader 新增可复用原生阅读窗口、书内搜索、章节/搜索/高亮统一跳转面板，并修复窗口缩放、全屏、竖排、图片/SVG、快捷键重复触发和失败返回路径。
- Sasayaki 恢复 SRT 匹配，改进播放/跳句/关闭 Reader/退出 App 时的播放位置保存，并在同步时导入更新的 Sasayaki 位置。
- 书架新增 EPUB 拖放导入、本地书籍手动排序、导出面板定位修复、封面缩略图稳定性改进，以及更紧凑的封面与进度显示。
- Popup 与词典新增大尺寸双栏释义布局、跨 App 选中文本查词和剪贴板回退读取，并修复词典设置重启回退、重复制卡状态和上下文选择体验。
- Google Drive 同步恢复书籍刷新入口，支持后台多本下载、进度显示、较短网络超时、短暂离线降噪和 Sasayaki 位置同步。
- Video 新增本地资料库，可添加文件夹、扫描视频、搜索、排序、按继续观看/未观看/已完成/缺失/最近/系列/文件夹/合集/收藏/待复习浏览，管理本地标题、标签、备注、合集和绑定字幕。
- Video 资料库新增海报缩略图、智能集合、现代化控件和主题自适应玻璃背景；缩略图生成通过单任务后台调度器运行，并在播放、查词和制卡时暂停。
- Video 播放器新增独立播放窗口、播放列表、拖放导入、字幕/音频/章节轨道、位置和字幕状态恢复、紧凑悬浮控制栏、底栏 Profile、单击播放、双击全屏和统一快捷键。
- Video 播放体验新增硬件解码、反交错、HDR、亮度/对比度/饱和度/Gamma/色相调节、滚动调节音量、时间轴悬停预览、窗口比例适配和稳定的原生全屏退出。
- Video 字幕支持 SRT/VTT 和内嵌文字轨解析、点击/Shift 悬停查词、选择复制、字幕列表、章节列表、挖卡历史、字重/阴影/背景/垂直位置/高亮文字色和 50 ms 时间校准。
- Video 制卡支持 `{video-screenshot}` 和 `{video-audio-clip}`，会先做重复检查和字段映射预检，跳过未映射媒体，并优先直接写入 Anki `collection.media` 后台完成截图/音频生成。
- 设置页拆分 Reader/Video 分组，统一键盘快捷键和手柄控制入口，新增 AnkiConnect API key，并修复 macOS 26 设置背景、拖放排序和快捷键设置崩溃。

### English

- Completed the migration from Mac Catalyst to a native macOS app while preserving upgrade paths for books, progress, bookmarks, sidecars, dictionaries, Anki configuration, and Google tokens. The app identity remains `moe.shishamo.hoshi`.
- Added separate native Light and Video builds. The Video build bundles universal libmpv, while the Light build does not include mpv. Both variants share user data, but should not be run at the same time.
- Added independent Profiles, Japanese and English content setup, automatic book-language selection, Profile-specific dictionaries, Reader appearance and Anki mappings, plus dictionary backup/restore compatibility with older backups.
- Added English word and phrase lookup, apostrophe/hyphen-aware scanning, IPA field output, approximate word-count progress, and separate default Anki mappings for novel and anime cards.
- Reader now has a reusable native reader window, in-book search, and a unified jump panel for chapters, search results and highlights, with fixes for resizing, full screen, vertical layout, images/SVGs, duplicate shortcuts, and failed-load recovery.
- Sasayaki SRT matching is restored, and playback position now survives playback, cue jumps, Reader window close, app quit, and sync import of newer Sasayaki positions.
- Bookshelf now supports drag-and-drop EPUB import, manual local-book ordering, steadier export sheet placement, more stable cover thumbnails, and denser cover/progress presentation.
- Popup and Dictionary now support an optional two-column glossary layout, cross-app selected-text lookup with clipboard fallback, and fixes for Dictionary settings persistence, duplicate-card status and context selection.
- Google Drive sync restores the book refresh entry, supports background multi-book downloads with progress, shorter network timeouts, quieter transient offline handling, and Sasayaki position sync.
- Video adds a local library for folders, scanning, search, sorting, Continue Watching, Unwatched, Finished, Missing, Recent, Series, Folders, Collections, Favorites and Needs Review, plus local titles, tags, notes, collections and bound subtitles.
- Video library adds poster thumbnails, smart collections, modern controls and theme-adaptive glass backgrounds. Thumbnail generation now runs through a single-worker scheduler that pauses during playback, lookup and card media export.
- Video playback adds a dedicated player window, playlist handling, drag-and-drop import, subtitle/audio/chapter tracks, playback and subtitle-state restore, compact floating controls, bottom-bar Profile switching, click play/pause, double-click full screen, and unified shortcuts.
- Video playback now includes hardware decoding, deinterlacing, HDR, brightness/contrast/saturation/gamma/hue controls, scroll-to-adjust volume, timeline hover previews, aspect-ratio fitting, and stable native full-screen exit.
- Video subtitles support SRT/VTT and embedded text tracks, click and Shift-hover lookup, selection/copying, transcript, chapters, mining history, font weight, shadow, background, vertical position, highlight text color, and 50 ms timing adjustment.
- Video mining supports `{video-screenshot}` and `{video-audio-clip}`, performs duplicate and field-mapping preflight before media work, skips unmapped media, and writes directly to Anki `collection.media` while screenshot/audio generation finishes in the background.
- Settings separates Reader and Video groups, centralizes keyboard shortcuts and game-controller controls, adds AnkiConnect API key support, and fixes macOS 26 settings backgrounds, drag reordering, and keyboard shortcut settings crashes.

## 0.6.0 Beta 4

- Added experimental, opt-in cross-App selected-text lookup: press the configurable global shortcut to show the active Profile's Niratan dictionary Popup near the pointer without copying text through the clipboard.
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
