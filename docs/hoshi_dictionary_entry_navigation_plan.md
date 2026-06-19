# Hoshi Reader Mac：Yomitan-like Dictionary Entry Navigation 实现方案

## 目标

在 Hoshi Reader Mac 的字典 WebView / 查词弹窗里实现类似 Yomitan 的词条导航快捷键：

- Previous Entry：跳到上一个 dictionary entry
- Next Entry：跳到下一个 dictionary entry
- 支持 Jump Count，默认 `1`
- 默认快捷键：
  - `Option + PageUp`：Previous Entry
  - `Option + PageDown`：Next Entry
- 作用范围：字典搜索页、Reader 里的查词 popup、nested popup
- 不影响搜索框输入、Reader 翻页、Sasayaki 快捷键

---

## 当前项目相关结构

项目是 Mac Catalyst SwiftUI 应用，已有：

- `UserConfig`：保存用户设置、快捷键、popup 尺寸、字典设置等
- `ReaderKeyboardShortcut`：已有快捷键模型，支持 arrow / pageUp / pageDown / space / 字符键和 modifiers
- `KeyboardShortcutsView`：已有快捷键录制 UI
- `DictionarySearchView`：字典搜索页，调用 `PopupWebView` 渲染字典结果
- `LookupEngine` / `DictionaryManager`：负责 Yomitan 词典导入、查询、样式加载
- `PopupWebView`：字典 HTML / JS / CSS 渲染入口，需要在仓库内定位其定义文件

目前已有的快捷键主要是：

- Reader previous / next page
- Sasayaki previous / play-pause / next cue

本次要补的是 **dictionary entry navigation**。

---

## 设计原则

### 1. 不照搬 Yomitan 的完整 HotkeyHandler

Yomitan 是浏览器扩展，使用 JS 统一监听 `document.keydown`，再分发到 action。

Hoshi Reader Mac 是 SwiftUI + Mac Catalyst + WKWebView。更合适的方式是：

```text
Swift / UIKit 捕获快捷键
        ↓
WKWebView.evaluateJavaScript(...)
        ↓
JS 在 WebView 内部移动当前 entry 并滚动
```

这样作用域更清楚，不容易影响 Reader 其他快捷键。

---

### 2. Swift 只负责发命令，entry index 由 JS 维护

不要在 Swift 层维护当前 entry index。原因：

- WebView 内容会重渲染
- 字典 entry 可能折叠 / 展开
- nested popup 可能有自己的 WebView
- JS 最清楚 DOM 当前状态

Swift 只需要调用：

```js
window.hoshiMoveDictionaryEntry(direction, count)
```

JS 内部负责：

- normalize entry DOM
- 维护 `currentEntryIndex`
- clamp index
- 设置 `entry-current`
- `scrollIntoView`

---

### 3. 默认 Count 使用 1

Yomitan 的快捷键设置里可以看到 `Count: 3`，但 Hoshi 的 popup 默认高度较小。默认跳 3 个容易越过用户想看的词条。

建议默认：

```text
dictionaryEntryJumpCount = 1
```

用户可在设置里改成 2、3、5 等。

---

## 实现步骤

---

## Step 1：扩展 `UserConfig`

文件：

```text
Core/UserConfig.swift
```

新增配置：

```swift
var dictionaryPreviousEntryShortcut: ReaderKeyboardShortcut {
    didSet {
        Self.saveShortcut(dictionaryPreviousEntryShortcut, key: "dictionaryPreviousEntryShortcut")
    }
}

var dictionaryNextEntryShortcut: ReaderKeyboardShortcut {
    didSet {
        Self.saveShortcut(dictionaryNextEntryShortcut, key: "dictionaryNextEntryShortcut")
    }
}

var dictionaryEntryJumpCount: Int {
    didSet {
        UserDefaults.standard.set(dictionaryEntryJumpCount, forKey: "dictionaryEntryJumpCount")
    }
}
```

