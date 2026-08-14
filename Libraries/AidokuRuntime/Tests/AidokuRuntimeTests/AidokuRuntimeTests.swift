import AppKit
import Foundation
import SwiftSoup
import Testing
import ZIPFoundation
@testable import AidokuRuntime

private final class DefaultsCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [[String: Data]] = []

    func append(_ values: [String: Data]) { lock.withLock { snapshots.append(values) } }
    func values() -> [[String: Data]] { lock.withLock { snapshots } }
}

@Test func postcardRoundTripsPrimitiveValues() throws {
    var writer = AidokuPostcardWriter()
    writer.write(true)
    writer.write(Int32(-17))
    writer.write(Int64(9_000_000_000))
    writer.write(Float(1.25))
    writer.write("漫画")
    writer.write(Data([0, 1, 2, 255]))
    writer.write(Optional("value")) { writer, value in writer.write(value) }
    writer.write(Optional<String>.none) { writer, value in writer.write(value) }

    var reader = AidokuPostcardReader(data: writer.data)
    #expect(try reader.readBool())
    #expect(try reader.readInt32() == -17)
    #expect(try reader.readInt64() == 9_000_000_000)
    #expect(try reader.readFloat() == 1.25)
    #expect(try reader.readString() == "漫画")
    #expect(try reader.readData(maxBytes: 10) == Data([0, 1, 2, 255]))
    #expect(try reader.readOptional { try $0.readString() } == "value")
    #expect(try reader.readOptional { try $0.readString() } == nil)
    try reader.finish()
}

@Test func sourceFailureUsesOnlyBoundedErrorDiagnosticsFromCurrentInvocation() {
    let store = AidokuHostStore(
        defaults: [:],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: nil,
        defaultsWriter: { _ in }
    )

    store.recordSourceDiagnostic("ordinary source log")
    #expect(store.sourceFailureMessage(for: -1) == "Aidoku source could not decode its input")

    store.recordSourceDiagnostic("Error: JsonParseError(expected value)\nremote response was HTML")
    #expect(
        store.sourceFailureMessage(for: -1)
            == "Aidoku source failed: JsonParseError(expected value) remote response was HTML"
    )

    store.recordSourceDiagnostic("Error: \(String(repeating: "x", count: 4_096))")
    let bounded = store.sourceFailureMessage(for: -1)
    #expect(bounded.count == "Aidoku source failed: ".count + 2_048)

    store.resetCancellation()
    #expect(store.sourceFailureMessage(for: -1) == "Aidoku source could not decode its input")
}

@Test func registeredSettingDefaultsAreFallbacksAndAreNotPersisted() {
    let capture = DefaultsCapture()
    let store = AidokuHostStore(
        defaults: ["quality": Data([9])],
        maximumParallelRequests: 1,
        cookies: [],
        userAgent: nil,
        defaultsWriter: { capture.append($0) }
    )

    store.registerDefaults([
        "quality": Data([1]),
        "contentRating": Data([2]),
    ])
    #expect(store.defaultsValue(for: "quality") == Data([9]))
    #expect(store.defaultsValue(for: "contentRating") == Data([2]))
    #expect(capture.values().isEmpty)

    store.setDefaultsValue(Data([3]), for: "contentRating")
    #expect(store.defaultsValue(for: "contentRating") == Data([3]))
    #expect(capture.values() == [["quality": Data([9]), "contentRating": Data([3])]])

    store.setDefaultsValue(nil, for: "contentRating")
    #expect(store.defaultsValue(for: "contentRating") == Data([2]))
    #expect(capture.values().last == ["quality": Data([9])])
}

