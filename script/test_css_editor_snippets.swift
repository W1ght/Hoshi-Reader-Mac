import Foundation

enum CSSEditorSnippet {
    static func selector(for dictionaryTitle: String) -> (text: String, cursorOffset: Int) {
        let prefix = "[data-dictionary=\"\(cssStringEscaped(dictionaryTitle))\"] {\n    "
        let suffix = "\n}\n\n"
        return (prefix + suffix, prefix.utf16.count)
    }

    private static func cssStringEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

private func assertCursorIsInsideRule(_ snippet: (text: String, cursorOffset: Int), _ message: String) {
    let text = snippet.text as NSString
    assertEqual(text.substring(with: NSRange(location: snippet.cursorOffset - 4, length: 4)), "    ", "\(message) cursor follows indentation")
    assertEqual(text.substring(from: snippet.cursorOffset), "\n}\n\n", "\(message) cursor precedes closing brace")
}

let plain = CSSEditorSnippet.selector(for: "JMdict")
assertEqual(plain.text, "[data-dictionary=\"JMdict\"] {\n    \n}\n\n", "plain dictionary selector")
assertCursorIsInsideRule(plain, "plain dictionary selector")

let quoted = CSSEditorSnippet.selector(for: "A \"quoted\" dictionary")
assertEqual(
    quoted.text,
    "[data-dictionary=\"A \\\"quoted\\\" dictionary\"] {\n    \n}\n\n",
    "quoted dictionary selector"
)
assertCursorIsInsideRule(quoted, "quoted dictionary selector")

let escaped = CSSEditorSnippet.selector(for: #"path\dictionary"#)
assertEqual(
    escaped.text,
    #"[data-dictionary="path\\dictionary"] {"# + "\n    \n}\n\n",
    "backslash dictionary selector"
)
assertCursorIsInsideRule(escaped, "backslash dictionary selector")

print("CSS editor snippet tests passed")
