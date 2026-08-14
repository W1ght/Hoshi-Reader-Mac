import AppKit
import Foundation
import Testing
import ZIPFoundation
@testable import AidokuRuntime

private struct AuditStep: Codable, Sendable {
    var state: String
    var count: Int?
    var hasNextPage: Bool?
    var message: String?

    static func passed(count: Int? = nil, hasNextPage: Bool? = nil) -> Self {
        .init(state: "passed", count: count, hasNextPage: hasNextPage, message: nil)
    }

    static func skipped(_ message: String) -> Self {
        .init(state: "skipped", count: nil, hasNextPage: nil, message: message)
    }

    static func failed(_ error: Error) -> Self {
        .init(state: "failed", count: nil, hasNextPage: nil, message: auditError(error))
    }

    static func failed(_ message: String) -> Self {
        .init(state: "failed", count: nil, hasNextPage: nil, message: message)
    }

    static func missing(_ message: String) -> Self {
        .init(state: "missing", count: nil, hasNextPage: nil, message: message)
    }
}

private struct AuditListing: Codable, Sendable {
    let id: String
    let name: String
    let result: AuditStep
    let secondPage: AuditStep?
}

private struct AuditSecondPageResult: Sendable {
    let step: AuditStep?
    let entries: [AidokuManga]
}

private struct AuditLanguageSelection: Codable, Sendable {
    let type: AidokuLanguageSelectType
    let supportedLanguages: [String]
    let selectedLanguages: [String]
}

private struct AuditRuntimeDefaults: Sendable {
    let values: [String: Data]
    let languageSelection: AuditLanguageSelection?
}

private struct AuditBrowseCover: Codable, Sendable {
    let mangaKey: String
    let title: String
    let advertisedURL: String?
    let result: AuditStep
}

private struct AuditBrowseCoverCollection: Codable, Sendable {
    let limit: Int
    let sampled: Int
    let passed: Int
    let failed: Int
    let missing: Int
    let results: [AuditBrowseCover]
}

private struct AidokuSourceAudit: Codable, Sendable {
    let id: String
    var name: String
    var version: Int
    var packageValidation: AuditStep
    var installation: AuditStep
    var languageSelection: AuditLanguageSelection?
    var home: AuditStep
    var listingsDiscovery: AuditStep
    var listings: [AuditListing]
    var search: AuditStep
    var searchSecondPage: AuditStep?
    var details: AuditStep
    var cover: AuditStep
    var browseCovers: AuditBrowseCoverCollection?
    var chapter: AuditStep
    var page: AuditStep

    init(id: String) {
        self.id = id
        name = id
        version = 0
        packageValidation = .skipped("not attempted")
        installation = .skipped("not attempted")
        languageSelection = nil
        home = .skipped("not attempted")
        listingsDiscovery = .skipped("not attempted")
        listings = []
        search = .skipped("not attempted")
        searchSecondPage = nil
        details = .skipped("no browse candidate")
        cover = .skipped("no detailed manga")
        browseCovers = nil
        chapter = .skipped("no detailed manga")
        page = .skipped("no readable chapter")
    }

    var openedRepresentativePage: Bool { page.state == "passed" }
}

private actor AuditReportWriter {
    private var results: [String: AidokuSourceAudit] = [:]
    private let url: URL

    init(url: URL) { self.url = url }

    func record(_ result: AidokuSourceAudit) throws {
        results[result.id] = result
        let output = results.values.sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(output).write(to: url, options: .atomic)
        let completed = output.count
        let opened = output.lazy.filter(\.openedRepresentativePage).count
        let coverCounts = result.browseCovers.map {
            " covers=\($0.passed)/\($0.failed)/\($0.missing)"
        } ?? ""
        FileHandle.standardError.write(Data(
            "AUDIT \(completed): \(result.id) page=\(result.page.state) opened=\(opened)\(coverCounts)\n".utf8
        ))
    }
}

