# Hoshi Reader Mac Agent Instructions

本仓库是 Hoshi Reader 的独立 Mac Catalyst 版本，目标是保留原 Hoshi Reader 的阅读、查词、同步、制卡体验，同时把桌面端交互、AnkiConnect、本地音频、Sasayaki、快捷键和 DMG 发布流程做成稳定的 macOS App。

## 核心规则

- 本仓库以 **Mac 用户可见行为** 为第一真源；不要为了机械同步 iOS/上游实现而破坏 Mac 端已经修好的交互、排版或发布流程。
- 上游功能来源是 `upstream/develop`。迁移上游改动时先理解用户可见行为，再适配到 Mac Catalyst，不要直接覆盖本仓库的 Mac 专用文件。
- `main` 是当前发布分支，release tag 从 `main` 打。除非用户明确要求，不要再把发布改回旧的开发分支流程。
- 修 bug 时不要一层层堆补丁。先复现、定位边界，再改最小稳定方案；尤其是 Reader 排版、WKWebView 渲染、AnkiConnect 和 Google Drive 回调。
- 不要为了发版擅自发布。用户说“可以发版”后再打 tag / push / release。
- 不要回滚或重置用户未说明的本地改动；工作树可能包含用户或前一轮 agent 的未提交内容。
- Commit message 必须使用 Conventional Commits，例如 `feat(reader): add mouse wheel page turn`、`fix(sync): preserve reading progress`、`chore(release): 0.5.0`；发版 tag 说明可以使用中文发布日志。
- 新增用户可见设置、按钮、提示或页面时，同步考虑 `Localizable.xcstrings`。至少保证中文、英文入口不会裸露明显错误文案。

## 仓库结构

- `App/`：SwiftUI App 入口。
- `Core/`：核心服务与持久化，如 Anki、词典、配置、本地文件服务、查词引擎、桌面输入管理。
- `Features/Bookshelf/`：书架、导入、排序、同步入口。
- `Features/Reader/`：阅读器、Reader WebView、分页/连续阅读、统计、Sasayaki 高亮。
- `Features/Popup/`：查词弹窗、渲染 CSS/JS、单词音频、制卡入口。
- `Features/Dictionary/`：词典搜索页。
- `Features/Settings/`：设置页、外观、Anki、音频、Sasayaki、快捷键、CSS 等。
- `Features/Sync/`：Google Drive OAuth、token、同步逻辑。
- `Models/`：数据模型。
- `Util/`：工具与更新检查。
- `script/`：本地构建、打包、发版脚本。
- `.github/workflows/release-mac.yml`：tag 触发 DMG 构建和 GitHub Release。
- `docs/mac-catalyst-interactions.md`：Mac 交互设计与验证说明。

## 构建与启动

本地启动 shipping Mac Catalyst App 优先使用项目脚本：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run_catalyst.sh --verify
```

native macOS 迁移壳使用独立脚本，避免和当前发布用 Catalyst App 混淆：

```bash
./script/build_and_run_native.sh
./script/build_and_run_native.sh --verify
```

无签名 Mac Catalyst 编译验证：

```bash
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

如果使用 `platform=macOS,variant=Mac Catalyst` 构建，可能出现 CoreSimulator 版本警告；只要 Mac Catalyst 编译继续进行，通常不是本仓库代码问题。

普通签名构建可能因为本机缺少 `Mac Development` 证书或 ShareExtension profile 失败。除非任务是签名/发布，不要把这类证书错误当作代码回归。

## Release 流程

- 版本号来自 `Hoshi Reader.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`。
- GitHub Actions 通过 `v*.*.*` tag 构建 DMG，并发布 `Hoshi-Reader-Mac-<version>.dmg` 和 `.sha256`。
- 发布前确认工作树干净、当前分支是 `main`、版本号正确、tag 不存在。
- 发布日志要写用户可见改动，优先中文；可以参考 0.1.5 之后的中英双语风格，但用户明确要求中文时只写中文。
- `script/release_mac.sh` 会改版本、提交、推送并打 tag。使用前确认它的目标分支符合当前策略；当前发布策略应是从 `main` 发布。
- 不要上传不需要的 source zip 或 app zip；Release 产物以 DMG 和 checksum 为主。

## 上游同步

上游远端：

```bash
git fetch upstream
git log --oneline main..upstream/develop
```

迁移上游功能时：

- 先读 diff，确认是否涉及设置页、Reader WebView、popup 渲染、词典导入、图片显示、Sasayaki 或同步。
- 对设置页功能要检查本仓库是否已有 Mac 替代实现，避免重复入口。
- 对 Reader / Popup / Dictionary 的 JS、CSS、WebView 改动要特别小心，Mac Catalyst 的 WKWebView 行为可能不同。
- 上游 iOS 行为是参考，不是无条件覆盖；Mac 端已修复的窗口缩放、安全区、全屏导航、触摸板禁用等行为不能被回退。

## Reader 与 Mac Catalyst 排版

Reader 是最容易回归的区域。修改以下内容后必须自测：

