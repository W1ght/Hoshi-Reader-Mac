# Hoshi Reader Mac Agent 指南

Hoshi Reader Mac 是 Hoshi Reader 的原生 macOS 桌面端项目。当前仓库只有一个原生 `Hoshi Reader` App target，产品能力分为小说阅读与视频学习两个模块：小说模块覆盖书架、阅读、查词、同步、制卡、本地音频、Sasayaki 和快捷键；视频模块在 Video 配置中启用本地视频库、播放器、字幕查词和视频制卡。

本文件是所有 agent 进入仓库后的常驻规则。任务状态、执行日志、长调查过程不要写进这里。

## 工作原则

- **Mac 用户可见行为是第一真源。** 不要为了机械同步 iOS、Android 或上游实现而破坏 Mac 端已经修好的交互、排版、快捷键、同步或发布流程。
- **原生 macOS 是唯一开发和发布目标。** 小说和视频功能、修复、重构和验证只保证 `Hoshi Reader` 原生 App；不得新增非 macOS target、跨平台桥接层或替代构建路径。
- **不要用整屏重写代替原生演进。** 优先复用现有表现良好的 SwiftUI 页面和业务服务；平台差异和模块差异只在窄边界里用 AppKit / NSViewRepresentable / NSWindow 能力补齐。
- **原生 App 必须保护用户数据兼容。** 书籍目录、bookmark、sidecar、词典配置、Anki 配置、Google token 和 UserDefaults 的兼容仍是硬约束；App 启动路径不得清理旧 token 或用“首次启动清理”代替显式退出登录。
- **修 bug 不叠补丁。** 先复现、定位边界，再改最小稳定方案；Reader / WKWebView / Popup / AnkiConnect / Google Drive / Sasayaki 尤其要避免猜测式修改。
- **不回滚用户或其他 agent 的未说明改动。** 工作树可能包含未提交功能、修复或验证内容；只处理当前任务范围。
- **不擅自发版、打 tag、push 或提交。** 用户明确要求 release / commit / push 后再执行。Commit message 必须使用 Conventional Commits，例如 `feat(reader): add mouse wheel page turn`。
- 新增用户可见设置、按钮、提示、toast、alert、页面标题或 release 可见文案时，必须考虑 `Localizable.xcstrings`，至少保证中文和英文不会裸露错误文案。

## 架构基线

### 当前 App 与模块

- `Hoshi Reader`：唯一原生 macOS App target，承载小说阅读模块，并在 Video 配置中启用视频学习模块。
- Light 配置：`Hoshi Reader` scheme，使用 `Debug` / `Release`，只发布小说阅读模块，不链接、复制或运行时查找 Video/libmpv。
- Video 配置：`Hoshi Reader Video` scheme，使用 `Debug-Video` / `Release-Video` 和 `HOSHI_VIDEO`，在小说阅读模块之外启用本地视频库、播放器、字幕查词、视频挖矿和视频制卡。
- Light 和 Video 构建产物的 App 名称、bundle id `moe.shishamo.hoshi` 和持久化目录相同，可以覆盖安装并共享用户数据。
- `main`：当前发布分支。Release tag 从 `main` 打。
- `codex/` 分支：较大功能、小说/视频跨模块重构或高风险修复优先使用。

### Native 架构约束

- SwiftUI 页面能复用就复用；不要为了“原生”或“模块化”重写成熟 UI。
- 原生 macOS 最低支持版本是 macOS 26.0；新 UI 可以直接使用 macOS 26+ SwiftUI / AppKit API，不要再为 macOS 15-25 增加 material fallback，除非明确决定下调 deployment target。
- 不新增 iOS 平台条件或双平台抽象；macOS 必要能力直接使用窄范围 AppKit bridge。
- AppKit 只用于 macOS 必要能力，例如 `NSWindow`、`NSViewRepresentable`、`NSEvent`、菜单、panel、focus/key capture、文件选择、窗口 chrome。
- `NativeMac/` 承载原生 App shell、窗口呈现和验证探针，但共享业务逻辑应留在 `Core/`、`Features/`、`Models/` 等已有边界。
- 共享代码修改以原生构建和对应功能验证为准。
- Video 条件编译只能存在于功能入口和 `Features/Video/` 的依赖边界。Reader、Dictionary、Popup、LocalAudio、AnkiConnect 等共享实现不得依赖 Video 才能编译；可共享纯数据 mining metadata，以保证 Light/Video 切换时配置兼容。
- Light 配置是小说模块发布包，不得链接、复制或运行时查找 libmpv；每次修改 `Features/Video/`、构建配置或打包脚本都要同时验证 Light。