@Test func optionalAidokuRepositoryLiveAudit() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let packageDirectory = environment["AIDOKU_REPOSITORY_AUDIT_PACKAGES"],
          let reportPath = environment["AIDOKU_REPOSITORY_AUDIT_REPORT"] else {
        return
    }
    var packages = try FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: packageDirectory, isDirectory: true),
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "aix" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    if let sourceID = environment["AIDOKU_REPOSITORY_AUDIT_SOURCE_ID"] {
        packages = packages.filter { $0.deletingPathExtension().lastPathComponent == sourceID }
    }
    #expect(!packages.isEmpty)
    let writer = AuditReportWriter(url: URL(fileURLWithPath: reportPath))
    let parallelism = max(1, min(Int(environment["AIDOKU_REPOSITORY_AUDIT_PARALLELISM"] ?? "4") ?? 4, 8))
    let coverLimit = max(1, min(Int(environment["AIDOKU_REPOSITORY_AUDIT_COVER_LIMIT"] ?? "20") ?? 20, 100))
    let preferredLanguageIdentifiers = auditPreferredLanguageIdentifiers(environment: environment)

    for batchStart in stride(from: 0, to: packages.count, by: parallelism) {
        let batch = Array(packages[batchStart..<min(batchStart + parallelism, packages.count)])
        await withTaskGroup(of: AidokuSourceAudit.self) { group in
            for package in batch {
                group.addTask {
                    await auditAidokuSource(
                        package: package,
                        coverLimit: coverLimit,
                        preferredLanguageIdentifiers: preferredLanguageIdentifiers
                    )
                }
            }
            for await result in group {
                try? await writer.record(result)
            }
        }
    }
}

