# Hoshi Reader Mac Agent Development Guide

> 历史文档：本文记录已退役的 Mac Catalyst 阶段，包含的 Catalyst 构建命令和平台判断不得用于当前开发或验证。当前规则以仓库根目录 `AGENTS.md`、`docs/AGENT_DEVELOPMENT_GUIDE.md` 和 `.codex/skills/hoshi-reader-mac-workflow/SKILL.md` 为准；当前唯一 App 是 bundle id `moe.shishamo.hoshi` 的原生 macOS target。

> 建议保存为：`docs/AGENT_DEVELOPMENT_GUIDE.md`  
> 目的：让 Codex / Claude Code / 其他 agent 在 Hoshi Reader Mac 仓库里接力开发时，优先遵守项目边界、验证矩阵和用户可见行为，避免重复踩坑、盲目同步上游或补丁式修复。

---

## 1. 项目定位

Hoshi Reader Mac 是 Hoshi Reader 的独立 Mac Catalyst 版本，目标不是简单复刻 iOS，也不是普通 EPUB reader，而是一个面向日语沉浸学习用户的桌面阅读工具。

核心链路：

```text
导入 EPUB
→ 阅读
→ 查词
→ 播放词典/本地音频
→ 制作 Anki 卡片
→ 同步阅读进度/统计/Sasayaki 数据
```

Agent 在本仓库工作时，必须优先保护这条主路径。

---

## 2. 行为真源

### 2.1 Mac 用户可见行为优先

本仓库的第一真源是 **Mac 用户可见行为**。

也就是说：

- Mac 端已经修好的 Reader 排版、窗口缩放、顶部/底部遮挡、全屏行为，不得因为同步 iOS 上游而回退。
- Mac 端已经适配好的 AnkiConnect、本地音频、快捷键、窗口交互，不得被 iOS/iPad 逻辑覆盖。
- Mac Catalyst 的 WKWebView 行为和 iOS WebKit 不完全一致，不能机械搬运 iOS 代码。

### 2.2 iOS 上游只作为功能参考

iOS 上游仍然重要，但它是：

```text
用户可见行为参考
```

不是：

```text
可以直接覆盖 Mac 文件的实现真源
```

同步上游时，必须先判断：

1. iOS 改动的用户可见行为是什么？
2. Mac 当前是否已有等价或更适合桌面的实现？
3. 是否会回退 Mac 专用修复？
4. 是否需要以 Mac Catalyst 方式重新适配？

---

## 3. Agent 工作纪律

每个任务开始前，先判断影响区域：

- Reader / WKWebView / JS / CSS
- Popup / Dictionary rendering
- Dictionary import / update
- AnkiConnect / mining
- Local audio / LocalFileServer
- Sasayaki
- Google Drive Sync
- Settings / localization
- Release / DMG / signing
- Build scripts / CI

修改前必须做到：

1. 找到对应关键文件。
2. 总结当前状态流或用户交互。
3. 判断问题根因。
4. 再做最小稳定修改。

禁止在根因不清楚时反复堆补丁。

---

## 4. 禁止行为

### 4.1 禁止盲目同步上游

不要直接用 iOS 上游文件覆盖 Mac 端文件，尤其是：

- Reader SwiftUI layout
- Reader WebView bridge
- `reader.js`
- `scrollreader.js`
- Popup CSS / JS
- Anki 相关逻辑
- Mac 专用快捷键和窗口逻辑

### 4.2 禁止清用户数据来掩盖 bug

不要通过删除以下内容来“修复”问题：

```text
~/Library/Application Support/
Books/
Dictionaries/
anki_config.json
anki_words.json
UserDefaults
Google token
```

除非用户明确要求测试迁移、空库、重装或清理数据。

### 4.3 禁止补丁式 Reader 修复

Reader 问题不要直接塞 magic number，例如：

```swift
.padding(.top, 24)
```

除非同时说明：

- 适用的窗口状态
- 横排/竖排影响
- paginated/continuous 影响
- 是否影响全屏
- 是否影响弹窗查词
- 验证结果

