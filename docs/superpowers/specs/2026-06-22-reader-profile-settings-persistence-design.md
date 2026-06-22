# Reader Profile 设置即时持久化设计

## 问题

`UserConfig` 会把 Reader 外观值立即写入 `UserDefaults`，但 `ProfileSettingsStore` 只在 Profile 切换或场景离开 active 时写入 `reader_settings.json`。正常退出未必触发可靠的场景状态切换，因此 JSON 可能仍是旧值。下一次启动时 `bootstrap` 又用旧 JSON 覆盖从 `UserDefaults` 恢复的新值，表现为外观设置在重启后被重置。

## 方案

把当前 Reader Profile 的设置保存改为变更驱动：应用观察完整的 `ReaderProfileSettings` 值；任一 Reader/外观字段变化时，调用 `ProfileSettingsStore` 的 Reader 专用保存入口，将当前快照以原子写入方式保存到当前 `appliedProfileID` 的 `reader_settings.json`。

保留现有 Profile 切换顺序：先保存旧 Profile，再切换 `appliedProfileID` 并载入新 Profile。载入新 Profile 引起的观察回调只会把已载入的新快照写回新 Profile，不会污染旧 Profile。现有 scene phase 保存继续作为兜底。

词典 Profile 设置、全局 `UserDefaults`、Profile 解析和用户数据路径不变。不新增用户可见文案。

## 验证

先添加一个失败的持久化契约，证明 Reader 设置变更后存在即时保存连接且保存入口只写当前 Reader Profile。然后运行该测试、现有 Profile/Reader 回归测试，并执行 `./script/build_and_run.sh --verify` 启动精确 Light 产物。

手工验证使用非破坏性临时改动：修改一个外观值、正常退出并重启，确认值保持；验证后恢复原值。不得改写书籍、bookmark、sidecar 或阅读进度。
