import Foundation
import WebKit

final class AidokuIsolatedWebView: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let webView: WKWebView
    private let condition = NSCondition()
    nonisolated(unsafe) private var navigationFinished = true

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    nonisolated static func create() -> AidokuIsolatedWebView? {
        runOnMain { AidokuIsolatedWebView() }
    }

    nonisolated func load(_ request: URLRequest) {
        beginNavigation()
        _ = Self.runOnMain { self.webView.load(request) }
    }

    nonisolated func loadHTML(_ html: String, baseURL: URL?) {
        beginNavigation()
        _ = Self.runOnMain { self.webView.loadHTMLString(html, baseURL: baseURL) }
    }

    nonisolated func waitForLoad(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !navigationFinished {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    nonisolated func evaluate(_ script: String, timeout: TimeInterval) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = AidokuWebViewResultBox()
        Self.runOnMainAsync {
            self.webView.evaluateJavaScript(script) { value, error in
                if error == nil {
                    if let string = value as? String { result.set(string) }
                    else if let value { result.set(String(describing: value)) }
                    else { result.set("") }
                }
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return result.value
    }

    nonisolated func addUserScript(_ source: String, atDocumentEnd: Bool, mainFrameOnly: Bool) {
        Self.runOnMain {
            self.webView.configuration.userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: atDocumentEnd ? .atDocumentEnd : .atDocumentStart,
                forMainFrameOnly: mainFrameOnly
            ))
        }
    }

    nonisolated func setRuleList(_ json: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = AidokuWebViewBoolBox()
        let identifier = "niratan-aidoku-\(UUID().uuidString)"
        Self.runOnMainAsync {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { ruleList, error in
                guard let ruleList, error == nil else { semaphore.signal(); return }
                Self.runOnMainAsync {
                    self.webView.configuration.userContentController.add(ruleList)
                    result.set(true)
                    semaphore.signal()
                }
            }
        }
        guard semaphore.wait(timeout: .now() + 30) == .success else { return false }
        return result.value
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishNavigation() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishNavigation() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishNavigation() }

    nonisolated private func beginNavigation() {
        condition.lock()
        navigationFinished = false
        condition.unlock()
    }

    nonisolated private func finishNavigation() {
        condition.lock()
        navigationFinished = true
        condition.broadcast()
        condition.unlock()
    }

    nonisolated private static func runOnMain<T: Sendable>(_ body: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    nonisolated private static func runOnMainAsync(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}

private final class AidokuWebViewResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?
    var value: String? { lock.withLock { storage } }
    func set(_ value: String) { lock.withLock { storage = value } }
}

private final class AidokuWebViewBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool { lock.withLock { storage } }
    func set(_ value: Bool) { lock.withLock { storage = value } }
}

private extension NSLocking {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
