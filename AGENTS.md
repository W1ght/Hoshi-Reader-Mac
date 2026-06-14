# Hoshi Reader Mac Agent 指南

Hoshi Reader Mac 是 Hoshi Reader 的原生 macOS 桌面端项目。`v0.5.0` 等既有 GitHub 版本是 Mac Catalyst 历史产物；当前仓库只有一个原生 `Hoshi Reader` App target，保留阅读、查词、同步、制卡、本地音频、Sasayaki、快捷键和 DMG 发布体验。

本文件是所有 agent 进入仓库后的常驻规则。任务状态、执行日志、长调查过程不要写进这里。

## 工作原则

- **Mac 用户可见行为是第一真源。** 不要为了机械同步 iOS、Android 或上游实现而破坏 Mac 端已经修好的交互、排版、快捷键、同步或发布流程。
- **原生 macOS 是唯一开发和发布目标。** 新功能、修复、重构和验证只保证 `Hoshi Reader` 原生 App；不得重新引入 UIKit、Mac Catalyst target、Catalyst bridge 或 Catalyst 构建路径。
- **Catalyst 只保留历史语义。** 可以从 Git 历史和历史文档确认旧用户行为或数据格式，但不得把 Catalyst 恢复为兼容目标、构建门槛、回归基线或发布候选。
- **不要用整屏重写代替迁移。** 优先复用现有表现良好的 SwiftUI 页面和业务服务；平台差异只在窄边界里用 AppKit / NSViewRepresentable / NSWindow 能力补齐。
- **删除 Catalyst 不等于删除用户数据兼容。** 书籍目录、bookmark、sidecar、词典配置、Anki 配置、Google token 和 UserDefaults 的升级兼容仍是硬约束；App 启动路径不得清理旧 token 或用“首次启动清理”代替显式退出登录。
- **修 bug 不叠补丁。** 先复现、定位边界，再改最小稳定方案；Reader / WKWebView / Popup / AnkiConnect / Google Drive / Sasayaki 尤其要避免猜测式修改。
- **不回滚用户或其他 agent 的未说明改动。** 工作树可能包含未提交迁移内容；只处理当前任务范围。
- **不擅自发版、打 tag、push 或提交。** 用户明确要求 release / commit / push 后再执行。Commit message 必须使用 Conventional Commits，例如 `feat(reader): add mouse wheel page turn`。
- 新增用户可见设置、按钮、提示、toast、alert、页面标题或 release 可见文案时，必须考虑 `Localizable.xcstrings`，至少保证中文和英文不会裸露错误文案。

## 架构基线

### 当前产品线

- `Hoshi Reader`：唯一的原生 macOS App target，bundle id 为 `de.manhhao.hoshi`，App 入口位于 `NativeMac/`。
- `main`：当前发布分支。Release tag 从 `main` 打。
- `codex/` 分支：较大功能、native 迁移、跨模块重构或高风险修复优先使用。

### Native 迁移方向

- SwiftUI 页面能复用就复用；不要为了“原生”重写成熟 UI。
- 不新增 iOS 平台条件或双平台抽象；macOS 必要能力直接使用窄范围 AppKit bridge。
- AppKit 只用于 macOS 必要能力，例如 `NSWindow`、`NSViewRepresentable`、`NSEvent`、菜单、panel、focus/key capture、文件选择、窗口 chrome。
- `NativeMac/` 可以承载 native shell 和验证探针，但共享业务逻辑应留在 `Core/`、`Features/`、`Models/` 等已有边界。
- 共享代码修改以原生构建和对应功能验证为准。

### 项目结构

- `NativeMac/`：原生 macOS App 入口、sidebar/detail、Reader 和 AppKit 能力；当前产品主路径。
- `Core/`：核心服务与持久化，如 Anki、词典、配置、本地文件服务、查词引擎、桌面输入管理。
- `Features/Bookshelf/`：书架、导入、排序、同步入口。
- `Features/Reader/`：阅读器、Reader WebView、分页/连续阅读、统计、Sasayaki 高亮。
- `Features/Popup/`：查词弹窗、渲染 CSS/JS、单词音频、制卡入口。
- `Features/Dictionary/`：词典搜索页。
- `Features/Settings/`：设置页、外观、Anki、音频、Sasayaki、快捷键、CSS 等。
- `Features/Sync/`：Google Drive OAuth、token、同步逻辑。
- `Models/`：数据模型。
- `Util/`：工具与更新检查。
- `script/`：本地构建、验证、打包、发版脚本。
- `.github/workflows/release-mac.yml`：tag 触发 DMG 构建和 GitHub Release。