### 项目结构

- `NativeMac/`：原生 macOS App 入口、sidebar/detail、Reader/Video 窗口呈现和 AppKit 能力；当前产品主路径。
- `Core/`：核心服务与持久化，如 Anki、词典、配置、本地文件服务、查词引擎、桌面输入管理。
- `Features/Bookshelf/`：小说书架、导入、排序、同步入口。
- `Features/Reader/`：小说阅读器、Reader WebView、分页/连续阅读、统计、Sasayaki 高亮。
- `Features/Popup/`：小说和视频共享的查词弹窗、渲染 CSS/JS、单词音频、制卡入口。
- `Features/Dictionary/`：词典搜索页。
- `Features/Settings/`：设置页、外观、Anki、音频、Sasayaki、快捷键、CSS 等。
- `Features/Sync/`：Google Drive OAuth、token、同步逻辑。
- `Features/Video/`：仅 Video 配置编译的视频库、视频播放、字幕 overlay、字幕查词协调和视频制卡上下文。
- `Models/`：数据模型。
- `Util/`：工具与更新检查。
- `script/`：本地构建、验证、打包、发版脚本。
- `.github/workflows/release-mac.yml`：tag 触发 DMG 构建和 GitHub Release。

## 真源文档

- `docs/TODO.md`：短状态、下一步、阻塞项、验证入口。
- `docs/ARCHITECTURE_REFACTORING.md`：长期架构方向，不记录执行流水账。
- `docs/READER_REGRESSION_TESTING.md`：Reader 回归验证、实际 EPUB 验证矩阵和数据安全规则。
- `docs/CHANGELOG.md`：只记录用户可见变化。
- `docs/UPSTREAM_SYNC_QUEUE.md`：上游同步队列。
- `docs/AGENT_DEVELOPMENT_GUIDE.md`：当前 agent 开发规范。
- `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`：本仓库任务前置工作流。

只有任务改变了对应文档的真源内容时，才更新该文档。不要把一次性调查日志、长命令输出或截图观察塞进 README 或 AGENTS。

- 任务改变 native 架构状态、小说/视频模块边界、已完成能力、剩余风险、下一步、阻塞项、验证入口或发布切换条件时，必须在同一任务内更新最小相关真源文档。
- 实现使 `docs/TODO.md`、`docs/ARCHITECTURE_REFACTORING.md` 或 `docs/READER_REGRESSION_TESTING.md` 的现状描述失真时，不得只改代码；声明完成前必须同步文档。
- native 架构或模块实现引起的真源文档更新默认放在同一个 commit，除非用户明确要求拆分。不要单独制造没有状态变化的文档流水账 commit。

## 经验沉淀

- 如果 agent 犯错后定位到未来可能复发的问题，应把最小可执行规则沉淀到对应真源文档。
- 需要所有会话常驻的仓库级规则才写入 `AGENTS.md`。
- 验证矩阵和脚本入口写入 `docs/READER_REGRESSION_TESTING.md` 或 `docs/TODO.md`。
- 当前架构事实和长期演进方向写入 `docs/ARCHITECTURE_REFACTORING.md` 或 `docs/TODO.md`。
- 沉淀内容必须具体、可执行、低歧义；先查是否已有等价规则，有则更新原规则。

## 构建与启动

