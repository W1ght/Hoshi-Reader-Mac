import AppKit
import Foundation
import JavaScriptCore
import SwiftSoup
import Wasm3
import WebKit

enum AidokuHostModules {
    static func linkAll(module: Module, store: AidokuHostStore) throws {
        try linkEnvironment(module: module, store: store)
        try linkStandard(module: module, store: store)
        try linkDefaults(module: module, store: store)
        try linkNetwork(module: module, store: store)
        try linkHTML(module: module, store: store)
        try linkJavaScript(module: module, store: store)
        try linkCanvas(module: module, store: store)
    }

    private static func linkEnvironment(module: Module, store: AidokuHostStore) throws {
        try module.linkFunction(name: "abort", namespace: "env") { (_: Int32, _: Int32, _: Int32, _: Int32) in
            store.cancel()
            Wasm3.yieldNext()
        }
        try module.linkFunction(name: "print", namespace: "env") { (memory: Memory, ptr: Int32, len: Int32) in
            if let value = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) {
                store.logSourceMessage(value)
            }
        }
        try module.linkFunction(name: "sleep", namespace: "env") { (seconds: Int32) in
            guard seconds > 0 else { return }
            for _ in 0..<min(seconds * 10, 1_200) {
                if store.cancelled {
                    Wasm3.yieldNext()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        try module.linkFunction(name: "send_partial_result", namespace: "env") { (memory: Memory, pointer: Int32) in
            store.appendPartialResult(pointer: pointer, memory: MemoryReader(memory: memory))
        }
    }

    private static func linkStandard(module: Module, store: AidokuHostStore) throws {
        // Newer aidoku-rs builds import these two Rust runtime shims from `std`,
        // while older packages import the equivalent functions from `env`.
        // Link both namespaces so a source does not fail only when a later code
        // path (commonly manga details) first emits a diagnostic.
        try module.linkFunction(name: "abort", namespace: "std") { () in
            // A source panic is a source failure, not a user cancellation. Yield
            // into Wasm3's abort trap without poisoning the runtime cancellation
            // flag so callers receive the actual trap and the next call can reset.
            Wasm3.yieldNext()
        }
        try module.linkFunction(name: "print", namespace: "std") {
            (memory: Memory, ptr: Int32, len: Int32) in
            if let value = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) {
                store.logSourceMessage(value)
            }
        }
        try module.linkFunction(name: "destroy", namespace: "std") { (rid: Int32) in store.destroy(rid) }
        try module.linkFunction(name: "buffer_len", namespace: "std") { (rid: Int32) -> Int32 in
            guard let count = store.bytes(rid)?.count, count <= Int(Int32.max) else { return -1 }
            return Int32(count)
        }
        try module.linkFunction(name: "read_buffer", namespace: "std") {
            (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let data = store.bytes(rid), len >= 0, data.count >= len else { return -1 }
            do {
                try MemoryReader(memory: memory).write(data.prefix(Int(len)), pointer: ptr)
                return 0
            } catch { return -3 }
        }
        try module.linkFunction(name: "current_date", namespace: "std") { () -> Double in Date().timeIntervalSince1970 }
        try module.linkFunction(name: "utc_offset", namespace: "std") { () -> Int64 in
            Int64(-TimeZone.current.secondsFromGMT())
        }
        try module.linkFunction(name: "parse_date", namespace: "std") {
            (memory: Memory, datePtr: Int32, dateLen: Int32, formatPtr: Int32, formatLen: Int32,
             localePtr: Int32, localeLen: Int32, zonePtr: Int32, zoneLen: Int32) -> Double in
            let reader = MemoryReader(memory: memory)
            guard let date = try? reader.string(pointer: datePtr, length: dateLen),
                  let format = try? reader.string(pointer: formatPtr, length: formatLen) else { return -4 }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if localeLen > 0, let locale = try? reader.string(pointer: localePtr, length: localeLen) {
                formatter.locale = Locale(identifier: locale)
            }
            if zoneLen > 0, let zone = try? reader.string(pointer: zonePtr, length: zoneLen) {
                formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
            } else {
                formatter.timeZone = .gmt
            }
            return formatter.date(from: date)?.timeIntervalSince1970 ?? -5
        }
    }

    private static func linkDefaults(module: Module, store: AidokuHostStore) throws {
        try module.linkFunction(name: "get", namespace: "defaults") {
            (memory: Memory, keyPtr: Int32, keyLen: Int32) -> Int32 in
            guard let key = try? MemoryReader(memory: memory).string(pointer: keyPtr, length: keyLen) else { return -1 }
            guard let value = store.defaultsValue(for: key) else { return -2 }
            return store.store(bytes: value)
        }
        try module.linkFunction(name: "set", namespace: "defaults") {
            (memory: Memory, keyPtr: Int32, keyLen: Int32, kind: Int32, valuePtr: Int32) -> Int32 in
            guard (0...6).contains(kind),
                  let key = try? MemoryReader(memory: memory).string(pointer: keyPtr, length: keyLen) else { return -1 }
            if kind == 6 {
                store.setDefaultsValue(nil, for: key)
                return 0
            }
            guard let value = try? MemoryReader(memory: memory).resultData(at: valuePtr) else { return -4 }
            store.setDefaultsValue(value, for: key)
            return 0
        }
    }

    private static func linkNetwork(module: Module, store: AidokuHostStore) throws {
        let methods = ["GET", "POST", "PUT", "HEAD", "DELETE", "PATCH", "OPTIONS", "CONNECT", "TRACE"]
        try module.linkFunction(name: "init", namespace: "net") { (method: Int32) -> Int32 in
            guard methods.indices.contains(Int(method)) else { return -3 }
            return store.store(.request(.init(method: methods[Int(method)])))
        }
        try module.linkFunction(name: "set_url", namespace: "net") {
            (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let value = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return -4 }
            return store.updateItem(rid) { item in
                guard case .request(var request) = item else { return -1 }
                request.url = url
                item = .request(request)
                return 0
            } ?? -1
        }
        try module.linkFunction(name: "set_header", namespace: "net") {
            (memory: Memory, rid: Int32, keyPtr: Int32, keyLen: Int32, valPtr: Int32, valLen: Int32) -> Int32 in
            let reader = MemoryReader(memory: memory)
            guard let key = try? reader.string(pointer: keyPtr, length: keyLen),
                  let value = try? reader.string(pointer: valPtr, length: valLen),
                  !key.contains("\r"), !key.contains("\n"), !value.contains("\r"), !value.contains("\n") else { return -2 }
            return store.updateItem(rid) { item in
                guard case .request(var request) = item else { return -1 }
                request.headers[key] = value
                item = .request(request)
                return 0
            } ?? -1
        }
        try module.linkFunction(name: "set_body", namespace: "net") {
            (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let data = try? MemoryReader(memory: memory).data(pointer: ptr, length: len) else { return -2 }
            return store.updateItem(rid) { item in
                guard case .request(var request) = item else { return -1 }
                request.body = data
                item = .request(request)
                return 0
            } ?? -1
        }
        try module.linkFunction(name: "set_timeout", namespace: "net") { (rid: Int32, seconds: Double) -> Int32 in
            store.updateItem(rid) { item in
                guard case .request(var request) = item else { return -1 }
                request.timeout = min(max(1, seconds), 120)
                item = .request(request)
                return 0
            } ?? -1
        }
        try module.linkFunction(name: "send", namespace: "net") { (rid: Int32) -> Int32 in store.sendRequest(rid) }
        try module.linkFunction(name: "send_all", namespace: "net") {
            (memory: Memory, ptr: Int32, count: Int32) -> Int32 in
            guard count > 0, count <= 1_024,
                  let data = try? MemoryReader(memory: memory).data(pointer: ptr, length: count * 4, maximum: 4_096) else { return -1 }
            var descriptors: [Int32] = []
            descriptors.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                descriptors.append(Int32(littleEndian: data.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: index * 4, as: Int32.self)
                }))
            }
            let values = store.sendRequests(descriptors)
            var results = Data()
            results.reserveCapacity(values.count * 4)
            for value in values {
                var result = value.littleEndian
                withUnsafeBytes(of: &result) { results.append(contentsOf: $0) }
            }
            guard (try? MemoryReader(memory: memory).write(results, pointer: ptr)) != nil else { return -11 }
            return values.contains(where: { $0 != 0 }) ? -10 : 0
        }
        try module.linkFunction(name: "data_len", namespace: "net") { (rid: Int32) -> Int32 in
            response(store: store, rid: rid)?.data.count.int32 ?? -8
        }
        try module.linkFunction(name: "read_data", namespace: "net") {
            (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let data = response(store: store, rid: rid)?.data, len >= 0, data.count >= len else { return -8 }
            return (try? MemoryReader(memory: memory).write(data.prefix(Int(len)), pointer: ptr)) == nil ? -11 : 0
        }
        try module.linkFunction(name: "get_image", namespace: "net") { (rid: Int32) -> Int32 in
            guard let data = response(store: store, rid: rid)?.data, let image = NSImage(data: data) else { return -12 }
            return store.store(.image(image, data))
        }
        try module.linkFunction(name: "get_status_code", namespace: "net") { (rid: Int32) -> Int32 in
            response(store: store, rid: rid)?.statusCode.int32 ?? -8
        }
        try module.linkFunction(name: "get_url", namespace: "net") { (rid: Int32) -> Int32 in
            guard let url = response(store: store, rid: rid)?.url.absoluteString else { return -8 }
            return store.store(bytes: Data(url.utf8))
        }
        try module.linkFunction(name: "get_header", namespace: "net") {
            (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let key = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let headers = response(store: store, rid: rid)?.headers,
                  let value = headers.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value else { return -8 }
            return store.store(bytes: Data(value.utf8))
        }
        try module.linkFunction(name: "html", namespace: "net") { (rid: Int32) -> Int32 in
            guard let response = response(store: store, rid: rid),
                  let text = String(data: response.data, encoding: .utf8),
                  let document = try? SwiftSoup.parse(text, response.url.absoluteString) else { return -5 }
            return store.store(.document(document))
        }
        try module.linkFunction(name: "set_rate_limit", namespace: "net") {
            (permits: Int32, period: Int32, unit: Int32) in
            store.setRateLimit(permits: permits, period: period, unit: unit)
        }
    }

    private static func linkHTML(module: Module, store: AidokuHostStore) throws {
        try module.linkFunction(name: "parse", namespace: "html") {
            (memory: Memory, htmlPtr: Int32, htmlLen: Int32, basePtr: Int32, baseLen: Int32) -> Int32 in
            parseHTML(memory: memory, htmlPtr: htmlPtr, htmlLen: htmlLen, basePtr: basePtr, baseLen: baseLen, store: store)
        }
        try module.linkFunction(name: "parse_fragment", namespace: "html") {
            (memory: Memory, htmlPtr: Int32, htmlLen: Int32, basePtr: Int32, baseLen: Int32) -> Int32 in
            parseHTML(memory: memory, htmlPtr: htmlPtr, htmlLen: htmlLen, basePtr: basePtr, baseLen: baseLen, store: store)
        }
        try module.linkFunction(name: "escape", namespace: "html") {
            (memory: Memory, ptr: Int32, len: Int32) -> Int32 in
            guard let text = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) else { return -2 }
            return store.store(bytes: Data(text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").utf8))
        }
        try module.linkFunction(name: "unescape", namespace: "html") {
            (memory: Memory, ptr: Int32, len: Int32) -> Int32 in
            guard let text = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) else { return -2 }
            return store.store(bytes: Data(text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&").utf8))
        }
        try module.linkFunction(name: "kind", namespace: "html") { (rid: Int32) -> Int32 in
            store.withItem(rid) { item in
                switch item {
                case .node(let node): node is TextNode ? 2 : node is Comment ? 4 : node is Element ? 5 : 1
                case .element: 5
                case .elements: 6
                case .document: 7
                default: 0
                }
            } ?? -1
        }
        try module.linkFunction(name: "child_nodes", namespace: "html") { (rid: Int32) -> Int32 in
            guard let nodes = store.withItem(rid, { item -> [Node]? in
                switch item { case .node(let node): node.getChildNodes(); case .element(let element): element.getChildNodes(); case .document(let document): document.getChildNodes(); default: nil }
            }) ?? nil else { return -1 }
            return store.store(.nodes(nodes))
        }
        try module.linkFunction(name: "has_attr", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let key = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) else { return -2 }
            return element(store: store, rid: rid)?.hasAttr(key) == true ? 1 : 0
        }
        try module.linkFunction(name: "set_attr", namespace: "html") { (memory: Memory, rid: Int32, kp: Int32, kl: Int32, vp: Int32, vl: Int32) -> Int32 in
            let reader = MemoryReader(memory: memory)
            guard let key = try? reader.string(pointer: kp, length: kl), let value = try? reader.string(pointer: vp, length: vl), let element = element(store: store, rid: rid), (try? element.attr(key, value)) != nil else { return -1 }
            return 0
        }
        try module.linkFunction(name: "remove_attr", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let key = try? MemoryReader(memory: memory).string(pointer: ptr, length: len), let element = element(store: store, rid: rid), (try? element.removeAttr(key)) != nil else { return -1 }
            return 0
        }
        try linkElementMutation(module: module, name: "set_text", store: store) { try $0.text($1) }
        try linkElementMutation(module: module, name: "set_html", store: store) { try $0.html($1) }
        try linkElementMutation(module: module, name: "prepend", store: store) { try $0.prepend($1) }
        try linkElementMutation(module: module, name: "append", store: store) { try $0.append($1) }
        try module.linkFunction(name: "children", namespace: "html") { (rid: Int32) -> Int32 in
            guard let values = element(store: store, rid: rid)?.children().array() else { return -1 }
            return store.store(.elements(values))
        }
        try linkElementString(module: module, name: "base_uri", store: store) { $0.getBaseUri() }
        try linkElementString(module: module, name: "own_text", store: store) { $0.ownText() }
        try linkElementString(module: module, name: "data", store: store) { $0.data() }
        try linkElementString(module: module, name: "id", store: store) { $0.id() }
        try linkElementString(module: module, name: "tag_name", store: store) { $0.tagName() }
        try linkElementString(module: module, name: "class_name", store: store) { try $0.className() }
        try module.linkFunction(name: "has_class", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let value = try? MemoryReader(memory: memory).string(pointer: ptr, length: len) else { return -2 }
            return element(store: store, rid: rid)?.hasClass(value) == true ? 1 : 0
        }
        try linkElementMutation(module: module, name: "add_class", store: store) { try $0.addClass($1) }
        try linkElementMutation(module: module, name: "remove_class", store: store) { try $0.removeClass($1) }
        for (name, chooser) in [("first", true), ("last", false)] {
            try module.linkFunction(name: name, namespace: "html") { (rid: Int32) -> Int32 in
                guard let values = elements(store: store, rid: rid), let value = chooser ? values.first : values.last else { return -5 }
                return store.store(.element(value))
            }
        }
        try module.linkFunction(name: "get", namespace: "html") { (rid: Int32, index: Int32) -> Int32 in
            guard index >= 0, let values = elements(store: store, rid: rid), values.indices.contains(Int(index)) else { return -5 }
            return store.store(.element(values[Int(index)]))
        }
        try module.linkFunction(name: "size", namespace: "html") { (rid: Int32) -> Int32 in
            if let values = elements(store: store, rid: rid) { return values.count.int32 ?? -1 }
            if let nodes = store.withItem(rid, { if case .nodes(let nodes) = $0 { nodes } else { nil } }) ?? nil { return nodes.count.int32 ?? -1 }
            return -1
        }
        try linkRelatedElement(module: module, name: "parent", store: store) { $0.parent() }
        try module.linkFunction(name: "siblings", namespace: "html") { (rid: Int32) -> Int32 in
            guard let values = element(store: store, rid: rid)?.siblingElements().array() else { return -1 }
            return store.store(.elements(values))
        }
        try linkRelatedElement(module: module, name: "next", store: store) { try $0.nextElementSibling() }
        try linkRelatedElement(module: module, name: "previous", store: store) { try $0.previousElementSibling() }
        try module.linkFunction(name: "attr", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let key = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let element = element(store: store, rid: rid),
                  let value = AidokuHTMLAttributeResolver.value(for: element, key: key) else { return -1 }
            return store.store(bytes: Data(value.utf8))
        }
        try linkElementString(module: module, name: "outer_html", store: store) { try $0.outerHtml() }
        try module.linkFunction(name: "remove", namespace: "html") { (rid: Int32) -> Int32 in
            guard let element = element(store: store, rid: rid), (try? element.remove()) != nil else { return -1 }
            return 0
        }
        try module.linkFunction(name: "select", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let query = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let root = element(store: store, rid: rid),
                  let values = try? AidokuHTMLSelectorResolver.elements(in: root, query: query) else { return -4 }
            return store.store(.elements(values))
        }
        try module.linkFunction(name: "select_first", namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let query = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let root = element(store: store, rid: rid),
                  let value = try? AidokuHTMLSelectorResolver.elements(in: root, query: query).first else { return -5 }
            return store.store(.element(value))
        }
        try linkElementString(module: module, name: "text", store: store) { try $0.text() }
        try linkElementString(module: module, name: "untrimmed_text", store: store) { try $0.text(trimAndNormaliseWhitespace: false) }
        try linkElementString(module: module, name: "html", store: store) { try $0.html() }
    }

    private static func linkJavaScript(module: Module, store: AidokuHostStore) throws {
        try module.linkFunction(name: "context_create", namespace: "js") { () -> Int32 in
            guard let context = JSContext() else { return -2 }
            return store.store(.jsContext(context))
        }
        for name in ["context_eval", "context_eval_async", "context_get"] {
            try module.linkFunction(name: name, namespace: "js") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
                guard let source = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                      let context = store.withItem(rid, { if case .jsContext(let context) = $0 { context } else { nil } }) ?? nil else { return -2 }
                let value = name == "context_get" ? context.objectForKeyedSubscript(source) : context.evaluateScript(source)
                guard let string = value?.toString() else { return -1 }
                return store.store(bytes: Data(string.utf8))
            }
        }
        try module.linkFunction(name: "webview_create", namespace: "js") { () -> Int32 in
            guard let webView = AidokuIsolatedWebView.create() else { return -2 }
            return store.store(.webView(webView))
        }
        try module.linkFunction(name: "webview_set_rule_list", namespace: "js") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let json = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let webView = webView(store: store, rid: rid) else { return -2 }
            return webView.setRuleList(json) ? 0 : -6
        }
        try module.linkFunction(name: "webview_load", namespace: "js") { (rid: Int32, requestID: Int32) -> Int32 in
            guard let webView = webView(store: store, rid: rid), let request = store.urlRequest(requestID),
                  let scheme = request.url?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return -5 }
            webView.load(request)
            return 0
        }
        try module.linkFunction(name: "webview_load_html", namespace: "js") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32, urlPtr: Int32, urlLen: Int32) -> Int32 in
            let reader = MemoryReader(memory: memory)
            guard let html = try? reader.string(pointer: ptr, length: len),
                  let webView = webView(store: store, rid: rid) else { return -2 }
            let baseURL = urlLen > 0 ? (try? reader.string(pointer: urlPtr, length: urlLen)).flatMap(URL.init(string:)) : nil
            webView.loadHTML(html, baseURL: baseURL)
            return 0
        }
        try module.linkFunction(name: "webview_wait_for_load", namespace: "js") { (rid: Int32) -> Int32 in
            guard let webView = webView(store: store, rid: rid) else { return -2 }
            return webView.waitForLoad(timeout: 120) ? 0 : -1
        }
        for name in ["webview_eval", "webview_eval_async"] {
            try module.linkFunction(name: name, namespace: "js") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
                guard let script = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                      let webView = webView(store: store, rid: rid),
                      let value = webView.evaluate(script, timeout: 120) else { return -1 }
                return store.store(bytes: Data(value.utf8))
            }
        }
        try module.linkFunction(name: "webview_add_user_script", namespace: "js") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32, atEnd: Int32, mainOnly: Int32) -> Int32 in
            guard let source = try? MemoryReader(memory: memory).string(pointer: ptr, length: len),
                  let webView = webView(store: store, rid: rid) else { return -2 }
            webView.addUserScript(source, atDocumentEnd: atEnd != 0, mainFrameOnly: mainOnly != 0)
            return 0
        }
    }

    private static func linkCanvas(module: Module, store: AidokuHostStore) throws {
        try module.linkFunction(name: "new_context", namespace: "canvas") { (width: Float, height: Float) -> Int32 in
            guard let canvas = AidokuHostStore.Canvas(width: Int(width.rounded()), height: Int(height.rounded())) else { return -1 }
            return store.store(.canvas(canvas))
        }
        try module.linkFunction(name: "set_transform", namespace: "canvas") { (rid: Int32, tx: Float, ty: Float, sx: Float, sy: Float, angle: Float) -> Int32 in
            guard let canvas = canvas(store: store, rid: rid) else { return -1 }
            canvas.context.translateBy(x: CGFloat(tx), y: CGFloat(ty))
            canvas.context.rotate(by: CGFloat(angle))
            canvas.context.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
            return 0
        }
        try module.linkFunction(name: "draw_image", namespace: "canvas") { (context: Int32, image: Int32, x: Float, y: Float, width: Float, height: Float) -> Int32 in
            drawImage(store: store, context: context, image: image, source: nil, destination: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)))
        }
        try module.linkFunction(name: "copy_image", namespace: "canvas") { (context: Int32, image: Int32, sx: Float, sy: Float, sw: Float, sh: Float, dx: Float, dy: Float, dw: Float, dh: Float) -> Int32 in
            drawImage(store: store, context: context, image: image, source: CGRect(x: CGFloat(sx), y: CGFloat(sy), width: CGFloat(sw), height: CGFloat(sh)), destination: CGRect(x: CGFloat(dx), y: CGFloat(dy), width: CGFloat(dw), height: CGFloat(dh)))
        }
        try module.linkFunction(name: "fill", namespace: "canvas") { (memory: Memory, context: Int32, pathPointer: Int32, r: Float, g: Float, b: Float, a: Float) -> Int32 in
            guard let canvas = canvas(store: store, rid: context),
                  let path = try? decodeCanvasPath(memory: memory, pointer: pathPointer) else { return -7 }
            canvas.context.addPath(path)
            canvas.context.setFillColor(red: CGFloat(clampColor(r) / 255), green: CGFloat(clampColor(g) / 255), blue: CGFloat(clampColor(b) / 255), alpha: CGFloat(clampAlpha(a)))
            canvas.context.fillPath()
            return 0
        }
        try module.linkFunction(name: "stroke", namespace: "canvas") { (memory: Memory, context: Int32, pathPointer: Int32, stylePointer: Int32) -> Int32 in
            guard let canvas = canvas(store: store, rid: context),
                  let path = try? decodeCanvasPath(memory: memory, pointer: pathPointer),
                  let style = try? decodeStrokeStyle(memory: memory, pointer: stylePointer) else { return -7 }
            canvas.context.addPath(path)
            canvas.context.setStrokeColor(red: CGFloat(clampColor(style.color.0) / 255), green: CGFloat(clampColor(style.color.1) / 255), blue: CGFloat(clampColor(style.color.2) / 255), alpha: CGFloat(clampAlpha(style.color.3)))
            canvas.context.setLineWidth(CGFloat(max(0, style.width)))
            canvas.context.setLineCap([.round, .square, .butt][min(Int(style.cap), 2)])
            canvas.context.setLineJoin([.round, .bevel, .miter][min(Int(style.join), 2)])
            canvas.context.setMiterLimit(CGFloat(max(0, style.miterLimit)))
            canvas.context.setLineDash(phase: CGFloat(style.dashOffset), lengths: style.dash.map(CGFloat.init))
            canvas.context.strokePath()
            return 0
        }
        try module.linkFunction(name: "draw_text", namespace: "canvas") { (memory: Memory, context: Int32, ptr: Int32, len: Int32, size: Float, x: Float, y: Float, font: Int32, r: Float, g: Float, b: Float, a: Float) -> Int32 in
            guard let text = try? MemoryReader(memory: memory).string(pointer: ptr, length: len), let canvas = canvas(store: store, rid: context) else { return -1 }
            let selectedFont: NSFont? = store.withItem(font) { item -> NSFont? in
                if case .font(let font) = item { return font }
                return nil
            } ?? nil
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas.context, flipped: true)
            (text as NSString).draw(at: CGPoint(x: CGFloat(x), y: CGFloat(y)), withAttributes: [.font: selectedFont ?? NSFont.systemFont(ofSize: CGFloat(size)), .foregroundColor: NSColor(red: CGFloat(clampColor(r) / 255), green: CGFloat(clampColor(g) / 255), blue: CGFloat(clampColor(b) / 255), alpha: CGFloat(clampAlpha(a)))])
            NSGraphicsContext.restoreGraphicsState()
            return 0
        }
        try module.linkFunction(name: "get_image", namespace: "canvas") { (rid: Int32) -> Int32 in
            guard let canvas = canvas(store: store, rid: rid), let data = canvas.pngData(), let image = NSImage(data: data) else { return -5 }
            return store.store(.image(image, data))
        }
        try module.linkFunction(name: "new_font", namespace: "canvas") { (memory: Memory, ptr: Int32, len: Int32) -> Int32 in
            guard let name = try? MemoryReader(memory: memory).string(pointer: ptr, length: len), let font = NSFont(name: name, size: 12) else { return -10 }
            return store.store(.font(font))
        }
        try module.linkFunction(name: "system_font", namespace: "canvas") { (weight: Int32) -> Int32 in
            store.store(.font(NSFont.systemFont(ofSize: 12, weight: NSFont.Weight(CGFloat(weight) / 10))))
        }
        try module.linkFunction(name: "load_font", namespace: "canvas") { (_: Int32, _: Int32) -> Int32 in -11 }
        try module.linkFunction(name: "new_image", namespace: "canvas") { (memory: Memory, ptr: Int32, len: Int32) -> Int32 in
            guard let data = try? MemoryReader(memory: memory).data(pointer: ptr, length: len), let image = NSImage(data: data) else { return -3 }
            return store.store(.image(image, data))
        }
        try module.linkFunction(name: "get_image_data", namespace: "canvas") { (rid: Int32) -> Int32 in
            guard let data = store.bytes(rid) else { return -3 }
            return store.store(bytes: data)
        }
        try module.linkFunction(name: "get_image_width", namespace: "canvas") { (rid: Int32) -> Float in
            Float(image(store: store, rid: rid)?.size.width ?? -1)
        }
        try module.linkFunction(name: "get_image_height", namespace: "canvas") { (rid: Int32) -> Float in
            Float(image(store: store, rid: rid)?.size.height ?? -1)
        }
    }

    private static func response(store: AidokuHostStore, rid: Int32) -> AidokuHostStore.NetworkResponse? {
        store.withItem(rid) { if case .request(let request) = $0 { request.response } else { nil } } ?? nil
    }

    private static func parseHTML(memory: Memory, htmlPtr: Int32, htmlLen: Int32, basePtr: Int32, baseLen: Int32, store: AidokuHostStore) -> Int32 {
        let reader = MemoryReader(memory: memory)
        guard let html = try? reader.string(pointer: htmlPtr, length: htmlLen), let base = try? reader.string(pointer: basePtr, length: baseLen), let document = try? SwiftSoup.parse(html, base) else { return -3 }
        return store.store(.document(document))
    }

    private static func element(store: AidokuHostStore, rid: Int32) -> Element? {
        store.withItem(rid) { item in
            switch item { case .element(let value): value; case .document(let value): value; case .node(let value): value as? Element; default: nil }
        } ?? nil
    }

    private static func elements(store: AidokuHostStore, rid: Int32) -> [Element]? {
        store.withItem(rid) { if case .elements(let values) = $0 { values } else { nil } } ?? nil
    }

    private static func linkElementString(module: Module, name: String, store: AidokuHostStore, body: @escaping (Element) throws -> String) throws {
        try module.linkFunction(name: name, namespace: "html") { (rid: Int32) -> Int32 in
            guard let element = element(store: store, rid: rid), let value = try? body(element) else { return -1 }
            return store.store(bytes: Data(value.utf8))
        }
    }

    private static func linkElementMutation(module: Module, name: String, store: AidokuHostStore, body: @escaping (Element, String) throws -> Any) throws {
        try module.linkFunction(name: name, namespace: "html") { (memory: Memory, rid: Int32, ptr: Int32, len: Int32) -> Int32 in
            guard let value = try? MemoryReader(memory: memory).string(pointer: ptr, length: len), let element = element(store: store, rid: rid), (try? body(element, value)) != nil else { return -1 }
            return 0
        }
    }

    private static func linkRelatedElement(module: Module, name: String, store: AidokuHostStore, body: @escaping (Element) throws -> Element?) throws {
        try module.linkFunction(name: name, namespace: "html") { (rid: Int32) -> Int32 in
            guard let element = element(store: store, rid: rid),
                  let value = try? body(element) else { return -5 }
            return store.store(.element(value))
        }
    }

    private static func canvas(store: AidokuHostStore, rid: Int32) -> AidokuHostStore.Canvas? {
        store.withItem(rid) { if case .canvas(let canvas) = $0 { canvas } else { nil } } ?? nil
    }

    private static func image(store: AidokuHostStore, rid: Int32) -> NSImage? {
        store.withItem(rid) { if case .image(let image, _) = $0 { image } else { nil } } ?? nil
    }

    private static func webView(store: AidokuHostStore, rid: Int32) -> AidokuIsolatedWebView? {
        store.withItem(rid) { if case .webView(let webView) = $0 { webView } else { nil } } ?? nil
    }

    private struct CanvasStrokeStyle {
        let color: (Float, Float, Float, Float)
        let width: Float
        let cap: UInt64
        let join: UInt64
        let miterLimit: Float
        let dash: [Float]
        let dashOffset: Float
    }

    private static func decodeCanvasPath(memory: Memory, pointer: Int32) throws -> CGPath {
        let data = try MemoryReader(memory: memory).resultData(at: pointer)
        var reader = AidokuPostcardReader(data: data)
        let path = CGMutablePath()
        let operations = try reader.readArray(maximumCount: 100_000) { reader -> (UInt64, [CGPoint], [Float]) in
            let variant = try reader.readVarUInt()
            func point(_ reader: inout AidokuPostcardReader) throws -> CGPoint {
                CGPoint(x: CGFloat(try reader.readFloat()), y: CGFloat(try reader.readFloat()))
            }
            switch variant {
            case 0, 1: return (variant, [try point(&reader)], [])
            case 2: return (variant, [try point(&reader), try point(&reader)], [])
            case 3: return (variant, [try point(&reader), try point(&reader), try point(&reader)], [])
            case 4: return (variant, [try point(&reader)], [try reader.readFloat(), try reader.readFloat(), try reader.readFloat()])
            case 5: return (variant, [], [])
            default: throw AidokuRuntimeError.malformedPostcard
            }
        }
        try reader.finish()
        for operation in operations {
            switch operation.0 {
            case 0: path.move(to: operation.1[0])
            case 1: path.addLine(to: operation.1[0])
            case 2: path.addQuadCurve(to: operation.1[0], control: operation.1[1])
            case 3: path.addCurve(to: operation.1[0], control1: operation.1[1], control2: operation.1[2])
            case 4:
                path.addArc(
                    center: operation.1[0],
                    radius: CGFloat(operation.2[0]),
                    startAngle: CGFloat(operation.2[1]),
                    endAngle: CGFloat(operation.2[1] + operation.2[2]),
                    clockwise: operation.2[2] > 0
                )
            case 5: path.closeSubpath()
            default: break
            }
        }
        return path
    }

    private static func decodeStrokeStyle(memory: Memory, pointer: Int32) throws -> CanvasStrokeStyle {
        let data = try MemoryReader(memory: memory).resultData(at: pointer)
        var reader = AidokuPostcardReader(data: data)
        let color = (try reader.readFloat(), try reader.readFloat(), try reader.readFloat(), try reader.readFloat())
        let style = CanvasStrokeStyle(
            color: color,
            width: try reader.readFloat(),
            cap: try reader.readVarUInt(),
            join: try reader.readVarUInt(),
            miterLimit: try reader.readFloat(),
            dash: try reader.readArray { try $0.readFloat() },
            dashOffset: try reader.readFloat()
        )
        try reader.finish()
        return style
    }

    private static func clampColor(_ value: Float) -> Float { min(255, max(0, value)) }
    private static func clampAlpha(_ value: Float) -> Float { min(1, max(0, value)) }

    private static func drawImage(store: AidokuHostStore, context: Int32, image imageID: Int32, source: CGRect?, destination: CGRect) -> Int32 {
        guard let canvas = canvas(store: store, rid: context), let image = image(store: store, rid: imageID), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil), destination.width > 0, destination.height > 0 else { return -3 }
        let sourceImage: CGImage
        if let source {
            guard source.width > 0, source.height > 0 else { return -4 }
            // CGImage cropping uses its pixel-space (top-left) coordinates, matching Aidoku.
            // CGContext destinations are bottom-left and are converted separately below.
            guard source.minX >= 0,
                  source.minY >= 0,
                  source.maxX <= CGFloat(cgImage.width),
                  source.maxY <= CGFloat(cgImage.height),
                  let cropped = cgImage.cropping(to: source) else { return -4 }
            sourceImage = cropped
        } else { sourceImage = cgImage }
        let coreGraphicsDestination = CGRect(
            x: destination.minX,
            y: CGFloat(canvas.height) - destination.maxY,
            width: destination.width,
            height: destination.height
        )
        canvas.context.draw(sourceImage, in: coreGraphicsDestination)
        return 0
    }
}