private func auditAidokuSource(
    package: URL,
    coverLimit: Int,
    preferredLanguageIdentifiers: [String]
) async -> AidokuSourceAudit {
    let id = package.deletingPathExtension().lastPathComponent
    let directMediaSourceIDs = auditDirectMediaSourceIDs(
        environment: ProcessInfo.processInfo.environment
    )
    let usesSystemProxy = !directMediaSourceIDs.contains(id)
    func progress(_ step: String) {
        FileHandle.standardError.write(Data("AUDIT-STEP \(id) \(step)\n".utf8))
    }
    var result = AidokuSourceAudit(id: id)
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("Niratan-Aidoku-Audit-\(id)-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    do {
        progress("validate")
        let validated = try AidokuPackageValidator.validate(archiveURL: package, expectedSourceID: id)
        result.name = validated.manifest.info.name
        result.version = validated.manifest.info.version
        result.packageValidation = .passed()
    } catch {
        result.packageValidation = .failed(error)
        return result
    }

    let installed: AidokuInstalledSource
    do {
        progress("install")
        let installer = AidokuPackageInstaller(rootDirectory: temporary)
        installed = try await installer.install(archiveURL: package, expectedSourceID: id)
        result.installation = .passed()
    } catch {
        result.installation = .failed(error)
        return result
    }

    let runtime: AidokuSourceRuntime
    do {
        progress("runtime")
        let runtimeDefaults = auditRuntimeDefaults(
            manifest: installed.manifest,
            preferredLanguageIdentifiers: preferredLanguageIdentifiers
        )
        result.languageSelection = runtimeDefaults.languageSelection
        runtime = try AidokuSourceRuntime(configuration: .init(
            sourceDirectory: installed.directory,
            defaults: runtimeDefaults.values
        ))
    } catch {
        result.installation = .failed(error)
        return result
    }

    var candidates: [AidokuManga] = []
    do {
        progress("home")
        let entries = try await runtime.homeManga()
        result.home = .passed(count: entries.count)
        appendUnique(entries, to: &candidates)
    } catch {
        result.home = .failed(error)
    }

    do {
        progress("listings")
        let listings = try await runtime.listings()
        result.listingsDiscovery = .passed(count: listings.count)
        for listing in listings {
            do {
                progress("listing:\(listing.id):page:1")
                let page = try await runtime.mangaList(listing: listing, page: 1)
                let secondPage = await auditSecondPageIfNeeded(hasNextPage: page.hasNextPage) { requestedPage in
                    progress("listing:\(listing.id):page:\(requestedPage)")
                    return try await runtime.mangaList(listing: listing, page: requestedPage)
                }
                result.listings.append(.init(
                    id: listing.id,
                    name: listing.name,
                    result: .passed(count: page.entries.count, hasNextPage: page.hasNextPage),
                    secondPage: secondPage.step
                ))
                appendUnique(page.entries, to: &candidates)
                appendUnique(secondPage.entries, to: &candidates)
            } catch {
                result.listings.append(.init(
                    id: listing.id,
                    name: listing.name,
                    result: .failed(error),
                    secondPage: nil
                ))
            }
        }
    } catch {
        result.listingsDiscovery = .failed(error)
    }

    do {
        progress("search:page:1")
        let page = try await runtime.search(query: nil, page: 1)
        result.search = .passed(count: page.entries.count, hasNextPage: page.hasNextPage)
        let secondPage = await auditSecondPageIfNeeded(hasNextPage: page.hasNextPage) { requestedPage in
            progress("search:page:\(requestedPage)")
            return try await runtime.search(query: nil, page: requestedPage)
        }
        result.searchSecondPage = secondPage.step
        appendUnique(page.entries, to: &candidates)
        appendUnique(secondPage.entries, to: &candidates)
    } catch {
        result.search = .failed(error)
    }

    let browseCoverCandidates = Array(candidates.prefix(coverLimit))
    let coverLoader = AidokuCoverLoader(
        cacheDirectory: temporary.appendingPathComponent("cover-audit-cache", isDirectory: true)
    )
    var browseCovers: [AuditBrowseCover] = []
    browseCovers.reserveCapacity(browseCoverCandidates.count)
    for (index, candidate) in browseCoverCandidates.enumerated() {
        progress("cover:\(index + 1):\(candidate.key)")
        let advertisedURL = candidate.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let coverResult: AuditStep
        if advertisedURL?.isEmpty != false {
            coverResult = .missing("browse candidate returned no cover")
        } else {
            coverResult = await auditBrowseCover(
                candidate,
                sourceID: id,
                sourceVersion: result.version,
                runtime: runtime,
                loader: coverLoader,
                usesSystemProxy: usesSystemProxy
            )
        }
        browseCovers.append(.init(
            mangaKey: candidate.key,
            title: candidate.title,
            advertisedURL: advertisedURL,
            result: coverResult
        ))
    }
    result.browseCovers = .init(
        limit: coverLimit,
        sampled: browseCovers.count,
        passed: browseCovers.lazy.filter { $0.result.state == "passed" }.count,
        failed: browseCovers.lazy.filter { $0.result.state == "failed" }.count,
        missing: browseCovers.lazy.filter { $0.result.state == "missing" }.count,
        results: browseCovers
    )

    var detailed: AidokuManga?
    var detailErrors: [String] = []
    let requestedMangaKey = ProcessInfo.processInfo.environment["AIDOKU_REPOSITORY_AUDIT_MANGA_KEY"]
    let detailCandidates = requestedMangaKey.map { key in candidates.filter { $0.key == key } } ?? Array(candidates.prefix(5))
    for candidate in detailCandidates {
        do {
            progress("details:\(candidate.key)")
            let value = try await runtime.mangaDetails(candidate, chapters: true)
            if ProcessInfo.processInfo.environment["AIDOKU_REPOSITORY_AUDIT_REPEAT_DETAILS"] == "1" {
                progress("details-repeat:\(candidate.key)")
                _ = try await runtime.mangaDetails(candidate, chapters: true)
            }
            if value.chapters?.isEmpty == false {
                detailed = value
                break
            }
            detailErrors.append("returned no chapters")
        } catch {
            detailErrors.append(auditError(error))
        }
    }
    if let detailed {
        result.details = .passed()
        result.chapter = .passed(count: detailed.chapters?.count ?? 0)
        result.cover = await auditCover(
            detailed.coverURL,
            runtime: runtime,
            usesSystemProxy: usesSystemProxy
        )
        if let chapter = detailed.chapters?.first(where: { !$0.locked }) {
            do {
                progress("pages:\(chapter.key)")
                let pages = try await runtime.pages(manga: detailed, chapter: chapter)
                guard !pages.isEmpty else {
                    result.page = .failed("source returned an empty page list")
                    return result
                }
                var pageErrors: [String] = []
                for page in pages.prefix(3) {
                    do {
                        progress("page:\(page.index)")
                        try await auditPage(
                            page,
                            runtime: runtime,
                            usesSystemProxy: usesSystemProxy
                        )
                        result.page = .passed(count: pages.count)
                        return result
                    } catch {
                        pageErrors.append(auditError(error))
                    }
                }
                result.page = .failed(pageErrors.joined(separator: " | "))
            } catch {
                result.page = .failed(error)
            }
        } else {
            result.page = .skipped("all returned chapters are locked")
        }
    } else if candidates.isEmpty {
        result.details = .skipped("home, listings, and browse search returned no manga")
    } else {
        result.details = .failed(detailErrors.isEmpty ? "no candidate returned chapters" : detailErrors.joined(separator: " | "))
    }
    return result
}