## 真源文档

- `docs/TODO.md`：短状态、下一步、阻塞项、验证入口。
- `docs/MAC_NATIVE_MIGRATION_INVENTORY.md`：UIKit/Catalyst/AppKit 迁移清单和风险分层。
- `docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md`：UIKit 到 AppKit 的迁移路线。
- `docs/ARCHITECTURE_REFACTORING.md`：长期架构方向，不记录执行流水账。
- `docs/READER_REGRESSION_TESTING.md`：Reader 回归验证、fixture、截图计划。
- `docs/CHANGELOG.md`：只记录用户可见变化。
- `docs/UPSTREAM_SYNC_QUEUE.md`：上游同步队列。
- `docs/AGENT_DEVELOPMENT_GUIDE.md`、`docs/hoshi_reader_mac_agent_development_guide.md`：agent 开发规范和历史沉淀。
- `docs/mac-catalyst-interactions.md`：已退役 Catalyst 路径的历史说明，不是当前实现指南。
- `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`：本仓库任务前置工作流。

只有任务改变了对应文档的真源内容时，才更新该文档。不要把一次性调查日志、长命令输出或截图观察塞进 README 或 AGENTS。

- 任务改变 native 迁移阶段、已完成能力、剩余风险、下一步、阻塞项、验证入口或发布切换条件时，必须在同一任务内更新最小相关真源文档。
- 实现使 `docs/TODO.md`、`docs/MAC_NATIVE_MIGRATION_INVENTORY.md`、`docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md` 或 `docs/READER_REGRESSION_TESTING.md` 的现状描述失真时，不得只改代码；声明完成前必须同步文档。
- 迁移实现和由它引起的真源文档更新默认放在同一个 commit，除非用户明确要求拆分。不要单独制造没有状态变化的文档流水账 commit。

## 经验沉淀

- 如果 agent 犯错后定位到未来可能复发的问题，应把最小可执行规则沉淀到对应真源文档。
- 需要所有会话常驻的仓库级规则才写入 `AGENTS.md`。
- 验证矩阵和脚本入口写入 `docs/READER_REGRESSION_TESTING.md` 或 `docs/TODO.md`。
- 当前架构事实和长期迁移方向写入 `docs/MAC_NATIVE_MIGRATION_INVENTORY.md`、`docs/UIKit_TO_APPKIT_MIGRATION_PLAN.md` 或 `docs/ARCHITECTURE_REFACTORING.md`。
- 沉淀内容必须具体、可执行、低歧义；先查是否已有等价规则，有则更新原规则。

## 构建与启动

默认构建和验证原生 macOS App：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

`script/build_and_run_native.sh` 是同一原生 target 的显式入口。普通签名构建可能因为本机缺少 `Mac Development` 证书失败；除非任务是签名/发布，不要把证书错误当作代码回归。

## Release 流程

- 版本号来自 `Hoshi Reader.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION`。
- GitHub Actions 通过 `v*.*.*` tag 构建原生 App、移除包括 ad-hoc 在内的所有代码签名、不做 notarization，并发布 `Hoshi-Reader-Mac-<version>.dmg` 和 `.sha256`。
- 发布前确认工作树干净、当前分支是 `main`、版本号正确、tag 不存在。
- 发布日志写用户可见改动，优先中文；不要把内部迁移、CI、agent workflow 写成用户功能。
- `script/release_mac.sh` 会改版本、创建 Conventional Commit、推送分支和 tag；仅在用户明确批准 release 后运行。
- 不要上传不需要的 source zip 或 app zip；Release 产物以 DMG 和 checksum 为主。