### 4.4 禁止混淆音频来源

- Word audio / local audio 是词典发音。
- Sasayaki 是整本有声书播放。
- 不要让词典发音 fallback 到 Sasayaki cue。
- 不要让 Sasayaki 替代 dictionary audio。

### 4.5 禁止自动发布

Agent 不得自动：

- bump version
- create tag
- push release tag
- upload GitHub Release
- 修改 release notes 并发布

除非用户明确说：

```text
可以发版
```

或给出等价明确指令。

### 4.6 禁止裸露未本地化文案

新增用户可见按钮、toast、alert、设置项时，必须考虑：

- `Localizable.xcstrings`
- 英文
- 中文
- 已有 key 是否可以复用

---

## 5. 推荐仓库文档结构

建议新增或维护以下文件：

```text
AGENTS.md
docs/TODO.md
docs/CHANGELOG.md
docs/ARCHITECTURE_REFACTORING.md
docs/UPSTREAM_SYNC_QUEUE.md
docs/AGENT_DEVELOPMENT_GUIDE.md
```

### 5.1 `AGENTS.md`

面向所有 agent 的入口规则。

应该包含：

- 项目定位
- 真源规则
- 构建命令
- release 流程
- Reader 验证矩阵
- AnkiConnect 规则
- Sync 规则
- 禁止行为

### 5.2 `docs/TODO.md`

短交接文档，只记录当前状态。

规则：

- 保持短小，建议 150 行以内。
- 只记录当前状态、下一步、阻塞项、长期有效验证入口。
- 不粘贴长日志。
- 不写流水账。
- 不写 release notes。
- 完成任务后，在同一个 commit 中更新最小相关行。

推荐结构：

```md
# Hoshi Reader Mac Agent TODO

Last updated: YYYY-MM-DD

## Maintenance Rules

- Keep this file short.
- Record only current state, next actionable work, blockers, and durable validation requirements.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long investigations in issues, PRs, commit messages, or focused docs.

## Current Focus

### Reader / WebView

- Current state:
- Next action:
- Blockers:
- Required validation:

### AnkiConnect

- Current state:
- Next action:
- Blockers:
- Required validation:

### Local Audio / Sasayaki

- Current state:
- Next action:
- Blockers:
- Required validation:

### Release

- Current state:
- Next action:
- Blockers:
- Required validation:

## Required Validation

```bash
./script/build_and_run.sh --verify
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```
```

### 5.3 `docs/CHANGELOG.md`

只记录用户可见变化。

不要写：

- 内部重构
- agent workflow
- CI 微调
- 代码风格调整
- 未发布功能的补丁流水账

应该写：

- Reader 不再遮字
- AnkiConnect 自动重连更稳定
- 词典导入失败提示更清晰
- Sasayaki 高亮恢复更准确
- Google Drive 同步冲突提示更明确

建议格式：

```md
# Changelog

All notable user-visible changes to Hoshi Reader Mac are documented here.

## [Unreleased]

### Added

### Changed

### Fixed
```

### 5.4 `docs/ARCHITECTURE_REFACTORING.md`

长期技术债方向，不写每次任务记录。

建议方向：

1. 拆分 AnkiConnect client 和 mining service。
2. 拆分 Dictionary store / Lookup service。
3. LocalFileServer 安全化。
4. Reader WebView bridge / Reader session state 拆分。
5. Google Drive sync 加同步预览、冲突保护、同步历史。
6. Release signing / notarization / Sparkle 自动更新。
7. Reader actual-EPUB visual validation protocol。
8. 性能基准：冷启动、导入 EPUB、打开 Reader、查词、制卡。

### 5.5 `docs/UPSTREAM_SYNC_QUEUE.md`

用于记录 iOS 上游同步队列。

每个切片应该包含：

```md
## Slice N: Title

Source commits:
- xxx

iOS behavior:
- ...

Mac current behavior:
- ...

Mac adaptation:
- ...

Do not regress:
- ...

Validation:
- ...
```