private func auditPreferredLanguageIdentifiers(environment: [String: String]) -> [String] {
    let fallback = ["ja", "en", "zh-Hans", "zh-Hant"]
    guard let value = environment["AIDOKU_REPOSITORY_AUDIT_PREFERRED_LANGUAGES"] else {
        return fallback
    }
    let identifiers = value.split(separator: ",").compactMap { value -> String? in
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? nil : identifier
    }
    return identifiers.isEmpty ? fallback : identifiers
}

private func auditDirectMediaSourceIDs(environment: [String: String]) -> Set<String> {
    let value = environment["AIDOKU_REPOSITORY_AUDIT_DIRECT_MEDIA_SOURCE_IDS"]
        ?? environment["AIDOKU_REPOSITORY_AUDIT_DIRECT_COVER_SOURCE_IDS"]
        ?? ""
    return Set(value.split(separator: ",").compactMap { value -> String? in
        let sourceID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceID.isEmpty ? nil : sourceID
    })
}

private func auditRuntimeDefaults(
    manifest: AidokuSourceManifest,
    preferredLanguageIdentifiers: [String]
) -> AuditRuntimeDefaults {
    guard let type = manifest.resolvedLanguageSelectType else {
        return .init(values: [:], languageSelection: nil)
    }
    let supportedLanguages = AidokuLanguageDefaults.supportedLanguages(
        manifest.info.languages ?? []
    )
    let selectedLanguages = AidokuLanguageDefaults.normalizedSelection(
        supportedLanguages: supportedLanguages,
        selectedLanguages: nil,
        preferredLanguageIdentifiers: preferredLanguageIdentifiers,
        type: type
    )
    return .init(
        values: AidokuLanguageDefaults.encodedDefaults(
            type: type,
            selectedLanguages: selectedLanguages
        ),
        languageSelection: .init(
            type: type,
            supportedLanguages: supportedLanguages,
            selectedLanguages: selectedLanguages
        )
    )
}

private func auditSecondPageIfNeeded(
    hasNextPage: Bool,
    fetch: (Int) async throws -> AidokuMangaPage
) async -> AuditSecondPageResult {
    guard hasNextPage else {
        return .init(step: nil, entries: [])
    }
    do {
        let page = try await fetch(2)
        return .init(
            step: .passed(count: page.entries.count, hasNextPage: page.hasNextPage),
            entries: page.entries
        )
    } catch {
        return .init(step: .failed(error), entries: [])
    }
}

private actor AuditSecondPageRecorder {
    private var pages: [Int] = []

    func record(_ page: Int) {
        pages.append(page)
    }

    func snapshot() -> [Int] {
        pages
    }
}

@Test func aidokuRepositoryAuditRequestsSecondPageOnlyWhenAdvertised() async {
    let recorder = AuditSecondPageRecorder()
    let skipped = await auditSecondPageIfNeeded(hasNextPage: false) { page in
        await recorder.record(page)
        return AidokuMangaPage(entries: [], hasNextPage: false)
    }
    let callsAfterSkip = await recorder.snapshot()
    #expect(skipped.step == nil)
    #expect(skipped.entries.isEmpty)
    #expect(callsAfterSkip.isEmpty)

    let requested = await auditSecondPageIfNeeded(hasNextPage: true) { page in
        await recorder.record(page)
        return AidokuMangaPage(entries: [], hasNextPage: true)
    }
    let callsAfterRequest = await recorder.snapshot()
    #expect(requested.step?.state == "passed")
    #expect(requested.step?.count == 0)
    #expect(requested.step?.hasNextPage == true)
    #expect(requested.entries.isEmpty)
    #expect(callsAfterRequest == [2])
}