## 上游同步

上游远端：

```bash
git fetch upstream
git log --oneline main..upstream/develop
```

迁移上游功能时：

- 先读 diff，确认是否涉及设置页、Reader WebView、popup 渲染、词典导入、图片显示、Sasayaki 或同步。
- 上游 iOS 行为是参考，不是无条件覆盖；Mac 端已修复的窗口缩放、安全区、全屏导航、触摸板禁用、鼠标滚轮、AnkiConnect、本地音频路径不能被回退。
- 对设置页功能要检查本仓库是否已有 Mac/native 替代实现，避免重复入口。
- 对 Reader / Popup / Dictionary 的 JS、CSS、WebView 改动要特别小心；旧 Catalyst 行为只能用于定位历史意图，最终判断以 native macOS 的 WKWebView 表现为准。

## 用户可见 UI

- Mac UI 应优先遵守 macOS 桌面交互：窗口、sidebar、toolbar、keyboard shortcut、menu、focus、hover、context menu、scroll wheel、file picker。
- macOS 26 / Liquid Glass 风格可以采用系统组件和材质，但不要用过厚、过多的自定义玻璃层压住内容；视觉应遵守原生 macOS 交互，不要求逐像素复刻 Catalyst。
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

Reader 回归验证要逐步工程化，不要只靠人工提醒。当前验证设计与 fixture 计划记录在 `docs/READER_REGRESSION_TESTING.md`；测试 EPUB 由 `script/generate_reader_fixtures.py` 生成，截图运行目录由 `script/capture_reader_regression.sh` 初始化。无法完成截图或手工视觉验证时，必须明确说明未覆盖场景。

不要用 magic number 盲目修 Reader 遮挡。先确认是窗口 chrome、safe area、WKWebView viewport、分页尺寸、注入 CSS、JS restore/paginate 还是 EPUB 内容导致。

Mac 端不要重新启用触控板滑动翻页；之前因为 macOS 返回导航误触已取消。鼠标滚轮分页和触控板连续滚动要分别验证。

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

不要在迁移、fetch、native 验证或 profile 变更时随意删除用户配置。涉及 bundle id、container、profile、sidecar、书籍目录或持久化路径时，必须先评估旧版本升级风险。

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

- Google Drive 同步必须保护用户阅读进度和 sidecar 数据。
- `ASWebAuthenticationSession` 回调必须回到正确 actor/主线程，避免登录成功后崩溃。
- 回调成功后 UI 状态要刷新，不要停留在 `Not connected`。
- 跨天但数字进度未变化也可能是有效同步场景；不要只用百分比判断是否上传/下载。
- 修改 OAuth 或 token storage 时，验证登录、刷新 token、退出登录和重启后状态。

## 测试与提交

- 声明完成前，按影响范围跑验证。只改文档可不跑完整 App，但要说明。
- 低风险非 Reader 改动至少跑对应构建或脚本语法检查。
- Reader / Popup / Dictionary / Sync / Anki / Sasayaki 改动要补充对应手工验证或明确未验证项。
- 不要声明没有验证过的 UI 已经可用。
- Commit message 必须使用 Conventional Commits，格式为 `<type>(<scope>): <description>` 或 `<type>: <description>`，例如 `feat(reader): add mouse wheel page turn`、`fix(sync): refresh auth state after callback`、`docs(macos): align native migration plan`。
- 禁止使用 `update files`、`fix stuff`、`changes` 等无法表达意图的提交信息。一个 commit 混合多个独立主题时应先拆分；同一实现对应的测试和真源文档应随实现一起提交。
- Changelog 只记录普通用户可感知的 App 变化；不要记录 CI、agent workflow、构建脚本、依赖管理或内部重构。

常用验证入口：

```bash
./script/build_and_run_native.sh --verify
./script/build_and_run_native.sh --open-url 'hoshi://search?text=星'
./script/verify_native_upgrade_contract.sh
./script/audit_native_upgrade_data.sh
./script/verify_reader_ci_contract.sh
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
python3 -m py_compile script/generate_reader_fixtures.py
bash -n script/capture_reader_regression.sh
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