@Test func sourceListResolvesRelativeURLsAndLegacyFormat() throws {
    let current = Data(#"{"name":"Fixture","sources":[{"id":"en.fixture","name":"Fixture","version":2,"downloadURL":"sources/fixture.aix","iconURL":"icons/fixture.png","languages":["en"],"contentRating":0}]}"#.utf8)
    let baseURL = try #require(URL(string: "https://example.invalid/repo/index.json"))
    let parsed = try AidokuSourceListParser.parse(data: current, baseURL: baseURL)
    #expect(parsed.name == "Fixture")
    #expect(parsed.sources.first?.downloadURL == "https://example.invalid/repo/sources/fixture.aix")
    #expect(parsed.sources.first?.iconURL == "https://example.invalid/repo/icons/fixture.png")

    let legacy = Data(#"[{"id":"ja.legacy","name":"Legacy","version":1,"file":"legacy.aix","icon":"legacy.png","lang":"ja","nsfw":1}]"#.utf8)
    let legacyParsed = try AidokuSourceListParser.parse(data: legacy, baseURL: baseURL)
    #expect(legacyParsed.sources.first?.languages == ["ja"])
    #expect(legacyParsed.sources.first?.contentRating == .containsAdultContent)
    #expect(legacyParsed.sources.first?.iconURL == "https://example.invalid/repo/legacy.png")
}

@Test func sourceSearchMatchesAllFoldedTermsAcrossMetadataFields() {
    let fields = [
        "コミック DAYS",
        "ja.comicdays",
        "Japanese (ja)",
        "Aidoku Community Sources",
        "Comic Days",
    ]
    #expect(AidokuSourceSearch.matches(query: "comic ja", fields: fields))
    #expect(AidokuSourceSearch.matches(query: "ＣＯＭＩＣ days", fields: fields))
    #expect(AidokuSourceSearch.matches(query: "コミック", fields: fields))
    #expect(!AidokuSourceSearch.matches(query: "comic zh", fields: fields))
    #expect(AidokuSourceSearch.matches(query: "   ", fields: fields))
    #expect(!AidokuSourceSearch.hasTerms("\n\t"))
}

@Test func aidokuLanguageSelectionTypeMatchesCurrentManifestSemantics() throws {
    func manifest(config: String = "") throws -> AidokuSourceManifest {
        try JSONDecoder().decode(AidokuSourceManifest.self, from: Data(#"""
        {
          "info": {
            "id": "multi.fixture",
            "name": "Fixture",
            "version": 1,
            "languages": ["ja", "en"]
          }
          \#(config)
        }
        """#.utf8))
    }

    // MangaDex, MangaPlus, and other current community sources omit config
    // but read the `languages` array from defaults.
    #expect(try manifest().resolvedLanguageSelectType == .multiple)
    #expect(try manifest(config: #", "config": {"languageSelectType":"single"}"#)
        .resolvedLanguageSelectType == .single)
    #expect(try manifest(config: #", "config": {"languageSelectType":"multi"}"#)
        .resolvedLanguageSelectType == .multiple)
    #expect(try manifest(config: #", "config": {"languageSelectType":"multiple"}"#)
        .resolvedLanguageSelectType == .multiple)
    #expect(try manifest(config: #", "config": {"allowsBaseUrlSelect":true}"#)
        .config?.allowsBaseUrlSelect == true)

    let encoded = try JSONEncoder().encode(AidokuSourceManifest.Configuration(
        languageSelectType: .multiple
    ))
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["languageSelectType"] as? String == "multi")
}

@Test func aidokuManifestDecodesAuthenticationRequirement() throws {
    func manifest(_ authentication: String = "") throws -> AidokuSourceManifest {
        try JSONDecoder().decode(AidokuSourceManifest.self, from: Data(#"""
        {
          "info": {
            "id": "zh.fixture",
            "name": "Fixture",
            "version": 1
          }
          \#(authentication)
        }
        """#.utf8))
    }

    #expect(try manifest().requiresAuth == false)
    #expect(try manifest(#", "requiresAuth": true"#).requiresAuth == true)
    #expect(try manifest(#", "requires_auth": true"#).requiresAuth == true)
    #expect(try manifest(#", "config": {"requiresAuth": true}"#).requiresAuth == true)
}

@Test func aidokuLanguageSelectionNormalizesPreferencesAndUpdates() {
    let supported = ["ja", "en", "zh-Hans", "en"]
    #expect(AidokuLanguageDefaults.supportedLanguages(supported) == ["ja", "en", "zh-Hans"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: supported,
        selectedLanguages: nil,
        preferredLanguageIdentifiers: ["zh-Hans-CN"],
        type: .single
    ) == ["zh-Hans"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: supported,
        selectedLanguages: ["EN_us", "missing"],
        preferredLanguageIdentifiers: [],
        type: .multiple
    ) == ["en"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: supported,
        selectedLanguages: [],
        preferredLanguageIdentifiers: ["de-DE"],
        type: .multiple
    ) == ["ja"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: supported,
        selectedLanguages: ["zh-Hans", "ja"],
        preferredLanguageIdentifiers: [],
        type: .single
    ) == ["ja"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: ["zh-Hant", "zh-Hans"],
        selectedLanguages: nil,
        preferredLanguageIdentifiers: ["zh-CN"],
        type: .single
    ) == ["zh-Hans"])
    #expect(AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: ["zh-Hans", "zh-Hant"],
        selectedLanguages: nil,
        preferredLanguageIdentifiers: ["zh-TW"],
        type: .single
    ) == ["zh-Hant"])
}

@Test func aidokuLanguageDefaultsUseExpectedPostcardKeys() throws {
    let single = AidokuLanguageDefaults.encodedDefaults(
        type: .single,
        selectedLanguages: ["ja"]
    )
    #expect(single["languages"] == nil)
    var singleReader = AidokuPostcardReader(data: try #require(single["language"]))
    #expect(try singleReader.readString() == "ja")
    try singleReader.finish()

    let multiple = AidokuLanguageDefaults.encodedDefaults(
        type: .multiple,
        selectedLanguages: ["ja", "en"]
    )
    #expect(multiple["language"] == nil)
    var multipleReader = AidokuPostcardReader(data: try #require(multiple["languages"]))
    #expect(try multipleReader.readArray { try $0.readString() } == ["ja", "en"])
    try multipleReader.finish()
}

@Test func aidokuLanguageSourceCategoriesMatchVariantsAndMultilingualSources() {
    #expect(AidokuLanguageDefaults.matchesLanguageFilter(
        "zh",
        supportedLanguages: ["en", "zh-Hans", "zh-Hant"]
    ))
    #expect(AidokuLanguageDefaults.matchesLanguageFilter(
        "pt",
        supportedLanguages: ["pt-BR"]
    ))
    #expect(!AidokuLanguageDefaults.matchesLanguageFilter(
        "zh-Hans",
        supportedLanguages: ["zh-Hant"]
    ))
    #expect(AidokuLanguageDefaults.matchesLanguageFilter(
        "multi",
        supportedLanguages: ["en", "ja"]
    ))
    #expect(AidokuLanguageDefaults.matchesLanguageFilter(
        "multi",
        supportedLanguages: ["multi"]
    ))
    #expect(!AidokuLanguageDefaults.matchesLanguageFilter(
        "multi",
        supportedLanguages: ["ja"]
    ))
    #expect(!AidokuLanguageDefaults.matchesLanguageFilter(
        "All",
        supportedLanguages: ["All", "ja"]
    ))
}

@Test func legacyBaoziChapterURLUsesCurrentPageDirectEndpoint() throws {
    let legacy = try #require(URL(string:
        "https://appcn.baozimh.com/baozimhapp/comic/chapter/wuliandianfeng-pikapi/0_3873.html"
    ))
    let normalized = AidokuLegacyRequestCompatibility.normalizedURL(legacy)
    let components = try #require(URLComponents(
        url: normalized,
        resolvingAgainstBaseURL: false
    ))

    #expect(components.scheme == "https")
    #expect(components.host == "www.baozimh.com")
    #expect(components.path == "/user/page_direct")
    #expect(components.queryItems == [
        URLQueryItem(name: "comic_id", value: "wuliandianfeng-pikapi"),
        URLQueryItem(name: "section_slot", value: "0"),
        URLQueryItem(name: "chapter_slot", value: "3873"),
    ])
}

@Test func legacyRequestCompatibilityRejectsLookalikesAndMalformedSlots() throws {
    let values = [
        "http://appcn.baozimh.com/baozimhapp/comic/chapter/manga/0_1.html",
        "https://appcn.baozimh.com.evil.invalid/baozimhapp/comic/chapter/manga/0_1.html",
        "https://appcn.baozimh.com/baozimhapp/comic/chapter/manga/latest.html",
        "https://appcn.baozimh.com/other/comic/chapter/manga/0_1.html",
    ]
    for value in values {
        let url = try #require(URL(string: value))
        #expect(AidokuLegacyRequestCompatibility.normalizedURL(url) == url)
    }
}

@Test func manifestListingsAcceptLegacyMissingKind() throws {
    let data = Data(#"""
    {
      "info": {
        "id": "ja.legacy",
        "name": "Legacy",
        "version": 1,
        "contentRating": 0,
        "languages": ["ja"]
      },
      "listings": [{"id": "popular"}]
    }
    """#.utf8)
    let manifest = try JSONDecoder().decode(AidokuSourceManifest.self, from: data)
    #expect(manifest.listings?.first?.kind == .defaultListing)
    #expect(manifest.listings?.first?.name == "popular")
}

@Test func manifestListingsAreHiddenWhenSourceHasNoListingExport() async throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let manifest = Data(#"{"info":{"id":"ja.no-listing-export","name":"No Listing Export","version":1},"listings":[{"id":"popular","name":"Popular"}]}"#.utf8)
    try manifest.write(to: temporary.appendingPathComponent("source.json"))
    try executableFixtureWasm().write(to: temporary.appendingPathComponent("main.wasm"))

    let runtime = try AidokuSourceRuntime(configuration: .init(sourceDirectory: temporary))
    #expect(try await runtime.listings().isEmpty)
}

@Test func htmlImageSourceFallsBackToRealLazyAttribute() throws {
    let placeholder = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="
    let document = try SwiftSoup.parse(
        #"<img src="\#(placeholder)" data-src="/covers/real.jpg">"#,
        "https://example.invalid/home"
    )
    let image = try #require(document.select("img").first())
    #expect(
        AidokuHTMLAttributeResolver.value(for: image, key: "src")
            == "/covers/real.jpg"
    )
    #expect(
        AidokuHTMLAttributeResolver.value(for: image, key: "abs:src")
            == "https://example.invalid/covers/real.jpg"
    )
}

@Test func htmlImageSelectorFallsBackToAMPImageElement() throws {
    let document = try SwiftSoup.parse(
        #"<amp-img class="comic-page" data-src="https://example.invalid/1.jpg"></amp-img>"#,
        "https://example.invalid/chapter"
    )
    let selected = try AidokuHTMLSelectorResolver.elements(
        in: document,
        query: "img.comic-page"
    )
    #expect(selected.count == 1)
    #expect(try selected.first?.attr("data-src") == "https://example.invalid/1.jpg")
}

@Test func sourceListRejectsAltStoreAppCatalogWithSpecificError() throws {
    let altStore = Data(#"{"name":"Aidoku Source","identifier":"app.aidoku.altstore","apps":[{"name":"Aidoku","bundleIdentifier":"app.aidoku.Aidoku","versions":[{"downloadURL":"https://example.invalid/Aidoku.ipa"}]}]}"#.utf8)
    let baseURL = try #require(URL(string: "https://example.invalid/apps.json"))
    #expect(throws: AidokuRuntimeError.altStoreAppCatalog) {
        try AidokuSourceListParser.parse(data: altStore, baseURL: baseURL)
    }
}

@Test func packageValidatorAcceptsSafeFixture() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let archiveURL = temporary.appendingPathComponent("fixture.aix")
    let archive = try Archive(url: archiveURL, accessMode: .create)
    let manifest = Data(#"{"info":{"id":"en.fixture","name":"Fixture","version":1,"contentRating":0,"languages":["en"]}}"#.utf8)
    let wasm = validationFixtureWasm()
    try archive.addEntry(
        with: "Payload/source.json",
        type: .file,
        uncompressedSize: Int64(manifest.count),
        compressionMethod: .deflate,
        provider: { position, size in
            manifest.subdata(in: Int(position)..<Int(position) + size)
        }
    )
    try archive.addEntry(
        with: "Payload/main.wasm",
        type: .file,
        uncompressedSize: Int64(wasm.count),
        compressionMethod: .deflate,
        provider: { position, size in
            wasm.subdata(in: Int(position)..<Int(position) + size)
        }
    )

    let result = try AidokuPackageValidator.validate(archiveURL: archiveURL)
    #expect(result.manifest.info.id == "en.fixture")
}

@Test func packageValidatorRejectsPathTraversalAndMissingABI() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let unsafeURL = temporary.appendingPathComponent("unsafe.aix")
    let unsafeArchive = try Archive(url: unsafeURL, accessMode: .create)
    let byte = Data([0])
    try unsafeArchive.addEntry(
        with: "Payload/../escape",
        type: .file,
        uncompressedSize: Int64(1),
        provider: { (_: Int64, _: Int) in byte }
    )
    #expect(throws: AidokuRuntimeError.self) {
        try AidokuPackageValidator.validate(archiveURL: unsafeURL)
    }

    let missingABIURL = temporary.appendingPathComponent("missing-abi.aix")
    let missingABIArchive = try Archive(url: missingABIURL, accessMode: .create)
    let manifest = Data(#"{"info":{"id":"en.fixture","name":"Fixture","version":1}}"#.utf8)
    let emptyWasm = Data([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
    for (path, data) in [("Payload/source.json", manifest), ("Payload/main.wasm", emptyWasm)] {
        try missingABIArchive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        )
    }
    #expect(throws: AidokuRuntimeError.self) {
        try AidokuPackageValidator.validate(archiveURL: missingABIURL)
    }
}

@Test func wasmSanitizerCapsMemoryAndRejectsOversizedInitialMemory() throws {
    let safe = validationFixtureWasm(initialMemoryPages: 2, maximumMemoryPages: nil)
    let restricted = try AidokuWasmSanitizer.restrictingLinearMemory(in: safe)
    #expect(restricted.count > safe.count)
    let tooLarge = validationFixtureWasm(initialMemoryPages: 1_025, maximumMemoryPages: nil)
    #expect(throws: AidokuRuntimeError.self) {
        try AidokuWasmSanitizer.restrictingLinearMemory(in: tooLarge)
    }
}

@Test func runtimeExecutesFixtureSearchAndInterruptsInfiniteLoop() async throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let manifest = Data(#"{"info":{"id":"en.runtime-fixture","name":"Runtime Fixture","version":1}}"#.utf8)
    try manifest.write(to: temporary.appendingPathComponent("source.json"))
    try executableFixtureWasm().write(to: temporary.appendingPathComponent("main.wasm"))

    let runtime = try AidokuSourceRuntime(configuration: .init(sourceDirectory: temporary))
    let page = try await runtime.search(query: nil, page: 1)
    #expect(page.entries.isEmpty)
    #expect(!page.hasNextPage)

    let clock = ContinuousClock()
    let start = clock.now
    do {
        _ = try await runtime.testingInvoke(name: "infinite_loop", timeout: .milliseconds(50))
        Issue.record("Infinite-loop fixture unexpectedly completed")
    } catch let error as AidokuRuntimeError {
        #expect(error == .timedOut)
    } catch {
        Issue.record("Unexpected infinite-loop error: \(error)")
    }
    #expect(start.duration(to: clock.now) >= .milliseconds(40))
    #expect(start.duration(to: clock.now) < .seconds(2))
}

@Test func invocationGateRemovesCancelledWaitersWithoutStarvingNewRequests() async throws {
    let gate = AidokuInvocationGate()
    let order = InvocationOrderRecorder()
    try await gate.acquire()

    let first = Task {
        try await gate.acquire()
        await order.append(1)
        await gate.release()
    }
    let firstQueued = await eventually { await gate.waitingCount == 1 }
    #expect(firstQueued)

    let cancelled = (0..<32).map { index in
        Task {
            try await gate.acquire()
            await order.append(100 + index)
            await gate.release()
        }
    }
    let cancelledQueued = await eventually { await gate.waitingCount == cancelled.count + 1 }
    #expect(cancelledQueued)

    cancelled.forEach { $0.cancel() }
    let fresh = Task {
        try await gate.acquire()
        await order.append(2)
        await gate.release()
    }

    let cancelledRemoved = await eventually { await gate.waitingCount == 2 }
    #expect(cancelledRemoved)
    await gate.release()

    try await first.value
    try await fresh.value
    for task in cancelled {
        do {
            try await task.value
            Issue.record("Cancelled invocation waiter unexpectedly acquired a permit")
        } catch is CancellationError {
            // Expected: cancellation removes the waiter before the permit is transferred.
        } catch {
            Issue.record("Cancelled invocation waiter failed with unexpected error: \(error)")
        }
    }
    #expect(await order.values == [1, 2])
    #expect(await gate.waitingCount == 0)
}

@Test func runtimeCompletesConcurrentSourceInvocations() async throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let manifest = Data(#"{"info":{"id":"en.concurrent-fixture","name":"Concurrent Fixture","version":1}}"#.utf8)
    try manifest.write(to: temporary.appendingPathComponent("source.json"))
    try executableFixtureWasm().write(to: temporary.appendingPathComponent("main.wasm"))

    let runtime = try AidokuSourceRuntime(configuration: .init(sourceDirectory: temporary))
    let invocationCount = 48
    var completed = 0
    try await withThrowingTaskGroup(of: Bool.self) { group in
        for page in 1...invocationCount {
            group.addTask {
                let result = try await runtime.search(query: "fixture-\(page)", page: page)
                return result.entries.isEmpty && !result.hasNextPage
            }
        }
        for try await validResult in group {
            #expect(validResult)
            completed += 1
        }
    }
    #expect(completed == invocationCount)
}

@Test func optionalInstalledSourceOpensComicActionChapter() async throws {
    guard let sourceDirectory = ProcessInfo.processInfo.environment["AIDOKU_LIVE_SOURCE_DIR"] else {
        return
    }
    let runtime = try AidokuSourceRuntime(configuration: .init(
        sourceDirectory: URL(fileURLWithPath: sourceDirectory, isDirectory: true)
    ))
    let manga = AidokuManga(
        key: "/episode/13933686331674749665",
        title: "小林さんちのメイドラゴン エルマのOL日記"
    )
    let details = try await runtime.mangaDetails(manga, chapters: true)
    let chapter = try #require(details.chapters?.first(where: { !$0.locked }))
    let pages = try await runtime.pages(manga: details, chapter: chapter)
    let firstPage = try #require(pages.first)
    guard case .url(let value, let context) = firstPage.content else {
        Issue.record("Expected Comic Action to return URL pages")
        return
    }
    let imageRequest = try await runtime.imageRequest(url: value, context: context)
    let (image, response) = try await AidokuHTTPClient.data(
        for: URLRequest(url: imageRequest.url),
        maximumBytes: AidokuLimits.maximumImageBytes
    )
    let processed = try await runtime.processPageImage(
        image,
        statusCode: response.statusCode,
        responseHeaders: [:],
        request: imageRequest,
        context: context
    )
    #expect(!processed.isEmpty)
}

@Test func optionalInstalledRawFreeFollowsBaseURLRedirect() async throws {
    guard let sourceDirectory = ProcessInfo.processInfo.environment["AIDOKU_LIVE_RAWFREE_SOURCE_DIR"] else {
        return
    }
    let runtime = try AidokuSourceRuntime(configuration: .init(
        sourceDirectory: URL(fileURLWithPath: sourceDirectory, isDirectory: true)
    ))
    let page = try await runtime.search(query: nil, page: 1)
    #expect(!page.entries.isEmpty)
    #expect(page.entries.allSatisfy { !$0.title.isEmpty })
    let manga = try #require(page.entries.first)
    let details = try await runtime.mangaDetails(manga, chapters: true)
    let chapter = try #require(details.chapters?.first)
    let pages = try await runtime.pages(manga: details, chapter: chapter)
    #expect(!pages.isEmpty)
}

@Test func optionalInstalledRawOtakuLoadsHomeCover() async throws {
    guard let sourceDirectory = ProcessInfo.processInfo.environment["AIDOKU_LIVE_RAWOTAKU_SOURCE_DIR"] else {
        return
    }
    let runtime = try AidokuSourceRuntime(configuration: .init(
        sourceDirectory: URL(fileURLWithPath: sourceDirectory, isDirectory: true)
    ))
    let home = try await runtime.homeManga()
    let covers = try home.prefix(18).map { try #require($0.coverURL) }
    #expect(covers.count == min(home.count, 18))
    #expect(covers.allSatisfy { !$0.hasPrefix("data:image/") })
    var loaded = 0
    try await withThrowingTaskGroup(of: Bool.self) { group in
        for cover in covers {
            group.addTask {
                let imageRequest = try await runtime.imageRequest(url: cover, context: [:])
                var request = URLRequest(url: imageRequest.url)
                imageRequest.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                let (data, response) = try await AidokuHTTPClient.data(
                    for: request,
                    maximumBytes: AidokuLimits.maximumImageBytes
                )
                return (200..<300).contains(response.statusCode) && NSImage(data: data) != nil
            }
        }
        for try await succeeded in group where succeeded { loaded += 1 }
    }
    #expect(loaded == covers.count)
}

@Test func optionalDownloadedPackagesValidate() throws {
    guard let directory = ProcessInfo.processInfo.environment["AIDOKU_PACKAGE_FIXTURE_DIR"] else {
        return
    }
    let urls = try FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: directory, isDirectory: true),
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "aix" }
    #expect(!urls.isEmpty)
    var failures: [String] = []
    for url in urls {
        let expectedID = url.deletingPathExtension().lastPathComponent
        do {
            _ = try AidokuPackageValidator.validate(archiveURL: url, expectedSourceID: expectedID)
        } catch {
            failures.append("\(expectedID): \(error)")
        }
    }
    #expect(failures.isEmpty, Comment(rawValue: failures.sorted().joined(separator: "\n")))
}

@Test func optionalInstalledSourceOpensSelectedComicActionChapter() async throws {
    guard let sourceDirectory = ProcessInfo.processInfo.environment["AIDOKU_LIVE_SOURCE_DIR"],
          let mangaKey = ProcessInfo.processInfo.environment["AIDOKU_LIVE_MANGA_KEY"],
          let chapterKey = ProcessInfo.processInfo.environment["AIDOKU_LIVE_CHAPTER_KEY"] else {
        return
    }
    let runtime = try AidokuSourceRuntime(configuration: .init(
        sourceDirectory: URL(fileURLWithPath: sourceDirectory, isDirectory: true)
    ))
    let manga = AidokuManga(key: mangaKey, title: "Live Fixture")
    let details = try await runtime.mangaDetails(manga, chapters: true)
    let chapter = try #require(details.chapters?.first(where: { $0.key == chapterKey }))
    let pages = try await runtime.pages(manga: details, chapter: chapter)
    let firstPage = try #require(pages.first)
    guard case .url(let value, let context) = firstPage.content else {
        Issue.record("Expected Comic Action to return URL pages")
        return
    }
    let imageRequest = try await runtime.imageRequest(url: value, context: context)
    var request = URLRequest(url: imageRequest.url)
    imageRequest.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    let (image, response) = try await AidokuHTTPClient.data(
        for: request,
        maximumBytes: AidokuLimits.maximumImageBytes
    )
    if let rawOutput = ProcessInfo.processInfo.environment["AIDOKU_LIVE_RAW_OUTPUT"] {
        try image.write(to: URL(fileURLWithPath: rawOutput), options: .atomic)
    }
    let processed = try await runtime.processPageImage(
        image,
        statusCode: response.statusCode,
        responseHeaders: [:],
        request: imageRequest,
        context: context
    )
    #expect(!processed.isEmpty)
    if let output = ProcessInfo.processInfo.environment["AIDOKU_LIVE_OUTPUT"] {
        try processed.write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}

@Test func sourceListRequiresConfirmationForLocalNetwork() throws {
    let localURL = try #require(URL(string: "http://192.168.1.3/index.json"))
    #expect(throws: AidokuRuntimeError.insecureTransportRequiresConfirmation) {
        try AidokuSourceListParser.validateRemoteURL(localURL, insecureTransportConfirmed: false)
    }
    try AidokuSourceListParser.validateRemoteURL(localURL, insecureTransportConfirmed: true)
}

@Test func filterValuesUseDeclaredStringIdentifiers() throws {
    let data = AidokuPostcardModels.encode(filterValues: [
        ("genre", .select("action")),
        ("tags", .multiSelect(include: ["completed"], exclude: ["adult"])),
        ("year", .range(lower: 2000, upper: 2026)),
    ])
    var reader = AidokuPostcardReader(data: data)
    let values = try reader.readArray { reader -> (UInt64, String, [String]) in
        let variant = try reader.readVarUInt()
        let id = try reader.readString()
        switch variant {
        case 3:
            return (variant, id, [try reader.readString()])
        case 4:
            let included = try reader.readArray { try $0.readString() }
            let excluded = try reader.readArray { try $0.readString() }
            return (variant, id, included + excluded)
        case 5:
            let lower = try reader.readOptional { try $0.readFloat() }
            let upper = try reader.readOptional { try $0.readFloat() }
            return (variant, id, [String(lower ?? 0), String(upper ?? 0)])
        default:
            throw AidokuRuntimeError.malformedPostcard
        }
    }
    try reader.finish()
    #expect(values[0].2 == ["action"])
    #expect(values[1].2 == ["completed", "adult"])
    #expect(values[2].2 == ["2000.0", "2026.0"])
}

@Test func homeDecoderSkipsPromotionalBannersAndExtractsMangaEntries() throws {
    var writer = AidokuPostcardWriter()
    writer.write([0, 1, 2]) { writer, variant in
        writer.write(Optional("Section")) { $0.write($1) }
        writer.write(Optional<String>.none) { $0.write($1) }
        writer.writeVarUInt(UInt64(variant))
        if variant == 0 {
            writer.write(["banner"]) { writer, key in
                writeHomeLink(mangaKey: key, to: &writer)
            }
            writer.write(Optional<Float>.none) { $0.write($1) }
            writer.write(Optional<Int32>.none) { $0.write($1) }
            writer.write(Optional<Int32>.none) { $0.write($1) }
        } else if variant == 1 {
            writer.write(["featured"]) { writer, key in writeFixtureManga(key: key, to: &writer) }
            writer.write(Optional<Float>.none) { $0.write($1) }
        } else {
            writer.write(["linked"]) { writer, key in
                writeHomeLink(mangaKey: key, title: "Linked Manga", imageURL: "https://example.com/linked.jpg", to: &writer)
            }
            writer.write(Optional<Int32>.none) { $0.write($1) }
        }
    }
    let entries = try AidokuPostcardModels.decodeHomeManga(writer.data)
    #expect(entries.map(\.key) == ["featured", "linked"])
    #expect(entries.last?.title == "Linked Manga")
    #expect(entries.last?.coverURL == "https://example.com/linked.jpg")
}

@Test func staticFiltersAndSettingsCoverSupportedKinds() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let filters = Data(#"""
    [
      {"type":"text","id":"query","title":"Query","placeholder":"Title"},
      {"type":"check","id":"adult","title":"Adult","canExclude":true,"default":false},
      {"type":"select","id":"genre","title":"Genre","options":["A","B"],"ids":["a","b"],"default":"b"},
      {"type":"multi-select","id":"tags","title":"Tags","options":["X","Y"]},
      {"type":"sort","id":"sort","title":"Sort","options":["New","Old"],"canAscend":true},
      {"type":"range","id":"year","title":"Year","min":1990,"max":2030,"decimal":false}
    ]
    """#.utf8)
    try filters.write(to: temporary.appendingPathComponent("filters.json"))
    let settings = Data(#"""
    [
      {"type":"group","title":"Account","items":[
        {"type":"switch","key":"enabled","title":"Enabled","default":true},
        {"type":"text","key":"token","title":"Token","secure":true,"default":""},
        {"type":"select","key":"quality","title":"Quality","values":["low","high"],"titles":["Low","High"],"default":"high"},
        {"type":"multi-select","key":"contentRating","title":"Content Rating","values":["safe","suggestive","erotica"],"default":["safe","suggestive"]},
        {"type":"stepper","key":"count","title":"Count","minimumValue":1,"maximumValue":10,"stepValue":1,"default":3},
        {"type":"editable-list","key":"blockedUUIDs","title":"Blocked Groups","default":["one","two"]},
        {"type":"login","key":"account","title":"Login","method":"web","url":"https://example.invalid/login","localStorageKeys":["token"]}
      ]}
    ]
    """#.utf8)
    try settings.write(to: temporary.appendingPathComponent("settings.json"))

    #expect(try AidokuSourceMetadata.filters(in: temporary).count == 6)
    let decodedFilters = try AidokuSourceMetadata.filters(in: temporary)
    #expect(decodedFilters.contains {
        if case .select(_, _, _, let values, let defaultValue) = $0 {
            values == ["a", "b"] && defaultValue == "b"
        } else { false }
    })
    let decodedSettings = try AidokuSourceMetadata.settings(in: temporary)
    #expect(decodedSettings.count == 8)
    #expect(decodedSettings.contains { if case .login = $0 { true } else { false } })

    let defaults = try AidokuSourceMetadata.defaultValues(in: temporary)
    var ratings = AidokuPostcardReader(data: try #require(defaults["contentRating"]))
    #expect(try ratings.readArray { try $0.readString() } == ["safe", "suggestive"])
    try ratings.finish()
    var blocked = AidokuPostcardReader(data: try #require(defaults["blockedUUIDs"]))
    #expect(try blocked.readArray { try $0.readString() } == ["one", "two"])
    try blocked.finish()
    var quality = AidokuPostcardReader(data: try #require(defaults["quality"]))
    #expect(try quality.readString() == "high")
    try quality.finish()
}

private func validationFixtureWasm(
    initialMemoryPages: UInt64 = 1,
    maximumMemoryPages: UInt64? = 1
) -> Data {
    var bytes: [UInt8] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    var memory: [UInt8] = [1, maximumMemoryPages == nil ? 0 : 1]
    memory.append(contentsOf: encodeULEB(initialMemoryPages))
    if let maximumMemoryPages { memory.append(contentsOf: encodeULEB(maximumMemoryPages)) }
    appendSection(5, payload: memory, to: &bytes)
    let names = ["memory", "start", "free_result", "get_search_manga_list", "get_manga_update", "get_page_list"]
    var exports: [UInt8] = [UInt8(names.count)]
    for (index, name) in names.enumerated() {
        let nameBytes = Array(name.utf8)
        exports.append(UInt8(nameBytes.count))
        exports.append(contentsOf: nameBytes)
        exports.append(index == 0 ? 2 : 0)
        exports.append(UInt8(max(0, index - 1)))
    }
    appendSection(7, payload: exports, to: &bytes)
    return Data(bytes)
}

private func executableFixtureWasm() -> Data {
    var bytes: [UInt8] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    var types: [UInt8] = [5]
    types += [0x60, 0, 0]
    types += [0x60, 1, 0x7f, 0]
    types += [0x60, 3, 0x7f, 0x7f, 0x7f, 1, 0x7f]
    types += [0x60, 2, 0x7f, 0x7f, 1, 0x7f]
    types += [0x60, 0, 1, 0x7f]
    appendSection(1, payload: types, to: &bytes)
    appendSection(3, payload: [6, 0, 1, 2, 3, 3, 4], to: &bytes)
    appendSection(5, payload: [1, 1, 1, 1], to: &bytes)

    let exports: [(String, UInt8, UInt8)] = [
        ("memory", 2, 0), ("start", 0, 0), ("free_result", 0, 1),
        ("get_search_manga_list", 0, 2), ("get_manga_update", 0, 3),
        ("get_page_list", 0, 4), ("infinite_loop", 0, 5),
    ]
    var exportPayload: [UInt8] = [UInt8(exports.count)]
    for (name, kind, index) in exports {
        exportPayload.append(UInt8(name.utf8.count))
        exportPayload.append(contentsOf: name.utf8)
        exportPayload += [kind, index]
    }
    appendSection(7, payload: exportPayload, to: &bytes)

    let returnFixturePointer: [UInt8] = [0, 0x41, 0x80, 0x08, 0x0b]
    let returnZero: [UInt8] = [0, 0x41, 0, 0x0b]
    let infiniteLoop: [UInt8] = [0, 0x03, 0x7f, 0x41, 0, 0x0c, 0, 0x0b, 0x0b]
    let bodies: [[UInt8]] = [[0, 0x0b], [0, 0x0b], returnFixturePointer, returnZero, returnZero, infiniteLoop]
    var code: [UInt8] = [UInt8(bodies.count)]
    for body in bodies { code.append(UInt8(body.count)); code += body }
    appendSection(10, payload: code, to: &bytes)

    let resultBytes: [UInt8] = [10, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var data: [UInt8] = [1, 0, 0x41, 0x80, 0x08, 0x0b, UInt8(resultBytes.count)]
    data += resultBytes
    appendSection(11, payload: data, to: &bytes)
    return Data(bytes)
}

private func writeHomeLink(
    mangaKey: String,
    title: String = "",
    imageURL: String? = nil,
    to writer: inout AidokuPostcardWriter
) {
    writer.write(title)
    writer.write(Optional<String>.none) { $0.write($1) }
    writer.write(imageURL) { $0.write($1) }
    writer.write(true)
    writer.writeVarUInt(2)
    writeFixtureManga(key: mangaKey, title: "", to: &writer)
}

private func writeFixtureManga(
    key: String,
    title: String? = nil,
    to writer: inout AidokuPostcardWriter
) {
    writer.write(key)
    writer.write(title ?? key.capitalized)
    writer.write(Optional<String>.none) { $0.write($1) }
    writer.write(Optional<[String]>.none) { writer, values in writer.write(values) { $0.write($1) } }
    writer.write(Optional<[String]>.none) { writer, values in writer.write(values) { $0.write($1) } }
    writer.write(Optional<String>.none) { $0.write($1) }
    writer.write(Optional<String>.none) { $0.write($1) }
    writer.write(Optional<[String]>.none) { writer, values in writer.write(values) { $0.write($1) } }
    writer.write(UInt8(0))
    writer.write(UInt8(0))
    writer.write(UInt8(0))
    writer.write(UInt8(0))
    writer.write(Optional<Int64>.none) { $0.write($1) }
    writer.write(Optional<[Int]>.none) { writer, values in writer.write(values) { $0.write(Int32($1)) } }
}

private actor InvocationOrderRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}

private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}

private func appendSection(_ id: UInt8, payload: [UInt8], to bytes: inout [UInt8]) {
    precondition(payload.count < 128)
    bytes.append(id)
    bytes.append(UInt8(payload.count))
    bytes.append(contentsOf: payload)
}

private func encodeULEB(_ value: UInt64) -> [UInt8] {
    var value = value
    var output: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value != 0 { byte |= 0x80 }
        output.append(byte)
    } while value != 0
    return output
}
