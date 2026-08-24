import AidokuRuntimeWatchdog
import Foundation
import Wasm3

public actor AidokuSourceRuntime {
    private struct InvocationResult {
        let finalResult: Data
        let partialResults: [Data]
    }

    public struct Configuration: Sendable {
        public let sourceDirectory: URL
        public let defaults: [String: Data]
        public let cookies: [AidokuStoredCookie]
        public let userAgent: String?
        public let defaultsWriter: @Sendable ([String: Data]) -> Void

        public init(
            sourceDirectory: URL,
            defaults: [String: Data] = [:],
            cookies: [AidokuStoredCookie] = [],
            userAgent: String? = nil,
            defaultsWriter: @escaping @Sendable ([String: Data]) -> Void = { _ in }
        ) {
            self.sourceDirectory = sourceDirectory
            self.defaults = defaults
            self.cookies = cookies
            self.userAgent = userAgent
            self.defaultsWriter = defaultsWriter
        }
    }

    public let manifest: AidokuSourceManifest
    private let hostStore: AidokuHostStore
    private var executor: AidokuWasmExecutor
    private let wasmBytes: Data
    private let exports: Set<String>
    private let sourceDirectory: URL
    private let invocationGate = AidokuInvocationGate()
    private var didStart = false
    private var didPrepareBaseURL = false
    private var executorNeedsReset = false

    public init(configuration: Configuration) throws {
        sourceDirectory = configuration.sourceDirectory
        let manifestURL = configuration.sourceDirectory.appendingPathComponent("source.json")
        let wasmURL = configuration.sourceDirectory.appendingPathComponent("main.wasm")
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        guard manifestData.count <= AidokuLimits.maximumJSONBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        manifest = try JSONDecoder().decode(AidokuSourceManifest.self, from: manifestData)
        let bytes = try Data(contentsOf: wasmURL, options: [.mappedIfSafe])
        exports = try AidokuWasmSanitizer.inspect(bytes).exports
        let sanitized = try AidokuWasmSanitizer.restrictingLinearMemory(in: bytes)
        wasmBytes = sanitized
        var registeredDefaults = try AidokuSourceMetadata.defaultValues(in: configuration.sourceDirectory)
        if manifest.config?.allowsBaseUrlSelect == true,
           let urls = manifest.info.urls,
           urls.count > 1,
           let firstURL = urls.first {
            var writer = AidokuPostcardWriter()
            writer.write(firstURL)
            registeredDefaults["url"] = writer.data
        }
        let manifestUserAgent = manifest.config?.userAgent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredUserAgent = configuration.userAgent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let store = AidokuHostStore(
            defaults: configuration.defaults,
            maximumParallelRequests: manifest.config?.resolvedMaximumParallelRequests ?? 5,
            cookies: configuration.cookies,
            userAgent: manifestUserAgent?.isEmpty == false
                ? manifestUserAgent
                : (configuredUserAgent?.isEmpty == false ? configuredUserAgent : nil),
            sourceID: manifest.info.id,
            defaultsWriter: configuration.defaultsWriter
        )
        store.registerDefaults(registeredDefaults)
        hostStore = store
        executor = try AidokuWasmExecutor(bytes: sanitized, hostStore: store)
    }

    public func listings() async throws -> [AidokuListing] {
        guard exports.contains("get_listings") else {
            return exports.contains("get_manga_list") ? (manifest.listings ?? []) : []
        }
        let data = try await callResult(name: "get_listings", arguments: [], timeout: AidokuLimits.metadataTimeout)
        return try AidokuPostcardModels.decodeListings(data)
    }

    public func homeManga() async throws -> [AidokuManga] {
        guard exports.contains("get_home") else { return [] }
        let result = try await callResultWithPartialResults(
            name: "get_home",
            arguments: [],
            timeout: AidokuLimits.metadataTimeout
        )
        return try AidokuPostcardModels.resolvedHomeManga(
            finalResult: result.finalResult,
            partialResults: result.partialResults
        )
    }

    public func filters() async throws -> [AidokuFilter] {
        if exports.contains("get_filters") {
            let data = try await callResult(
                name: "get_filters",
                arguments: [],
                timeout: AidokuLimits.metadataTimeout
            )
            return try AidokuSourceMetadata.decodeFilters(data)
        }
        return try AidokuSourceMetadata.filters(in: sourceDirectory)
    }

    public func settings() async throws -> [AidokuSetting] {
        let staticSettings = try AidokuSourceMetadata.settings(in: sourceDirectory)
        if exports.contains("get_settings") {
            let data = try await callResult(
                name: "get_settings",
                arguments: [],
                timeout: AidokuLimits.metadataTimeout
            )
            let dynamicSettings = try AidokuSourceMetadata.decodeSettings(data)
            let settings = settingsIncludingManifest(staticSettings + dynamicSettings)
            hostStore.registerDefaults(AidokuSourceMetadata.defaultValues(for: settings))
            return settings
        }
        return settingsIncludingManifest(staticSettings)
    }

    public func search(
        query: String?,
        page: Int,
        filters: [(id: String, value: AidokuFilterValue)] = []
    ) async throws -> AidokuMangaPage {
        await prepareRedirectedBaseURLIfNeeded()
        let queryDescriptor = query.map { hostStore.store(bytes: AidokuPostcardModels.encode($0)) } ?? -1
        let filterDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(filterValues: filters))
        defer {
            if queryDescriptor >= 0 { hostStore.destroy(queryDescriptor) }
            hostStore.destroy(filterDescriptor)
        }
        let data = try await callResult(
            name: "get_search_manga_list",
            arguments: [queryDescriptor, Int32(clamping: page), filterDescriptor],
            timeout: AidokuLimits.metadataTimeout
        )
        return try AidokuPostcardModels.decodeMangaPage(data)
    }

    public func mangaList(listing: AidokuListing, page: Int) async throws -> AidokuMangaPage {
        guard exports.contains("get_manga_list") else {
            throw AidokuRuntimeError.incompatibleSource("missing get_manga_list export")
        }
        await prepareRedirectedBaseURLIfNeeded()
        var writer = AidokuPostcardWriter()
        writer.write(listing.id)
        writer.write(listing.name)
        writer.write(listing.kind.rawValue)
        let descriptor = hostStore.store(bytes: writer.data)
        defer { hostStore.destroy(descriptor) }
        let data = try await callResult(
            name: "get_manga_list",
            arguments: [descriptor, Int32(clamping: page)],
            timeout: AidokuLimits.metadataTimeout
        )
        return try AidokuPostcardModels.decodeMangaPage(data)
    }

    public func mangaDetails(_ manga: AidokuManga, chapters: Bool = true) async throws -> AidokuManga {
        await prepareRedirectedBaseURLIfNeeded()
        let descriptor = hostStore.store(bytes: AidokuPostcardModels.encode(manga))
        defer { hostStore.destroy(descriptor) }
        let result = try await callResultWithPartialResults(
            name: "get_manga_update",
            arguments: [descriptor, 1, chapters ? 1 : 0],
            timeout: AidokuLimits.metadataTimeout
        )
        return try AidokuPostcardModels.resolvedMangaDetails(
            finalResult: result.finalResult,
            partialResults: result.partialResults
        )
    }

    public func pages(manga: AidokuManga, chapter: AidokuChapter) async throws -> [AidokuPage] {
        await prepareRedirectedBaseURLIfNeeded()
        let mangaDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(manga))
        let chapterDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(chapter))
        defer {
            hostStore.destroy(mangaDescriptor)
            hostStore.destroy(chapterDescriptor)
        }
        let data = try await callResult(
            name: "get_page_list",
            arguments: [mangaDescriptor, chapterDescriptor],
            timeout: AidokuLimits.pageTimeout
        )
        return try AidokuPostcardModels.decodePages(data) { hostStore.bytes($0) }
    }

    public func imageRequest(url value: String, context: [String: String]) async throws -> AidokuImageRequest {
        guard let resolvedValue = resolvedRemoteURL(value)?.absoluteString else {
            throw AidokuRuntimeError.unsupportedURL
        }
        guard exports.contains("get_image_request") else {
            guard let url = URL(string: resolvedValue) else { throw AidokuRuntimeError.unsupportedURL }
            return hostStore.modifiedImageRequest(AidokuImageRequest(url: url))
        }
        let urlDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(resolvedValue))
        let contextDescriptor = context.isEmpty ? -1 : hostStore.store(bytes: AidokuPostcardModels.encodePageContext(context))
        defer {
            hostStore.destroy(urlDescriptor)
            if contextDescriptor >= 0 { hostStore.destroy(contextDescriptor) }
        }
        let data = try await callResult(
            name: "get_image_request",
            arguments: [urlDescriptor, contextDescriptor],
            timeout: AidokuLimits.metadataTimeout
        )
        let requestDescriptor = try AidokuPostcardModels.decodeInt32(data)
        defer { hostStore.destroy(requestDescriptor) }
        guard let request = hostStore.networkRequest(requestDescriptor) else {
            throw AidokuRuntimeError.runtimeFailure("Aidoku source returned an invalid image request")
        }
        return request
    }

    private func resolvedRemoteURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//"),
           let url = URL(string: "https:\(trimmed)") {
            return url
        }
        if let absolute = URL(string: trimmed),
           ["http", "https"].contains(absolute.scheme?.lowercased() ?? "") {
            return absolute
        }
        guard let baseValue = manifest.info.url,
              let base = URL(string: baseValue),
              let relative = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(relative.scheme?.lowercased() ?? "") else {
            return nil
        }
        return relative
    }

    public func processPageImage(
        _ data: Data,
        statusCode: Int,
        responseHeaders: [String: String],
        request: AidokuImageRequest,
        context: [String: String]
    ) async throws -> Data {
        guard exports.contains("process_page_image") else { return data }
        guard let imageDescriptor = hostStore.storeImage(data) else {
            throw AidokuRuntimeError.runtimeFailure("Aidoku page response is not a supported image")
        }
        let responseDescriptor = hostStore.store(bytes: AidokuPostcardModels.encodeImageResponse(
            statusCode: UInt16(clamping: statusCode),
            responseHeaders: responseHeaders,
            requestURL: request.url.absoluteString,
            requestHeaders: request.headers,
            imageDescriptor: imageDescriptor
        ))
        let contextDescriptor = context.isEmpty ? -1 : hostStore.store(bytes: AidokuPostcardModels.encodePageContext(context))
        defer { hostStore.destroy(responseDescriptor) }
        defer {
            hostStore.destroy(imageDescriptor)
            if contextDescriptor >= 0 { hostStore.destroy(contextDescriptor) }
        }
        let result = try await callResult(
            name: "process_page_image",
            arguments: [responseDescriptor, contextDescriptor],
            timeout: AidokuLimits.pageTimeout
        )
        let processedDescriptor = try AidokuPostcardModels.decodeInt32(result)
        guard processedDescriptor > 0 else {
            throw AidokuRuntimeError.runtimeFailure("Aidoku source image processor failed with code \(processedDescriptor)")
        }
        defer { hostStore.destroy(processedDescriptor) }
        guard let processed = hostStore.bytes(processedDescriptor) else {
            throw AidokuRuntimeError.runtimeFailure("Aidoku source returned missing processed image \(processedDescriptor)")
        }
        guard processed.count <= AidokuLimits.maximumImageBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return processed
    }

    public func basicLogin(key: String, username: String, password: String) async throws -> Bool {
        let descriptors = [key, username, password].map { hostStore.store(bytes: AidokuPostcardModels.encode($0)) }
        defer { descriptors.forEach(hostStore.destroy) }
        let data = try await callResult(name: "handle_basic_login", arguments: descriptors, timeout: AidokuLimits.metadataTimeout)
        return try AidokuPostcardModels.decodeBool(data)
    }

    public func webLogin(key: String, cookies: [String: String]) async throws -> Bool {
        let keyDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(key))
        let keysDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(cookies.keys.sorted()))
        let valuesDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(cookies.keys.sorted().map { cookies[$0] ?? "" }))
        defer { [keyDescriptor, keysDescriptor, valuesDescriptor].forEach(hostStore.destroy) }
        let data = try await callResult(name: "handle_web_login", arguments: [keyDescriptor, keysDescriptor, valuesDescriptor], timeout: AidokuLimits.metadataTimeout)
        return try AidokuPostcardModels.decodeBool(data)
    }

    public func migrateMangaKey(_ key: String) async throws -> String {
        try await migratedKey(kind: 0, mangaKey: key, chapterKey: nil)
    }

    public func migrateChapterKey(mangaKey: String, chapterKey: String) async throws -> String {
        try await migratedKey(kind: 1, mangaKey: mangaKey, chapterKey: chapterKey)
    }

    public func cancel() {
        hostStore.cancel()
        executor.interrupt()
        executorNeedsReset = true
        didStart = false
    }

    func testingInvoke(name: String, timeout: Duration) async throws -> Int32 {
        try await invocationGate.acquire()
        do {
            try Task.checkCancellation()
            if !didStart {
                hostStore.resetCancellation()
                try await executor.start(timeout: timeout)
                didStart = true
            }
            hostStore.resetCancellation()
            let result = try await executor.call(name: name, arguments: [], timeout: timeout)
            await invocationGate.release()
            return result
        } catch {
            invalidateExecutor()
            await invocationGate.release()
            throw error
        }
    }

    private func migratedKey(kind: Int32, mangaKey: String, chapterKey: String?) async throws -> String {
        let mangaDescriptor = hostStore.store(bytes: AidokuPostcardModels.encode(mangaKey))
        let chapterDescriptor = chapterKey.map { hostStore.store(bytes: AidokuPostcardModels.encode($0)) } ?? -1
        defer {
            hostStore.destroy(mangaDescriptor)
            if chapterDescriptor >= 0 { hostStore.destroy(chapterDescriptor) }
        }
        let data = try await callResult(name: "handle_key_migration", arguments: [kind, mangaDescriptor, chapterDescriptor], timeout: AidokuLimits.metadataTimeout)
        return try AidokuPostcardModels.decodeString(data)
    }

    private func settingsIncludingManifest(_ settings: [AidokuSetting]) -> [AidokuSetting] {
        guard manifest.config?.allowsBaseUrlSelect == true,
              let urls = manifest.info.urls,
              urls.count > 1,
              !settings.contains(where: { $0.id == "url" }) else { return settings }
        return settings + [
            .select(
                id: "url",
                title: "",
                values: urls,
                labels: urls,
                defaultValue: urls.first
            ),
        ]
    }

    private func prepareRedirectedBaseURLIfNeeded() async {
        guard !didPrepareBaseURL else { return }
        didPrepareBaseURL = true
        guard hostStore.defaultsValue(for: "baseUrl") == nil,
              (try? AidokuSourceMetadata.settings(in: sourceDirectory))?.contains(where: {
                  if case .text(let id, _, _, _) = $0 { return id == "baseUrl" }
                  return false
              }) == true,
              let declaredValue = manifest.info.url,
              let declaredURL = URL(string: declaredValue),
              declaredURL.scheme?.lowercased() == "https" else { return }
        do {
            var request = URLRequest(url: declaredURL)
            request.timeoutInterval = 15
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (_, response) = try await AidokuHTTPClient.data(
                for: request,
                maximumBytes: AidokuLimits.maximumJSONBytes
            )
            guard let finalURL = response.url,
                  finalURL.scheme?.lowercased() == "https",
                  finalURL.host?.lowercased() != declaredURL.host?.lowercased(),
                  let finalOrigin = Self.originString(for: finalURL) else { return }
            hostStore.setDefaultsValue(AidokuPostcardModels.encode(finalOrigin), for: "baseUrl")
        } catch {
            // The source still receives its declared default and reports the network/site error.
        }
    }

    private static func originString(for url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func callResult(name: String, arguments: [Int32], timeout: Duration) async throws -> Data {
        try await callResultWithPartialResults(
            name: name,
            arguments: arguments,
            timeout: timeout
        ).finalResult
    }

    private func callResultWithPartialResults(
        name: String,
        arguments: [Int32],
        timeout: Duration
    ) async throws -> InvocationResult {
        try await invocationGate.acquire()
        do {
            try Task.checkCancellation()
            let result = try await callResultExclusively(
                name: name,
                arguments: arguments,
                timeout: timeout
            )
            await invocationGate.release()
            return result
        } catch {
            await invocationGate.release()
            throw error
        }
    }

    private func callResultExclusively(
        name: String,
        arguments: [Int32],
        timeout: Duration
    ) async throws -> InvocationResult {
        defer { hostStore.discardPartialResults() }
        hostStore.clearWebsiteVerificationRequest()
        try resetExecutorIfNeeded()
        if !didStart {
            hostStore.resetCancellation()
            do {
                try await executor.start(timeout: AidokuLimits.metadataTimeout)
            } catch {
                invalidateExecutor()
                if let request = hostStore.takeWebsiteVerificationRequest() {
                    throw AidokuRuntimeError.websiteVerificationRequired(request)
                }
                throw error
            }
            didStart = true
        }
        hostStore.resetCancellation()
        let pointer: Int32
        do {
            pointer = try await executor.call(name: name, arguments: arguments, timeout: timeout)
        } catch {
            invalidateExecutor()
            if let request = hostStore.takeWebsiteVerificationRequest() {
                throw AidokuRuntimeError.websiteVerificationRequired(request)
            }
            throw error
        }
        if let request = hostStore.takeWebsiteVerificationRequest() {
            if pointer > 0 {
                try? await executor.free(pointer: pointer, timeout: AidokuLimits.metadataTimeout)
            }
            invalidateExecutor()
            throw AidokuRuntimeError.websiteVerificationRequired(request)
        }
        guard pointer > 0 else {
            invalidateExecutor()
            throw AidokuRuntimeError.runtimeFailure(hostStore.sourceFailureMessage(for: pointer))
        }
        do {
            let data = try executor.resultData(at: pointer)
            try await executor.free(pointer: pointer, timeout: AidokuLimits.metadataTimeout)
            return InvocationResult(
                finalResult: data,
                partialResults: hostStore.takePartialResults()
            )
        } catch {
            try? await executor.free(pointer: pointer, timeout: AidokuLimits.metadataTimeout)
            invalidateExecutor()
            throw error
        }
    }

    private func resetExecutorIfNeeded() throws {
        guard executorNeedsReset else { return }
        executor = try AidokuWasmExecutor(bytes: wasmBytes, hostStore: hostStore)
        executorNeedsReset = false
        didStart = false
    }

    private func invalidateExecutor() {
        executorNeedsReset = true
        didStart = false
    }
}

