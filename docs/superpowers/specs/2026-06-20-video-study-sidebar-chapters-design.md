# Video 学习侧栏章节设计

## 目标

将 Video Inspector 里的章节列表移入固定右侧学习侧栏，与“挖卡历史”和“字幕列表”使用同一个原生分段切换控件。

## 交互

- 学习侧栏包含 `挖卡历史 / 字幕列表 / 章节` 三个分段。
- 章节行显示章节标题和开始时间，左键跳转到章节。
- 当前播放时间所在章节高亮；最后一章持续高亮到视频结束。
- 没有章节时显示本地化空状态。
- Inspector 的 Video 页移除章节区和章节跳转回调，避免重复入口。

## 边界

- 复用 `VideoChapter`、`VideoTimeFormatter` 和现有 `model.seekToChapter(_:)`，不新增持久化或播放器 API。
- 侧栏宽度、覆盖关系和关闭方式保持不变。
- 不新增章节编辑、搜索或快捷键。

## 验证

- 更新 Video Liquid Glass 契约，先验证三分段、章节列表、高亮和 Inspector 去重失败，再实现至通过。
- 运行相关 Video 契约、Light `--verify` 与 Video `--video --verify`，最终保持 Video 产物运行。