enum AidokuHTMLAttributeResolver {
    private static let lazyImageAttributes = ["data-lazy-src", "data-src", "data-url"]

    static func value(for element: Element, key: String) -> String? {
        guard let original = try? element.attr(key) else { return nil }
        guard key == "src" || key == "abs:src",
              original.isEmpty || isTransparentPixel(original) else {
            return original
        }
        let prefix = key.hasPrefix("abs:") ? "abs:" : ""
        for attribute in lazyImageAttributes {
            guard let candidate = try? element.attr(prefix + attribute),
                  !candidate.isEmpty,
                  !isTransparentPixel(candidate) else { continue }
            return candidate
        }
        return original
    }

    private static func isTransparentPixel(_ value: String) -> Bool {
        guard value.hasPrefix("data:image/"),
              let comma = value.firstIndex(of: ","),
              value[..<comma].lowercased().contains(";base64"),
              let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
              let image = NSImage(data: data) else { return false }
        return image.size.width <= 1 && image.size.height <= 1
    }
}

enum AidokuHTMLSelectorResolver {
    static func elements(in root: Element, query: String) throws -> [Element] {
        let original = try root.select(query).array()
        guard original.isEmpty, let fallback = ampImageFallback(for: query) else {
            return original
        }
        return try root.select(fallback).array()
    }

    private static func ampImageFallback(for query: String) -> String? {
        guard query == "img"
                || query.hasPrefix("img.")
                || query.hasPrefix("img#")
                || query.hasPrefix("img[")
                || query.hasPrefix("img:") else {
            return nil
        }
        return "amp-\(query)"
    }
}

private extension Int {
    var int32: Int32? { self >= Int(Int32.min) && self <= Int(Int32.max) ? Int32(self) : nil }
}

private extension Elements {
    func array() -> [Element] { (0..<size()).map { get($0) } }
}