actor AidokuInvocationGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var available = true
    private var waiters: [Waiter] = []

    var waitingCount: Int { waiters.count }

    func acquire() async throws {
        try Task.checkCancellation()
        if available {
            available = false
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available = true
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

private final class AidokuWasmExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "moe.shishamo.niratan.aidoku.wasm", qos: .userInitiated)
    private let hostStore: AidokuHostStore
    private let environment: Environment
    private let runtime: Runtime
    private let module: Module
    private let stateLock = NSLock()
    private var runningThread: UInt = 0
    private var watchdogContext: OpaquePointer?

    init(bytes: Data, hostStore: AidokuHostStore) throws {
        self.hostStore = hostStore
        aidoku_watchdog_install()
        environment = try Environment()
        runtime = try environment.createRuntime(stackSize: 512 * 1_024)
        module = try runtime.parseAndLoadModule(bytes: [UInt8](bytes))
        try AidokuHostModules.linkAll(module: module, store: hostStore)
        for required in ["start", "free_result", "get_search_manga_list", "get_manga_update", "get_page_list"] {
            _ = try module.findFunction(name: required)
        }
        guard let context = aidoku_watchdog_context_create() else {
            throw AidokuRuntimeError.runtimeFailure("Unable to allocate Aidoku watchdog")
        }
        watchdogContext = context
    }

    deinit {
        if let watchdogContext {
            aidoku_watchdog_context_destroy(watchdogContext)
        }
    }

    func start(timeout: Duration) async throws {
        try await callVoid(name: "start", argument: nil, timeout: timeout)
    }

    func call(name: String, arguments: [Int32], timeout: Duration) async throws -> Int32 {
        let box = AidokuExecutorResultBox()
        let clock = ContinuousClock()
        let startedAt = clock.now
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async { [self] in
                    guard !box.cancelled else {
                        box.set(.failure(AidokuRuntimeError.cancelled))
                        continuation.resume()
                        return
                    }
                    aidoku_watchdog_context_reset(watchdogContext)
                    aidoku_watchdog_prepare_current_thread(watchdogContext)
                    _ = aidoku_watchdog_deadline_after(timeout.nanoseconds)
                    stateLock.withLock { runningThread = UInt(aidoku_watchdog_current_thread()) }
                    let watchdog = DispatchWorkItem { [self] in
                        box.markTimedOut()
                        hostStore.cancel()
                        interrupt()
                    }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(
                        deadline: .now() + timeout.dispatchInterval,
                        execute: watchdog
                    )
                    defer {
                        watchdog.cancel()
                        aidoku_watchdog_clear_deadline()
                        aidoku_watchdog_clear_current_thread()
                        stateLock.withLock { runningThread = 0 }
                        continuation.resume()
                    }
                    do {
                        let function = try module.findFunction(name: name)
                        let result: Int32
                        switch arguments.count {
                        case 0: result = try function.call()
                        case 1: result = try function.call(arguments[0])
                        case 2: result = try function.call(arguments[0], arguments[1])
                        case 3: result = try function.call(arguments[0], arguments[1], arguments[2])
                        default: throw AidokuRuntimeError.runtimeFailure("Unsupported Aidoku export signature")
                        }
                        box.set(.success(result))
                    } catch {
                        box.set(.failure(error))
                    }
                }
            }
        } onCancel: { [self] in
            box.markCancelled()
            hostStore.cancel()
            interrupt()
        }
        if box.cancelled { throw AidokuRuntimeError.cancelled }
        if box.timedOut || startedAt.duration(to: clock.now) >= timeout {
            throw AidokuRuntimeError.timedOut
        }
        guard let result = box.value else { throw AidokuRuntimeError.runtimeFailure("Aidoku source returned no result") }
        do { return try result.get() } catch {
            if hostStore.cancelled { throw AidokuRuntimeError.cancelled }
            throw AidokuRuntimeError.runtimeFailure(String(describing: error))
        }
    }

    func interrupt() {
        aidoku_watchdog_context_cancel(watchdogContext)
        let thread = stateLock.withLock { runningThread }
        if thread != 0 { _ = aidoku_watchdog_interrupt(thread) }
    }

    func resultData(at pointer: Int32) throws -> Data {
        try MemoryReader(memory: runtime.memory()).resultData(at: pointer)
    }

    func free(pointer: Int32, timeout: Duration) async throws {
        guard pointer > 0 else { return }
        try await callVoid(name: "free_result", argument: pointer, timeout: timeout)
    }

    private func callVoid(name: String, argument: Int32?, timeout: Duration) async throws {
        let box = AidokuExecutorVoidBox()
        let clock = ContinuousClock()
        let startedAt = clock.now
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async { [self] in
                    guard !box.cancelled else {
                        box.set(AidokuRuntimeError.cancelled)
                        continuation.resume()
                        return
                    }
                    aidoku_watchdog_context_reset(watchdogContext)
                    aidoku_watchdog_prepare_current_thread(watchdogContext)
                    _ = aidoku_watchdog_deadline_after(timeout.nanoseconds)
                    stateLock.withLock { runningThread = UInt(aidoku_watchdog_current_thread()) }
                    let watchdog = DispatchWorkItem { [self] in
                        box.markTimedOut()
                        hostStore.cancel()
                        interrupt()
                    }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(
                        deadline: .now() + timeout.dispatchInterval,
                        execute: watchdog
                    )
                    defer {
                        watchdog.cancel()
                        aidoku_watchdog_clear_deadline()
                        aidoku_watchdog_clear_current_thread()
                        stateLock.withLock { runningThread = 0 }
                        continuation.resume()
                    }
                    do {
                        let function = try module.findFunction(name: name)
                        if let argument { try function.call(argument) } else { try function.call() }
                        box.set(nil)
                    } catch {
                        box.set(error)
                    }
                }
            }
        } onCancel: { [self] in
            box.markCancelled()
            hostStore.cancel()
            interrupt()
        }
        if box.cancelled { throw AidokuRuntimeError.cancelled }
        if box.timedOut || startedAt.duration(to: clock.now) >= timeout {
            throw AidokuRuntimeError.timedOut
        }
        if let error = box.value {
            if hostStore.cancelled { throw AidokuRuntimeError.cancelled }
            throw AidokuRuntimeError.runtimeFailure(String(describing: error))
        }
    }
}