- `Features/Reader/ReaderView/ReaderView.swift`
- `Features/Reader/ReaderWebView/ReaderWebView.swift`
- `Features/Reader/ReaderWebView/reader.js`
- `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`
- `Features/Reader/ScrollReaderWebView/scrollreader.js`
- Reader CSS、分页尺寸、安全区、顶部/底部 chrome

验证至少覆盖：

- 竖排与横排。
- 普通窗口、缩放窗口、全屏窗口。
- 顶部导航是否遮字，底部统计/按钮是否遮字。
- 章节开头、章节末尾、长文本页、多图页、封面页。
- 弹窗查词后返回阅读，Sasayaki 高亮是否恢复。

Reader 回归验证要逐步工程化，不要只靠人工提醒。当前验证设计与 fixture 计划记录在 `docs/READER_REGRESSION_TESTING.md`；测试 EPUB 由 `script/generate_reader_fixtures.py` 生成，截图运行目录由 `script/capture_reader_regression.sh` 初始化。修改 Reader / WKWebView / JS / CSS 时，如果无法完成截图或手工视觉验证，必须明确说明未验证的场景。

不要用 magic number 盲目修 Reader 遮挡。先确认是窗口 chrome、safe area、WKWebView viewport、分页尺寸、注入 CSS、JS restore/paginate 还是 EPUB 内容导致，再改最小稳定方案。

Mac 端不要重新启用触控板滑动翻页；之前因为 macOS 返回导航误触已取消。

## 查词、Popup 与 CSS

- HoshiDict 是默认后端；不要随意引入实验性查词后端影响主路径速度和渲染。
- Popup 和 Dictionary 页面应该复用同一套渲染逻辑，避免“词典页正常、弹窗炸样式”。
- 自定义 CSS 应作为原生 CSS 注入，不要做自作聪明的兼容层或改写用户 CSS。
- 图片、结构化内容和 dictionary media 要按 hoshidicts / Yomitan 词典数据处理，不要用大图标兜底破坏样式。
- `WordAudioPlayer` 只负责词典词语发音和本地 audio 数据库；不要 fallback 到 Sasayaki cue 音频。
- Sasayaki 是整本有声书播放，不是词典发音来源。

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

- 词典启用和排序：`~/Library/Application Support/Dictionaries/config.json`
- Anki 主配置：`~/Library/Application Support/anki_config.json`
- 大量 UI / reader / audio / shortcut 设置：`UserDefaults`，入口在 `Core/UserConfig.swift`
- Google token：`Features/Sync/TokenStorage.swift`，优先 Keychain，带 fallback
- 书籍和 sidecar 数据：通过 `Core/BookStorage.swift`

不要在迁移或 fetch 时随意删除用户配置。涉及 profile、迁移、重命名 bundle id 或改持久化路径时，必须先评估旧版本升级风险。

## Sasayaki、本地音频与输入控制

- Sasayaki 相关：`Features/Sasayaki/`、`Models/Sasayaki.swift`、Reader WebView 中的 cue highlight。
- 本地单词音频相关：`Core/LocalFileServer.swift`、`Features/Popup/WordAudioPlayer.swift`、`Core/UserConfig.swift` 的 audio sources。
- 键盘快捷键：`Features/Settings/KeyboardShortcutsView.swift`、Reader 的隐藏 shortcut buttons。
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

- `ASWebAuthenticationSession` 回调必须回到正确 actor/主线程，避免登录成功后崩溃。
- 回调成功后 UI 状态要刷新，不要停留在 `Not connected`。
- 修改 OAuth 或 token storage 时，验证登录、刷新 token、退出登录和重启后状态。

## i18n

- 文案集中在 `Localizable.xcstrings`。
- 新增设置页、按钮、toast、alert、release 可见文案时要考虑中英和已有 14 语言。
- 如果无法一次补齐所有语言，至少不要破坏现有 key；新增 key 应能被 Xcode extraction 识别，后续再补翻译。

## 手工验证主路径

完成用户可见功能或 bugfix 前，至少按影响范围跑：

```bash
./script/build_and_run.sh --verify
```

主路径：

1. 打开书架。
2. 进入一本书。
3. 翻页或滚动。
4. 查词弹窗。
5. 弹窗内嵌套查词。
6. 播放词典音频或本地单词音频。
7. 如涉及 Sasayaki，播放/暂停/跳句并确认高亮。
8. 如涉及 Anki，测试连接、字段映射和制卡 toast。

无法硬件验证时要明确说明，例如没有对应手柄只能完成编译和事件链路验证。

## 工作方式

- 优先用 `rg` 搜索。
- 手动编辑文件使用 `apply_patch`。
- 不要用 `git reset --hard`、`git checkout --` 回滚用户改动，除非用户明确要求。
- 修改 Xcode synchronized root group 下的新文件时，确认是否需要更新 `project.pbxproj` 的 membership exceptions。
- 不要把调查日志、长命令输出或截图观察写进 README；需要长期保留的设计说明放 `docs/`。
- 回答用户时说明做了什么、验证了什么、没法验证什么。不要声称没验证过的 UI 已经可用。