@Test func aidokuRepositoryAuditReportsSecondPagesSeparately() throws {
    let listing = AuditListing(
        id: "popular",
        name: "Popular",
        result: .passed(count: 20, hasNextPage: true),
        secondPage: .passed(count: 15, hasNextPage: false)
    )
    var source = AidokuSourceAudit(id: "fixture.pagination")
    source.listings = [listing]
    source.search = .passed(count: 25, hasNextPage: true)
    source.searchSecondPage = .failed("fixture page-two failure")

    let data = try JSONEncoder().encode(source)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let listings = try #require(object["listings"] as? [[String: Any]])
    let encodedListing = try #require(listings.first)
    let listingPageOne = try #require(encodedListing["result"] as? [String: Any])
    let listingPageTwo = try #require(encodedListing["secondPage"] as? [String: Any])
    let searchPageOne = try #require(object["search"] as? [String: Any])
    let searchPageTwo = try #require(object["searchSecondPage"] as? [String: Any])

    #expect(listingPageOne["count"] as? Int == 20)
    #expect(listingPageTwo["count"] as? Int == 15)
    #expect(searchPageOne["count"] as? Int == 25)
    #expect(searchPageTwo["state"] as? String == "failed")
    #expect(searchPageTwo["message"] as? String == "fixture page-two failure")
}

@Test func aidokuRepositoryAuditInjectsManifestResolvedLanguageDefaults() throws {
    let manifest = AidokuSourceManifest(
        info: .init(
            id: "multi.fixture",
            name: "Fixture",
            version: 1,
            languages: ["fr", "en", "ja", "zh-Hant"]
        ),
        config: .init(languageSelectType: .multiple)
    )
    let runtimeDefaults = auditRuntimeDefaults(
        manifest: manifest,
        preferredLanguageIdentifiers: auditPreferredLanguageIdentifiers(environment: [:])
    )

    #expect(runtimeDefaults.languageSelection?.type == .multiple)
    #expect(runtimeDefaults.languageSelection?.selectedLanguages == ["en", "ja", "zh-Hant"])
    #expect(runtimeDefaults.values["language"] == nil)
    var reader = AidokuPostcardReader(data: try #require(runtimeDefaults.values["languages"]))
    #expect(try reader.readArray { try $0.readString() } == ["en", "ja", "zh-Hant"])
    try reader.finish()
    #expect(auditPreferredLanguageIdentifiers(environment: [
        "AIDOKU_REPOSITORY_AUDIT_PREFERRED_LANGUAGES": "de, fr"
    ]) == ["de", "fr"])
}

@Test func aidokuRepositoryAuditUsesOneExplicitDirectMediaSourceSet() {
    let sourceIDs = auditDirectMediaSourceIDs(environment: [
        "AIDOKU_REPOSITORY_AUDIT_DIRECT_MEDIA_SOURCE_IDS": " zh.baozimanhua, en.tcbscans "
    ])
    #expect(sourceIDs == ["zh.baozimanhua", "en.tcbscans"])
    #expect(!sourceIDs.contains("ja.rawkuro"))

    let legacySourceIDs = auditDirectMediaSourceIDs(environment: [
        "AIDOKU_REPOSITORY_AUDIT_DIRECT_COVER_SOURCE_IDS": "zh.baozimanhua"
    ])
    #expect(legacySourceIDs == ["zh.baozimanhua"])
}

private func appendUnique(_ entries: [AidokuManga], to candidates: inout [AidokuManga]) {
    var keys = Set(candidates.map(\.key))
    for entry in entries where keys.insert(entry.key).inserted {
        candidates.append(entry)
    }
}

private func auditBrowseCover(
    _ manga: AidokuManga,
    sourceID: String,
    sourceVersion: Int,
    runtime: AidokuSourceRuntime,
    loader: AidokuCoverLoader,
    usesSystemProxy: Bool
) async -> AuditStep {
    do {
        let data = try await loader.data(
            sourceID: sourceID,
            sourceVersion: sourceVersion,
            manga: manga,
            runtime: runtime,
            usesSystemProxy: usesSystemProxy
        )
        guard let image = NSImage(data: data), image.size.width > 1, image.size.height > 1 else {
            return .failed("cover loader returned an undecodable or 1x1 image")
        }
        return .passed(count: data.count)
    } catch {
        return .failed(error)
    }
}

