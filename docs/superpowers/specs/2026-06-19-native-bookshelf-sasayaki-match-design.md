# 原生书架 Sasayaki 匹配恢复设计

## 目标

恢复 v0.5.0 的书架匹配行为，同时保持当前原生 macOS 书架结构。启用 Sasayaki 后，用户可以右键本地书籍，选择“匹配”，在弹窗中选择 SRT、调整搜索窗口、执行匹配并查看匹配率。

## 实现边界

- 在 `NativeBookshelfReuseView` 保存当前待匹配的 `BookMetadata`。
- 将该状态传给 `NativeBookshelfSectionsView`，把 `ShelfView.onMatch` 从空操作改为选中对应书籍。
- 在原生书架挂载现有 `SasayakiMatchView(book:viewModel:)` sheet。
- 继续使用现有 `BookCell` 的 `enableSasayaki` 显示条件。
- 继续使用现有 `BookshelfViewModel.runSasayakiMatch`、`SasayakiParser`、`SasayakiMatcher` 和 `sasayaki_match.json` 格式。
- 不新增批量匹配、全局协调器或新的持久化格式。

## v0.5.0 视觉对齐

- 匹配界面使用宽而居中的系统 sheet，设置明确的理想宽高，避免原生 macOS `Form` 按内容压缩成狭小窗口。
- 顶部使用自定义 header：标题“匹配”水平居中，“完成”按钮固定在右上角；不依赖 macOS 将 `confirmationAction` 放到底部的默认行为。
- 主体复用原生设置页的 `NativeSettingsForm`、`NativeSettingsSectionCard`、`NativeSettingsRow` 和统一 palette。
- “文件”作为独立圆角卡片；文件名在左，“打开”在右。
- “匹配搜索范围”、当前数值、滑块和“匹配”按钮位于同一圆角卡片，按钮在滑块下方并由分隔线区分。
- “当前匹配”作为独立圆角卡片，左侧显示“匹配率”，右侧显示匹配数量与百分比。
- 保留原生 macOS 字体、动态深浅色、按钮和滑块行为，不引入 UIKit、Catalyst bridge 或一次性手绘玻璃组件。

## 数据流

1. 用户右键本地书籍并点击“匹配”。
2. `BookCell` 经 `ShelfView` 把该书传回原生书架。
3. 原生书架设置待匹配书籍，SwiftUI 打开 `SasayakiMatchView`。
4. 用户选择 SRT 并执行匹配。
5. 现有匹配器生成结果，`BookshelfViewModel` 保存 `sasayaki_match.json`。
6. 弹窗显示已有匹配率；关闭后留在书架。

## 错误与数据安全

- 未选择文件时禁用匹配按钮，沿用现有行为。
- 匹配失败不写入无效 sidecar；不删除或替换 EPUB。
- 实际数据测试前备份目标书籍已有 `sasayaki_match.json`，测试结束后恢复。

## 验证

- 新增契约测试，禁止原生书架再次把 `onMatch` 接为空操作，并要求存在匹配 sheet。
- 验证 Light App 构建、bundle id 和运行进程路径。
- Computer Use 验证：右键入口、弹窗打开/关闭、书架仍可操作。
- Computer Use 对照 v0.5.0 参考图验证：弹窗尺寸、居中标题、右上完成按钮、三组内容层级、卡片圆角、间距、数值对齐以及窄/宽书架窗口下的稳定性。
- 使用现有实际 EPUB 与 SRT 验证匹配执行、匹配率显示及 Reader 识别；若本机没有可安全使用的 SRT，明确报告该项未覆盖。