默认构建和验证原生 macOS App 与两个发布包：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --video
./script/build_and_run.sh --video --verify
```

`script/build_and_run_native.sh` 是同一原生 target 的显式入口。普通签名构建可能因为本机缺少 `Mac Development` 证书失败；除非任务是签名/发布，不要把证书错误当作代码回归。

构建、启动和 UI 验证必须确认实际 App 身份：当前 Light/Video 产物的 bundle id 都是 `moe.shishamo.hoshi`。`--verify` 必须同时校验构建产物的 `CFBundleIdentifier` 和运行中进程的完整 executable 路径；仅凭进程名、窗口标题或 `/Applications/Hoshi Reader.app` 不得宣称验证成功。Computer Use 等 GUI 工具必须传入本次 DerivedData 产物的绝对 `.app` 路径或唯一 bundle id，不得只传模糊名称 `Hoshi Reader`，以免启动旧安装包。
多个 Codex 会话并行做 App UI 验证时，每个会话必须使用不同 `./script/build_and_run.sh --instance <id>` 或显式 `HOSHI_DERIVED_DATA_PATH`，并只操作该命令输出的 `.app` / executable path；`--instance` 只隔离构建产物、启动清理、进程验证和日志，不隔离同一 bundle id 下的 UserDefaults、Application Support、书籍 sidecar 或 Sasayaki 播放数据。

Video 配置通过 `./script/build_and_run.sh --video` 启动，内部使用 `Hoshi Reader Video` scheme，但构建产物仍是同 bundle id 的 `Hoshi Reader.app`。首次构建前运行 `./script/bootstrap_libmpv.sh`；依赖只允许落在被忽略的 `Vendor/libmpv/include/mpv/` 和 `Vendor/libmpv/lib/`。

## Release 流程

- 版本号来自 `Hoshi Reader.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`。
- GitHub Actions 通过 `v*.*.*` tag 构建 Light（小说模块）和 Video（小说 + 视频模块）两个原生发布包，并发布两套 DMG 和 checksum。若配置 `HOSHI_RELEASE_CERTIFICATE_P12_BASE64`、`HOSHI_RELEASE_CERTIFICATE_PASSWORD` 和 `HOSHI_RELEASE_SIGNING_IDENTITY`，打包脚本会用稳定发布证书签名；否则回退 ad-hoc 签名。不做 notarization。不得移除 arm64 可执行文件的全部签名，否则 Apple Silicon 会在启动时终止进程。
- `script/package_mac.sh <version> light|video` 是打包真源；正式 release 必须两个 variant 都成功，Light 产物不得包含 mpv，Video 产物必须自带 universal dylib 且没有 Homebrew 路径。
- 全局查词的无障碍授权由 macOS TCC 绑定到 App 的代码签名要求。ad-hoc 发布包的要求包含每次构建变化的 cdhash，更新后可能需要用户在系统设置里删除并重新授权；稳定证书签名是保留授权的发布前提。
- 发布前确认工作树干净、当前分支是 `main`、版本号正确、tag 不存在。
- 发布日志写用户可见改动，优先中文；不要把 CI、agent workflow、构建脚本或内部重构写成用户功能。
- `script/release_mac.sh` 会改版本、创建 Conventional Commit、推送分支和 tag；仅在用户明确批准 release 后运行。
- 不要上传不需要的 source zip 或 app zip；Release 产物以 DMG 和 checksum 为主。

## 上游同步

上游远端：

```bash
git fetch upstream
git log --oneline main..upstream/develop
```

同步或移植上游功能时：

- 先读 diff，确认是否涉及设置页、Reader WebView、popup 渲染、词典导入、图片显示、Sasayaki 或同步。
- 上游 iOS 行为是参考，不是无条件覆盖；Mac 端已修复的窗口缩放、安全区、全屏导航、触摸板禁用、鼠标滚轮、AnkiConnect、本地音频路径不能被回退。
- 对设置页功能要检查本仓库是否已有 Mac/native 替代实现，避免重复入口。
- 对 Reader / Popup / Dictionary 的 JS、CSS、WebView 改动要特别小心；最终判断以原生 macOS 的 WKWebView 表现为准。

## 用户可见 UI

- Mac UI 应优先遵守 macOS 桌面交互：窗口、sidebar、toolbar、keyboard shortcut、menu、focus、hover、context menu、scroll wheel、file picker。
- macOS 26 / Liquid Glass 风格可以采用系统组件和材质，但不要用过厚、过多的自定义玻璃层压住内容；视觉应遵守原生 macOS 交互。
- 设置页、书架、词典等已有稳定 SwiftUI 页面优先复用；需要 macOS 差异时抽小组件或 bridge。
- 新增图标优先用 SF Symbols 或现有图标体系；不要手绘临时图标。
- 用户可见错误应通过既有 alert、toast、状态行或明确错误状态展示；不要把原始异常文本直接渲染进主 UI。
- 所有用户可见文案要进入 `Localizable.xcstrings`；目前至少保证中文、英文。

## Reader / WKWebView / JS / CSS

Reader 是最高风险区域。修改以下内容后必须自测：

- `Features/Reader/ReaderWebView/reader.js`
- `Features/Reader/ScrollReaderWebView/scrollreader.js`
- `NativeMac/NativeReaderView.swift`
- Reader CSS、分页尺寸、安全区、顶部/底部 chrome、popup 坐标、Sasayaki highlight

验证至少覆盖：

- 竖排与横排。
- 分页与连续滚动。
- 普通窗口、缩放窗口、全屏窗口。
- 顶部导航是否遮字，底部统计/按钮是否遮字。
- 章节开头、章节末尾、长文本页、多图页、封面页。
- 查词弹窗、嵌套查词、关闭弹窗后返回阅读。
- Sasayaki 播放、暂停、跳句、高亮恢复。

Reader 视觉验证以精确构建的 `moe.shishamo.hoshi` App 和实际 EPUB 为准；轻量契约测试只能证明代码边界，不能证明排版正确。具体矩阵和数据安全规则记录在 `docs/READER_REGRESSION_TESTING.md`。不得为了验证擅自导入、替换、删除用户书籍，或自动改写 bookmark、Reader 设置、sidecar 和阅读进度；无法完成实际数据视觉验证时，必须明确说明未覆盖场景。

不要用 magic number 盲目修 Reader 遮挡。先确认是窗口 chrome、safe area、WKWebView viewport、分页尺寸、注入 CSS、JS restore/paginate 还是 EPUB 内容导致。

Mac 端不要重新启用触控板滑动翻页；之前因为 macOS 返回导航误触已取消。鼠标滚轮分页和触控板连续滚动要分别验证。

## 查词、Popup 与 CSS

- HoshiDict 是默认后端；不要随意引入实验性查词后端影响主路径速度和渲染。
- Popup 和 Dictionary 页面应该复用同一套渲染逻辑，避免“词典页正常、弹窗炸样式”。
- 自定义 CSS 应作为原生 CSS 注入，不要做自作聪明的兼容层或改写用户 CSS。
- 图片、结构化内容和 dictionary media 要按 hoshidicts / Yomitan 词典数据处理，不要用大图标兜底破坏样式。
- `WordAudioPlayer` 只负责词典词语发音和本地 audio 数据库；不要 fallback 到 Sasayaki cue 音频。
- Sasayaki 是整本有声书播放，不是词典发音来源。
- 小说模块与视频模块的 lookup surface 应复用 `PopupPresentationCoordinator`、`PopupView`、`LookupEngine` 和 `WordAudioPlayer`；禁止在 Video 下复制词典渲染、嵌套查词或本地音频实现。

## Video

- Video 是 Hoshi 的学习播放器，不是通用播放器皮肤。新增能力优先服务字幕查词、Transcript、Mining History、制卡、章节和学习循环；不要为 shader、均衡器、复杂滤镜、在线元数据或播放器外观炫技引入重依赖或厚重 chrome，除非用户明确要求。
- `PlaybackEngine` 隔离播放器状态，`MpvPlayerEngine` 是 Video 模块的 libmpv 实现；SwiftUI 和普通 UI 层不直接调用 mpv C API。
- Video 使用一个 AppKit-owned、non-restoring 的专用播放器窗口。重复打开视频应保存当前状态后替换媒体；关闭窗口必须保存状态、释放 mpv、清理 security-scoped URL，不允许后台继续播放或同时开多个播放器窗口。
- Video 页面按 macOS 26+ Liquid Glass 设计体系实现，并保持未来 macOS 27 的系统风格连续性：优先使用系统 toolbar、sidebar、标准控件和 `glassEffect`，控制栏使用克制的悬浮玻璃表面；不要制作通用播放器式的厚重自定义 chrome。
- 播放控制布局只是 UI 呈现选择。新增或打磨 `Floating`、`Compact Bottom` 等控制栏时，必须复用同一套 action/state/shortcut/popup/mining 管线；不要复制播放逻辑、另建按钮组件树或改动 playback、subtitle、lookup、mining、settings 持久化语义。布局尺寸、前景色、glass 使用和 Light 泄漏风险要用 `script/test_video_*` contract 锁住。
- 视频库和 collection 功能必须是非破坏性的虚拟组织层：不得移动、重命名、删除用户视频，不得擅自改写 subtitle sidecar 或 Finder tag；扫描、缩略图、smart rule 匹配应基于本地 catalog/row 状态，不引入网络元数据、Python/Node/ML 或大型规则库。
- 大型视频库、缩略图、字幕解析、Transcript 和 embedded subtitle extraction 不得阻塞首次播放或主线程交互。文件夹扫描、thumbnail 生成、subtitle cue store 和 transcript rows 应异步、可取消、忽略 stale result；列表 UI 只消费缓存或轻量 change token。
- Study sidebar 可以推开视频画面，但 inspector 覆盖画面边缘而不改变 mpv canvas 布局。长滚动列表行使用轻量 tint/stroke，不给每行加 `glassEffect`；Transcript 拥有自己的滚动面，不能嵌在另一个无界 `ScrollView` 里。
- Windowed ambient backdrop 只能装饰 letterbox / workspace 空间；full screen 必须保持纯黑背景。Ambient preview 必须走 playback boundary 的 video-only in-memory capture，限流、downsample、单个 in-flight、丢弃旧 generation；失败时不得暂停、重载、报播放错误或影响 `{video-screenshot}` / audio clip mining。
- Native full-screen 状态只由 `VideoWindowChromeController` 等窗口边界对象发布。不要在 full-screen will/did transition 中安装持久 `contentAspectRatio`、`setFrame`、替换 SwiftUI window identity、detach mpv render view 或做会参与 AppKit snapshot resize 的 frame/chrome mutation。
- 视频字幕文本保持透明 overlay，不添加玻璃、material、黑色或其他背景框；可读性应通过文字描边、阴影或排版处理，不恢复字幕卡片。
- Hoshi 自己解析 SRT/VTT 并渲染可交互 `SubtitleOverlayView`。不得依赖 mpv 绘制的字幕做点击查词，也不要同时显示 mpv 字幕与 Hoshi overlay。
- 视频查词弹框打开时只暂停视频；关闭整个 popup 栈后仅在此前确实播放时恢复。
- 视频制卡通过 `MiningContext.video` 和既有 AnkiConnect 流程扩展字段，禁止另建 Anki 客户端、duplicate check 或 media pipeline。
- 验证 Video 全屏时必须按原生 macOS 窗口行为处理：系统交通灯和播放器控制栏都可能因为空闲、指针位置或全屏 Space 顶栏自动收起而暂时消失。Computer Use 点击这类控件时必须先移动指针唤醒 chrome，立刻重新读取当前 UI 状态，再点击同一轮状态里的按钮；不要复用延迟后的元素 id 或旧坐标。全屏进入/退出还要覆盖底部全屏按钮、绿色交通灯、`f` 快捷键和 `Esc`，并在每次切换后等待 AppKit transition 完成再做下一步。
- 修改 Video 后按影响范围运行对应的 `script/test_video_*.swift` 或独立 contract，并完成 Light build 和 Video build。若修改共享 Reader / popup / audio 路径，还必须用精确构建的 App 和实际 EPUB 验证对应 Reader 场景；涉及 popup/audio/Anki 的 UI 行为若未手工验证，必须明确说明。

## AnkiConnect

Mac 制卡使用 AnkiConnect，不使用 iOS AnkiMobile callback。

关键文件：

- `Core/AnkiManager.swift`
- `Features/Settings/AnkiView.swift`
- `Models/Anki.swift`
- `~/Library/Application Support/anki_config.json`

规则：

- Mac 默认 AnkiConnect 地址是 `http://127.0.0.1:8765`。
- Hoshi 先启动、Anki 后启动时，应该自动重试连接并恢复状态。
- AnkiConnect 未连接时，应隐藏或禁用容易误操作的 deck/model/field 配置。
- Fetch decks/models 不应无条件清空已有字段映射；保留仍然存在的字段，删除不存在的字段。
- 修改制卡后要验证成功、重复、失败三种 toast 提示。