在 `init()` 里加入默认值：

```swift
self.dictionaryPreviousEntryShortcut =
    Self.loadShortcut(key: "dictionaryPreviousEntryShortcut")
    ?? ReaderKeyboardShortcut(key: "pageUp", modifiers: EventModifiers.option.rawValue)

self.dictionaryNextEntryShortcut =
    Self.loadShortcut(key: "dictionaryNextEntryShortcut")
    ?? ReaderKeyboardShortcut(key: "pageDown", modifiers: EventModifiers.option.rawValue)

self.dictionaryEntryJumpCount =
    defaults.object(forKey: "dictionaryEntryJumpCount") as? Int ?? 1
```

---

## Step 2：把快捷键解析逻辑抽到公共位置

当前 `KeyboardShortcutsView.swift` 里有一个 private extension：

```swift
private extension ReaderKeyboardShortcut {
    init?(key: UIKey) { ... }
}
```

这个逻辑现在只能设置页使用。需要移动到公共文件，例如：

```text
Util/KeyboardShortcut+UIKey.swift
```

建议实现：

```swift
import SwiftUI
import UIKit

extension ReaderKeyboardShortcut {
    init?(uiKey key: UIKey) {
        guard let keyValue = Self.keyValue(for: key) else {
            return nil
        }

        self.key = keyValue
        self.modifiers = Self.eventModifiers(from: key.modifierFlags).rawValue
    }

    func matches(_ key: UIKey) -> Bool {
        guard let pressed = ReaderKeyboardShortcut(uiKey: key) else {
            return false
        }
        return pressed.key == self.key && pressed.modifiers == self.modifiers
    }

    private static func keyValue(for key: UIKey) -> String? {
        switch key.keyCode {
        case .keyboardLeftArrow: return "leftArrow"
        case .keyboardRightArrow: return "rightArrow"
        case .keyboardUpArrow: return "upArrow"
        case .keyboardDownArrow: return "downArrow"
        case .keyboardPageUp: return "pageUp"
        case .keyboardPageDown: return "pageDown"
        case .keyboardSpacebar: return "space"
        case .keyboardEscape: return nil
        default:
            guard let character = key.charactersIgnoringModifiers.lowercased().first,
                  !character.isWhitespace else {
                return nil
            }
            return String(character)
        }
    }

    private static func eventModifiers(from flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
```

然后删除 `KeyboardShortcutsView.swift` 里的重复 private extension，改用：

```swift
ReaderKeyboardShortcut(uiKey: key)
```

---

## Step 3：扩展 `KeyboardShortcutsView`

文件：

```text
Features/Settings/KeyboardShortcutsView.swift
```

新增 action：

```swift
private enum ShortcutAction: Hashable {
    case previousPage
    case nextPage
    case previousSasayakiCue
    case playPauseSasayaki
    case nextSasayakiCue
    case previousDictionaryEntry
    case nextDictionaryEntry
}
```

在 `assign(_:)` 里加入：

```swift
case .previousDictionaryEntry:
    userConfig.dictionaryPreviousEntryShortcut = shortcut
case .nextDictionaryEntry:
    userConfig.dictionaryNextEntryShortcut = shortcut
```

在 `List` 中新增分组：

```swift
Section("Dictionary") {
    ShortcutRecorderRow(
        title: "Previous Entry",
        shortcut: $userConfig.dictionaryPreviousEntryShortcut,
        action: .previousDictionaryEntry,
        recording: $recording
    )

    ShortcutRecorderRow(
        title: "Next Entry",
        shortcut: $userConfig.dictionaryNextEntryShortcut,
        action: .nextDictionaryEntry,
        recording: $recording
    )

    Stepper(
        "Entry Jump Count: \(userConfig.dictionaryEntryJumpCount)",
        value: $userConfig.dictionaryEntryJumpCount,
        in: 1...10
    )
}
```

