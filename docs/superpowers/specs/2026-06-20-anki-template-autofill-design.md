# Anki 模板默认字段映射设计

## 目标

移植上游提交 `8ffca617204c357e69573741c70c8d57a463bfd5` 的 Lapis、Kiku、Senren 默认字段映射，修复字段未配置时生成的 Anki 卡片缺少内容的问题，同时保护用户已有自定义映射。

## 数据模型

- 在 `Models/Anki.swift` 定义 `AnkiFieldTemplate`，保存笔记类型名称与字段到 Handlebars 的默认映射。
- Lapis、Kiku 使用上游字段名：`Expression`、`ExpressionFurigana`、`ExpressionReading`、`ExpressionAudio`、`SelectionText`、`MainDefinition`、`Sentence`、`Picture`、`Glossary`、`PitchPosition`、`PitchCategories`、`Frequency`、`FreqSort`、`MiscInfo`。
- Senren 使用上游字段名：`word`、`reading`、`sentence`、`selectionText`、`definition`、`wordAudio`、`picture`、`glossary`、`pitchPositions`、`pitchCategories`、`frequencies`、`freqSort`、`miscInfo`。
- 仅为当前 AnkiConnect 返回的实际字段生成映射；模板中存在但笔记类型不存在的字段忽略。

## 合并规则

- 以当前 `fieldMappings` 为输入，只补充 `nil`、空字符串或纯空白的字段。
- 非空的用户映射始终保留，即使它与模板默认值不同。
- 未知笔记类型不改变映射。
- 返回合并后的映射与是否发生变化，便于调用者只在必要时保存。

## 显式恢复默认映射

- 设置页在已识别的 Lapis、Kiku、Senren 笔记类型下提供“应用笔记类型默认映射”操作。
- 操作前显示确认提示；确认后覆盖该模板中、且当前笔记类型实际存在的字段，使被 Video 动漫卡预设改写的小说字段可以恢复。
- 模板未定义的现存字段继续保留，但 Lapis 已确认有害的 `DefinitionPicture` 映射除外；未知笔记类型不显示或禁用此操作。
- 自动补全仍严格采用“只填空值”语义，显式恢复是唯一会覆盖已知模板字段的路径。

## Lapis `DefinitionPicture` 回归修复

### 根因

- Video 动漫卡预设原先用包含关系猜测字段语义，`DefinitionPicture` 因包含 `definition` 被错误映射为 `{glossary}`。
- Lapis 模板把非空 `DefinitionPicture` 放进右浮动 `.def-image`，完整释义因此被渲染为右侧第二栏；正常旧卡该字段为空，所以不受影响。
- “应用笔记类型默认映射”保留模板外字段，使这个错误映射在切回小说默认值后继续存在。

### 修复边界

- Video 动漫卡预设明确跳过 `DefinitionPicture`，不得把释义、截图或其他文本写入该字段。
- Lapis 的显式默认恢复额外移除 `DefinitionPicture` 映射；其他模板外映射仍按现有规则保留。
- 自动补空逻辑不主动删除用户映射，避免启动或刷新时产生静默破坏。
- 不修改 Lapis 卡片模板、CSS 或其他正常卡片。

### 现有坏卡修复

- 修改前把 note `1781894179856` 的完整 `notesInfo` 备份到 `/tmp`。
- 仅通过 AnkiConnect 清空“被害者”note 的 `DefinitionPicture`；其他字段、tags、deck、model 和 scheduling 数据不变。
- 修改后用 `notesInfo` 和 `cardsInfo` 确认字段为空、渲染 HTML 不再包含 `def-image tappable`。

## 触发时机

- `AnkiManager` 加载已保存配置后立即补齐，使用户无需先打开设置页即可正常制卡。
- AnkiConnect 刷新牌组/模板并裁剪失效字段后补齐当前模板。
- 设置页切换笔记类型后补齐新模板并保存。
- Video 的“Apply Anime Card Preset”保持显式覆盖语义，不受默认补空规则限制。
- EPUB 与 Video 暂时共用一份映射；用户可用两个显式预设在小说默认值和 Video 动漫卡值之间切换。

## 数据安全与错误处理

- 不清空字段映射，不覆盖非空映射，不修改 deck/model 选择。
- 不自动创建测试卡片；除用户明确授权修复的“被害者”note 外，不修改用户 Anki 集合。
- 显式恢复只在用户确认后修改 `anki_config.json`；note 修复通过独立、可审计的 AnkiConnect 请求执行。
- 没有匹配模板或字段列表为空时无操作。

## 后续 Profile

- 后续为小说与 Video 引入可切换的 Anki mapping profile，分别保存两套字段映射。
- 本任务不提前改变配置格式，避免在 profile 数据迁移设计完成前引入兼容风险。

## 验证

- 行为测试覆盖：Lapis 完整填充、Kiku 映射、Senren 映射、部分映射补齐、自定义值保留、未知模板无变化、不存在字段不写入。
- 验证 AnkiConnect 刷新和设置页切换调用补齐逻辑。
- 构建 Light App，并用 Computer Use 检查现有 Lapis 可通过确认操作恢复上游小说默认值；除 `DefinitionPicture` 外的模板外字段保留。
- 只验证配置与 UI，不创建真实 Anki 卡片；成功/重复/失败制卡仍需一次明确授权的 disposable deck 测试。
- 回归测试覆盖 Lapis 默认恢复会移除 `DefinitionPicture`、Video 预设不会重新映射它、其他模板外字段保留。
- 实际 Anki 数据验证只修复用户明确指定的“被害者”note，不创建第二张测试卡。