## 配置与持久化

重要持久化位置：

- Profile 索引：`~/Library/Application Support/Profiles/profiles.json`
- Profile 词典、Reader 外观和 Anki 制卡配置：`~/Library/Application Support/Profiles/<id>/` 下的 `dictionary_config.json`、`dictionary_settings.json`、`reader_settings.json` 和 `anki_config.json`
- `default-ja` 同步维护 `~/Library/Application Support/Dictionaries/config.json` 与 `~/Library/Application Support/anki_config.json` 的旧版只读兼容投影；不得把全局 AnkiConnect 地址、超时、重连或同步状态错误地拆进 Profile
- 物理词典文件：`~/Library/Application Support/Dictionaries/`，由所有 Profile 共享；新词典只在当前 Profile 启用，删除词典必须清理所有 Profile 的文件引用
- 大量 UI / reader / audio / shortcut 设置：`UserDefaults`，入口在 `Core/UserConfig.swift`
- Google token：`Features/Sync/TokenStorage.swift`，优先 Keychain，带 fallback
- 书籍和 sidecar 数据：通过 `Core/BookStorage.swift`

不要在 fetch、App 验证或 profile 变更时随意删除用户配置。涉及 bundle id、container、profile、sidecar、书籍目录或持久化路径时，必须先评估用户数据风险。
Profile 切换必须通过显式 `ProfileContext` 解析；Reader、Popup、嵌套查词和 Anki 制卡要携带解析后的 `profileID`，不得依赖其他窗口最后切换的隐式全局状态。词典备份使用 `.hoshi-profiles` 元数据并在临时目录校验后合并，恢复时不得覆盖 Profile 的 Reader 或 Anki 配置。