---

## 6. Reader / WKWebView 修改规则

Reader 是最容易回归的区域。

修改以下文件前必须特别小心：

```text
Features/Reader/ReaderView/ReaderView.swift
Features/Reader/ReaderWebView/ReaderWebView.swift
Features/Reader/ReaderWebView/reader.js
Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift
Features/Reader/ScrollReaderWebView/scrollreader.js
Reader CSS
Popup CSS / JS
```

### 6.1 Reader 必测矩阵

修改 Reader 后至少验证：

- 横排
- 竖排
- paginated mode
- continuous mode
- 普通窗口
- 缩放窗口
- 全屏窗口
- 章节开头
- 章节末尾
- 长文本页
- 多图页
- 封面页
- 查词弹窗打开和关闭
- 弹窗内递归查词
- Sasayaki 高亮恢复
- 顶部导航是否遮字
- 底部控件是否遮字
- focus mode 是否异常触发

### 6.2 Reader 修复顺序

优先判断问题属于哪一层：

```text
SwiftUI layout
→ Mac Catalyst safe area/window
→ WKWebView sizing
→ CSS pagination/continuous layout
→ JS scroll/page state
→ Popup selection/coordinates
→ Bookmark restore
```

不要一开始就改 CSS 或硬塞 padding。

---

## 7. AnkiConnect 修改规则

Mac 制卡主路径是 AnkiConnect。

默认地址：

```text
http://127.0.0.1:8765
```

修改 Anki 逻辑时必须验证：

1. Anki 未启动时提示是否清晰。
2. Anki 后启动时是否自动重连。
3. Fetch deck/model 是否保留已有字段映射。
4. Add note 成功。
5. Duplicate check。
6. Add note 失败。
7. Audio field。
8. Sasayaki audio field。
9. Dictionary media。
10. Force sync。

建议逐步拆分：

```text
AnkiConnectClient
AnkiTemplateRenderer
AnkiMiningService
AnkiDuplicateChecker
AnkiMediaStore
```

---

## 8. LocalFileServer / Local Audio 修改规则

LocalFileServer 负责：

- card cover
- Sasayaki temporary audio
- local word audio
- dictionary audio compatibility

建议改进方向：

1. 移除 `try!`。
2. 只绑定 loopback。
3. 临时媒体 URL 加 token。
4. SQLite 查询封装到 actor 或只读连接管理。
5. 错误日志可诊断但不泄露隐私。
6. 不让局域网访问本地媒体。

修改后验证：

- 词典音频播放
- local audio 数据库查询
- Sasayaki audio 添加到 Anki
- cover 添加到 Anki
- 清理临时媒体后 URL 不再可访问
- 端口被占用时不 crash

---

## 9. Dictionary 修改规则

词典导入/更新属于高风险 IO 任务。

修改时要注意：

- 大词典内存占用
- 导入失败回滚
- 更新时保留启用状态和排序
- dictionary title 改变时迁移 Anki single glossary handlebar
- term/frequency/pitch 类型不能混淆
- dictionary media 不能破坏渲染

建议：

1. 导入任务可取消。
2. 更新使用 staging + backup + atomic swap。
3. 失败信息分层：下载失败、解析失败、导入失败、磁盘不足、权限问题。
4. 设置页显示词典健康状态：条数、类型、更新时间、是否 updatable。

---

## 10. Sync 修改规则

Google Drive 同步必须让用户信任。

修改同步逻辑时，优先保护：

- 不丢进度
- 不误覆盖
- 可解释
- 可恢复

建议能力：

1. 同步前预览。
2. 冲突保护。
3. 同步历史。
4. 最近一次同步可回滚。
5. 错误分层：网络、token、权限、远端文件缺失、格式损坏。
6. 关闭 Reader / 后台时的 flush 不能被 route disposal 打断。

---

## 11. Release 修改规则

当前 release 主路径：

```text
main
→ bump version
→ build DMG
→ tag vX.Y.Z
→ GitHub Actions release
```