private final class AidokuExecutorResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Int32, Error>?
    private var didTimeOut = false
    private var didCancel = false
    var value: Result<Int32, Error>? { lock.withLock { storage } }
    var timedOut: Bool { lock.withLock { didTimeOut } }
    var cancelled: Bool { lock.withLock { didCancel } }
    func set(_ value: Result<Int32, Error>) { lock.withLock { storage = value } }
    func markTimedOut() { lock.withLock { didTimeOut = true } }
    func markCancelled() { lock.withLock { didCancel = true } }
}

private final class AidokuExecutorVoidBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Error?
    private var didTimeOut = false
    private var didCancel = false
    var value: Error? { lock.withLock { storage } }
    var timedOut: Bool { lock.withLock { didTimeOut } }
    var cancelled: Bool { lock.withLock { didCancel } }
    func set(_ value: Error?) { lock.withLock { storage = value } }
    func markTimedOut() { lock.withLock { didTimeOut = true } }
    func markCancelled() { lock.withLock { didCancel = true } }
}

private extension Duration {
    var nanoseconds: UInt64 {
        let components = self.components
        guard components.seconds >= 0, components.attoseconds >= 0 else { return 0 }
        let seconds = UInt64(components.seconds)
        let subsecond = UInt64(components.attoseconds / 1_000_000_000)
        let total = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !total.overflow else { return UInt64.max }
        let combined = total.partialValue.addingReportingOverflow(subsecond)
        return combined.overflow ? UInt64.max : combined.partialValue
    }

    var dispatchInterval: DispatchTimeInterval {
        guard nanoseconds <= UInt64(Int.max) else { return .never }
        return .nanoseconds(Int(nanoseconds))
    }
}

private extension NSLocking {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