## Sasayaki、本地音频与输入控制

- Sasayaki 相关：`Features/Sasayaki/`、`Models/Sasayaki.swift`、Reader WebView 中的 cue highlight。
- 本地单词音频相关：`Core/LocalFileServer.swift`、`Features/Popup/WordAudioPlayer.swift`、`Core/UserConfig.swift` 的 audio sources。
- 键盘快捷键：`Core/Shortcuts/`、`Features/Settings/KeyboardShortcutsView.swift` 和各 feature 的 `*ShortcutActions.swift`。
- 快捷键配置统一由 `Core/Shortcuts/`、`ShortcutRegistry`、`ShortcutManager` 和 `UserConfig.ShortcutConfiguration` 管理。Reader、Dictionary/Popup、Sasayaki、Video 只能声明 action 并注册当前上下文 handler，不得再添加独立存储、隐藏 `.keyboardShortcut` 按钮或 feature 私有 `NSEvent` monitor。
- 快捷键冲突必须按 `ShortcutScope` 判断；互斥的 Reader/Video scope 可以复用按键，Popup scope 必须优先于底层 Reader/Dictionary/Video。快捷键录制、文本输入和 IME 组合期间不得拦截输入。
- `Settings > Advanced > Keyboard Shortcuts` 是唯一快捷键编辑入口。Video Settings 只能跳转到统一页面的 Video 分组，不得维护第二套快捷键页面。
- 通用手柄控制（Xbox / PlayStation / Switch）：`Core/XboxControllerManager.swift`、`Features/Settings/XboxControllerView.swift`。