---

## Step 4：在 `PopupWebView` 内捕获快捷键

定位 `PopupWebView` 定义文件。

建议在内部 WKWebView 使用子类：

```swift
final class DictionaryNavigationWKWebView: WKWebView {
    var onKeyPress: ((UIKey) -> Bool)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key,
           onKeyPress?(key) == true {
            return
        }

        super.pressesBegan(presses, with: event)
    }
}
```

在 `makeUIView` / `makeUIViewController` 中设置：

```swift
webView.onKeyPress = { [weak webView] key in
    guard AppPlatform.usesDesktopLayout else {
        return false
    }

    let count = max(1, userConfig.dictionaryEntryJumpCount)

    if userConfig.dictionaryPreviousEntryShortcut.matches(key) {
        webView?.evaluateJavaScript("window.hoshiMoveDictionaryEntry?.(-1, \(count));")
        return true
    }

    if userConfig.dictionaryNextEntryShortcut.matches(key) {
        webView?.evaluateJavaScript("window.hoshiMoveDictionaryEntry?.(1, \(count));")
        return true
    }

    return false
}
```

当 popup 出现、WebView 被点击、或内容加载完成后，可尝试：

```swift
DispatchQueue.main.async {
    webView.becomeFirstResponder()
}
```

注意不要在搜索框输入时强行抢焦点。字典搜索页的主结果 WebView 可以在用户点击结果区域后成为 first responder；reader popup 打开时可以自动成为 first responder。

---

## Step 5：注入 JS 导航逻辑

在 `PopupWebView` 构造 HTML 或注入 JS 的地方加入以下脚本。

脚本目标：

- 给 entries 添加 `data-hoshi-entry-index`
- 维护 `currentEntryIndex`
- 支持 `hoshiMoveDictionaryEntry(direction, count)`
- 支持滚动与高亮
- 支持内容重渲染后重新 normalize

```js
(function () {
    if (window.__hoshiDictionaryEntryNavigationInstalled) {
        return;
    }
    window.__hoshiDictionaryEntryNavigationInstalled = true;

    let currentEntryIndex = 0;

    function getEntriesContainer() {
        return document.querySelector("#entries-container");
    }

    function guessEntryNodes() {
        const container = getEntriesContainer();
        if (!container) {
            return [];
        }

        let entries = Array.from(container.querySelectorAll("[data-hoshi-entry-index]"));
        if (entries.length > 0) {
            return entries;
        }

        entries = Array.from(container.querySelectorAll(".dictionary-entry, .entry, [data-entry-index]"));
        if (entries.length > 0) {
            return entries;
        }

        return Array.from(container.children).filter((node) => {
            return node instanceof HTMLElement && node.offsetParent !== null;
        });
    }

    function normalizeDictionaryEntries() {
        const entries = guessEntryNodes();

        entries.forEach((entry, index) => {
            entry.classList.add("dictionary-entry");
            entry.dataset.hoshiEntryIndex = String(index);
        });

        return entries;
    }

    function getEntries() {
        return normalizeDictionaryEntries();
    }

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    window.hoshiFocusDictionaryEntry = function (index, smooth = true) {
        const entries = getEntries();

        if (entries.length === 0) {
            return false;
        }

        index = clamp(index, 0, entries.length - 1);

        for (const entry of entries) {
            entry.classList.remove("entry-current");
        }

        const entry = entries[index];
        entry.classList.add("entry-current");
        currentEntryIndex = index;

        entry.scrollIntoView({
            block: "start",
            inline: "nearest",
            behavior: smooth ? "smooth" : "auto"
        });

        return true;
    };

    window.hoshiMoveDictionaryEntry = function (direction, count = 1) {
        direction = Number(direction);
        count = Number(count);

        if (!Number.isFinite(direction) || direction === 0) {
            return false;
        }

        if (!Number.isFinite(count)) {
            count = 1;
        }

        count = Math.max(1, Math.floor(count));
        const sign = direction > 0 ? 1 : -1;

        return window.hoshiFocusDictionaryEntry(currentEntryIndex + sign * count, true);
    };

    window.hoshiResetDictionaryEntryFocus = function () {
        currentEntryIndex = 0;
        return window.hoshiFocusDictionaryEntry(0, false);
    };

    const style = document.createElement("style");
    style.textContent = `
        .dictionary-entry.entry-current {
            outline: 2px solid rgba(90, 140, 255, 0.55);
            outline-offset: 4px;
            border-radius: 8px;
            scroll-margin-top: 72px;
        }
    `;
    document.head.appendChild(style);

    const container = getEntriesContainer();
    if (container) {
        const observer = new MutationObserver(() => {
            normalizeDictionaryEntries();
            currentEntryIndex = Math.min(currentEntryIndex, Math.max(0, getEntries().length - 1));
        });

        observer.observe(container, {
            childList: true,
            subtree: false
        });
    }

    normalizeDictionaryEntries();
})();
```