private func auditCover(
    _ value: String?,
    runtime: AidokuSourceRuntime,
    usesSystemProxy: Bool
) async -> AuditStep {
    guard let value, !value.isEmpty else { return .failed("details returned no cover") }
    do {
        let data: Data
        if value.hasPrefix("data:image/") {
            data = try decodeInlineImage(value)
        } else {
            let imageRequest = try await runtime.imageRequest(url: value, context: [:])
            let (downloaded, response) = try await download(
                imageRequest,
                maximumBytes: AidokuLimits.maximumImageBytes,
                usesSystemProxy: usesSystemProxy
            )
            guard (200..<300).contains(response.statusCode) else {
                return .failed("cover HTTP \(response.statusCode)")
            }
            data = downloaded
        }
        guard let image = NSImage(data: data), image.size.width > 1, image.size.height > 1 else {
            return .failed("cover is missing, undecodable, or a 1x1 placeholder")
        }
        return .passed(count: data.count)
    } catch {
        return .failed(error)
    }
}

private func auditPage(
    _ page: AidokuPage,
    runtime: AidokuSourceRuntime,
    usesSystemProxy: Bool
) async throws {
    let data: Data
    switch page.content {
    case .text(let text):
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AidokuRuntimeError.runtimeFailure("text page is empty")
        }
        return
    case .image(let image):
        data = image
    case .url(let value, let context):
        let imageRequest = try await runtime.imageRequest(url: value, context: context)
        let (downloaded, response) = try await download(
            imageRequest,
            maximumBytes: AidokuLimits.maximumImageBytes,
            usesSystemProxy: usesSystemProxy
        )
        guard (200..<300).contains(response.statusCode) else {
            throw AidokuRuntimeError.runtimeFailure("page HTTP \(response.statusCode)")
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, pair in
            values[String(describing: pair.key)] = String(describing: pair.value)
        }
        data = try await runtime.processPageImage(
            downloaded,
            statusCode: response.statusCode,
            responseHeaders: headers,
            request: imageRequest,
            context: context
        )
    case .zip(let value, let path):
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw AidokuRuntimeError.unsupportedURL
        }
        let (archiveData, response) = try await AidokuHTTPClient.data(
            for: URLRequest(url: url),
            maximumBytes: AidokuLimits.maximumArchiveBytes,
            usesSystemProxy: usesSystemProxy
        )
        guard (200..<300).contains(response.statusCode),
              let archive = try? Archive(data: archiveData, accessMode: .read),
              let entry = archive[path], entry.type == .file,
              entry.uncompressedSize <= UInt64(AidokuLimits.maximumImageBytes) else {
            throw AidokuRuntimeError.invalidArchive
        }
        var extracted = Data()
        _ = try archive.extract(entry) { chunk in
            guard extracted.count <= AidokuLimits.maximumImageBytes - chunk.count else {
                throw AidokuRuntimeError.responseTooLarge
            }
            extracted.append(chunk)
        }
        data = extracted
    }
    guard NSImage(data: data) != nil else {
        throw AidokuRuntimeError.runtimeFailure("page image is not decodable")
    }
}

private func download(
    _ imageRequest: AidokuImageRequest,
    maximumBytes: Int,
    usesSystemProxy: Bool
) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: imageRequest.url)
    imageRequest.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    return try await AidokuHTTPClient.data(
        for: request,
        maximumBytes: maximumBytes,
        usesSystemProxy: usesSystemProxy
    )
}

private func decodeInlineImage(_ value: String) throws -> Data {
    guard let comma = value.firstIndex(of: ","),
          value[..<comma].lowercased().contains(";base64"),
          let data = Data(base64Encoded: String(value[value.index(after: comma)...])) else {
        throw AidokuRuntimeError.runtimeFailure("invalid inline image")
    }
    return data
}

private func auditError(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}