修改 Sasayaki 后要检查：

- 播放/暂停、上一句、下一句。
- 查词自动暂停后返回是否恢复高亮。
- 切到其他软件一段时间再回来，高亮和跳转是否仍一致。
- 本地音频导入不应影响词典发音路径。

## Google Drive 同步

关键文件：

- `Features/Sync/GoogleDriveAuth.swift`
- `Features/Sync/GoogleDriveHandler.swift`
- `Features/Sync/SyncManager.swift`
- `Features/Settings/SyncView.swift`

规则：

- Google Drive 同步必须保护用户阅读进度和 sidecar 数据。
- `ASWebAuthenticationSession` 回调必须回到正确 actor/主线程，避免登录成功后崩溃。
- 回调成功后 UI 状态要刷新，不要停留在 `Not connected`。
- 跨天但数字进度未变化也可能是有效同步场景；不要只用百分比判断是否上传/下载。
- 修改 OAuth 或 token storage 时，验证登录、刷新 token、退出登录和重启后状态。

## 测试与提交

- 声明完成前，按影响范围跑验证。只改文档可不跑完整 App，但要说明。
- 修改可运行 App 代码后，完成对应验证并在回复前使用启动脚本打开受影响模块/发布包；小说或共享基础代码默认启动 Light，Video UI/播放/字幕改动启动 Video。只有纯文档、纯 CI 或用户明确要求不启动时可以跳过。
- 低风险非 Reader 改动至少跑对应构建或脚本语法检查。
- Reader / Popup / Dictionary / Sync / Anki / Sasayaki 改动要补充对应手工验证或明确未验证项。
- 不要声明没有验证过的 UI 已经可用。
- Commit message 必须使用 Conventional Commits，格式为 `<type>(<scope>): <description>` 或 `<type>: <description>`，例如 `feat(reader): add mouse wheel page turn`、`fix(sync): refresh auth state after callback`、`docs(macos): update agent rules`。
- 禁止使用 `update files`、`fix stuff`、`changes` 等无法表达意图的提交信息。一个 commit 混合多个独立主题时应先拆分；同一实现对应的测试和真源文档应随实现一起提交。
- Changelog 只记录普通用户可感知的 App 变化；不要记录 CI、agent workflow、构建脚本、依赖管理或内部重构。

常用验证入口：

```bash
./script/build_and_run_native.sh --verify
./script/build_and_run_native.sh --open-url 'hoshi://search?text=星'
./script/verify_native_release_contract.sh
./script/verify_video_variant_contract.sh
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
swift script/test_color_hex_codec.swift
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_css_editor_snippets.swift
```

## 工作方式

- 开始前读本文件和 `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`，并查看 `git status --short --branch`。
- 优先用 `rg` 搜索。
- 手动编辑文件使用 `apply_patch`。
- 不要用 `git reset --hard`、`git checkout --` 回滚用户改动，除非用户明确要求。
- 修改 Xcode synchronized root group 下的新文件时，确认是否需要更新 `project.pbxproj` 的 membership exceptions。
- 涉及 Apple/macOS 平台能力、AppKit、SwiftUI、WKWebView、ASWebAuthenticationSession、签名、notarization 或 sandbox 权限时，优先参考 Apple 官方文档或本仓库已有实现，不靠记忆猜 API。
- 回答用户时说明做了什么、验证了什么、没法验证什么。