如果当前项目已有 CSS 注入系统，优先把 CSS 放进已有 CSS 入口，不要重复创建 style。

---

## Step 6：内容更新后 reset focus

当 `lookupEntries` 改变、HTML 重载、或者 `content` 改变时，调用：

```swift
webView.evaluateJavaScript("window.hoshiResetDictionaryEntryFocus?.();")
```

或者 JS 的 MutationObserver 会自动处理。更稳的方式是两者都做。

---

## Step 7：测试点

### 字典搜索页

1. 打开 Dictionary tab
2. 搜索一个多词条词，例如 `出る`
3. 点击结果区域让 WebView 聚焦
4. 按 `Option + PageDown`
5. 应跳到下一个 entry，并出现高亮
6. 按 `Option + PageUp`
7. 应跳回上一个 entry

### Reader popup

1. 打开 EPUB
2. 查词弹出 popup
3. 按 `Option + PageDown`
4. popup 内部应滚动到下一个 entry
5. Reader 不应该翻页

### Nested popup

1. 在 popup 内再次选词 / 点词
2. 打开 nested popup
3. 快捷键应作用于当前 popup，而不是父 popup

### 设置页

1. Settings > Advanced > Keyboard Shortcuts
2. Dictionary 分组存在
3. 修改 Previous / Next Entry 快捷键
4. 重启 app 后仍保留
5. Jump Count 修改后即时生效

### 冲突测试

1. 搜索框正在输入时，不应触发 entry navigation
2. Reader 页面的左右键翻页不应受影响
3. Sasayaki 快捷键不应受影响
4. `Esc` / `Cmd+W` 关闭 reader 不应受影响

---

## 构建验证

运行：

```bash
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

---

## 预期改动文件

大概率涉及：

```text
Core/UserConfig.swift
Features/Settings/KeyboardShortcutsView.swift
Util/KeyboardShortcut+UIKey.swift
PopupWebView 所在文件
```

如果 `PopupWebView` 的 JS / CSS 是独立资源文件，还需要改对应 JS / CSS 文件。

---

## 验收标准

- 默认 `Option + PageUp / Option + PageDown` 可在字典结果中上下移动 entry
- 当前 entry 有明显高亮
- 滚动位置正确，不被顶部搜索栏遮挡
- Jump Count 默认为 1，可配置为 1...10
- 设置页可修改快捷键并持久化
- Reader 翻页快捷键不被破坏
- Sasayaki 快捷键不被破坏
- Mac Catalyst unsigned build 通过
# Historical Catalyst Plan

> 本计划描述已退役的 Mac Catalyst 实现，不是当前开发或验证依据。当前实现必须使用原生 macOS `Hoshi Reader` target、bundle id `moe.shishamo.hoshi` 和 `AGENTS.md` 中的验证入口。
