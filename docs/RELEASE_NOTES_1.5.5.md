## 中文

- 修复从视频挖矿历史跳回已选中的内嵌字幕轨道时，交互字幕与转录可能被清空的问题；返回历史记录后字幕查词与制卡上下文会继续保持可用。
- 视频字幕制卡的动画 AVIF 改用更紧凑的画面尺寸与编码参数，减少短字幕片段生成的媒体体积；同时恢复制卡准备、成功与失败提示，字段准备失败时也会明确反馈。

## English

- Fixed interactive subtitles and the transcript potentially being cleared when returning from Video Mining History to an already selected embedded subtitle track. Subtitle lookup and mining context now remain available after history navigation.
- Animated AVIF captures for Video subtitle mining now use a more compact frame size and encoding profile to reduce media size. Card preparation, success, and failure feedback is restored, including clear errors when field preparation fails.
