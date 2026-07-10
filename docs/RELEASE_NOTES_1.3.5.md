## 用户可见改动

- 修复 Reader 查词弹窗内选中文本后，普通鼠标移动到阅读区会取消选区的问题。
- 修复词典释义拖选跨出查词弹窗边界再松开时，选区可能被底层阅读器接管的问题。
- Shift 悬停查词继续可用，并且不会再因普通鼠标移动抢走查词弹窗的焦点。

## User-facing changes

- Fixed Reader lookup popup text selections being cleared when ordinary pointer movement returned to the reading surface.
- Fixed dictionary-definition drags that cross a lookup popup boundary from being taken over by the underlying Reader on release.
- Shift-hover lookup remains available without ordinary pointer movement stealing focus from a lookup popup.