发布前确认：

- 用户明确允许发版。
- 当前分支是 main。
- 工作树干净。
- 版本号正确。
- tag 不存在。
- DMG 能打开。
- checksum 正确。
- release notes 是用户可见变化。

建议长期方向：

1. Developer ID signing。
2. notarization。
3. Sparkle 自动更新。
4. 分 channel：stable / beta / nightly。
5. release notes 从 `docs/CHANGELOG.md` 或 tag message 生成。

---

## 12. 建议的本地 skill

如果使用 Codex / Claude Code，建议新增：

```text
.codex/skills/hoshi-reader-mac-workflow/SKILL.md
```

内容示例：

```md
# Hoshi Reader Mac Workflow Skill

## Before touching Reader

1. Read `AGENTS.md`.
2. Read `docs/TODO.md`.
3. Inspect the relevant Reader Swift/JS/CSS files.
4. Classify the issue:
   - SwiftUI layout
   - Catalyst safe area
   - WKWebView sizing
   - CSS pagination
   - JS page state
   - popup coordinates
5. Do not patch with magic numbers unless justified.
6. Run targeted build/verification.

## Before touching Anki

1. Inspect `Core/AnkiManager.swift`.
2. Preserve field mappings.
3. Verify disconnected, connected, duplicate, add success, add failure.
4. Do not mix dictionary audio and Sasayaki audio.

## Before touching Sync

1. Inspect sync direction logic.
2. Protect local progress.
3. Add clear user-facing errors.
4. Do not overwrite silently.

## Before release

1. Confirm user explicitly approved release.
2. Verify branch, version, tag, build, DMG, checksum.
3. Do not publish automatically without approval.
```

---

## 13. Agent 回复要求

完成任务后，agent 回复必须说明：

```text
改了什么
验证了什么
没验证什么
风险是什么
下一步建议是什么
```

不要声称未验证的 UI 已经可用。

---

# Prompt for Codex

下面这段可以直接发给 Codex。

```text
你现在接手的是 Hoshi Reader Mac 仓库。

请先不要写业务代码，先完成以下工作：

1. 阅读现有 `AGENTS.md`。
2. 参考我提供的 `docs/AGENT_DEVELOPMENT_GUIDE.md` 内容。
3. 检查仓库是否已有：
   - `docs/TODO.md`
   - `docs/CHANGELOG.md`
   - `docs/ARCHITECTURE_REFACTORING.md`
   - `docs/UPSTREAM_SYNC_QUEUE.md`
   - `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`
4. 如果不存在，请创建或补充这些文档。
5. 如果已存在，请不要覆盖，先合并规则，保留已有项目事实。
6. 修改重点是建立 agent 开发规范，不要改业务代码。
7. 文档内容要围绕 Hoshi Reader Mac 的真实开发风险：
   - Mac 用户可见行为优先
   - iOS 上游只作行为参考，不可盲目覆盖 Mac 实现
   - Reader / WKWebView / JS / CSS 是最高风险区域
   - AnkiConnect 是 Mac 制卡主路径
   - LocalFileServer / local audio / Sasayaki 音频来源不能混淆
   - Google Drive sync 必须保护用户进度
   - release/tag 必须等用户明确批准
   - 用户可见文案需要考虑 `Localizable.xcstrings`
8. 文档不要写成流水账。
9. `docs/TODO.md` 要短，只记录当前状态、下一步、阻塞项、验证入口。
10. `docs/CHANGELOG.md` 只记录用户可见变化。
11. `docs/ARCHITECTURE_REFACTORING.md` 记录长期架构方向，不记录每次执行日志。
12. `.codex/skills/hoshi-reader-mac-workflow/SKILL.md` 写成实际工作流，方便后续 Codex 在 Reader、Anki、Sync、Release 任务前快速遵守。

完成后请输出：

- 新增/修改了哪些文件
- 每个文件的作用
- 你是否只改了文档
- 是否运行了构建；如果没有，请说明因为本次只改文档
- 后续建议
```
