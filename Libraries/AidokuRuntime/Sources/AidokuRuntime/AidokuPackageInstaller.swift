import Foundation
import ZIPFoundation

public struct AidokuValidatedPackage: Sendable {
    public let archiveURL: URL
    public let manifest: AidokuSourceManifest
    public let paths: [String]

    public init(archiveURL: URL, manifest: AidokuSourceManifest, paths: [String]) {
        self.archiveURL = archiveURL
        self.manifest = manifest
        self.paths = paths
    }
}

public enum AidokuPackageValidator {
    public static func validate(
        archiveURL: URL,
        expectedSourceID: String? = nil
    ) throws -> AidokuValidatedPackage {
        let values = try archiveURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AidokuRuntimeError.invalidArchive
        }
        guard let fileSize = values.fileSize, fileSize <= AidokuLimits.maximumArchiveBytes else {
            throw AidokuRuntimeError.archiveTooLarge
        }
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw AidokuRuntimeError.invalidArchive
        }
        var totalExpanded = 0
        var paths: [String] = []
        var manifestData: Data?
        var wasmData: Data?
        for entry in archive {
            guard paths.count < AidokuLimits.maximumArchiveEntries else {
                throw AidokuRuntimeError.tooManyArchiveEntries
            }
            try validatePath(entry.path)
            guard entry.type != .symlink else {
                throw AidokuRuntimeError.symbolicLink(entry.path)
            }
            guard entry.uncompressedSize <= UInt64(Int.max - totalExpanded) else {
                throw AidokuRuntimeError.expandedArchiveTooLarge
            }
            totalExpanded += Int(entry.uncompressedSize)
            guard totalExpanded <= AidokuLimits.maximumExpandedBytes else {
                throw AidokuRuntimeError.expandedArchiveTooLarge
            }
            paths.append(entry.path)
            if entry.path == "Payload/source.json" {
                manifestData = try read(entry, from: archive, maximumBytes: AidokuLimits.maximumJSONBytes)
            } else if entry.path == "Payload/main.wasm" {
                wasmData = try read(entry, from: archive, maximumBytes: AidokuLimits.maximumExpandedBytes)
            }
        }
        guard let manifestData else { throw AidokuRuntimeError.missingPayload("source.json") }
        guard let wasmData else { throw AidokuRuntimeError.missingPayload("main.wasm") }
        let manifest: AidokuSourceManifest
        do {
            manifest = try JSONDecoder().decode(AidokuSourceManifest.self, from: manifestData)
        } catch {
            throw AidokuRuntimeError.invalidManifest
        }
        guard isSafeSourceID(manifest.info.id), manifest.info.version >= 0,
              !manifest.info.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AidokuRuntimeError.invalidSourceID
        }
        if let expectedSourceID, expectedSourceID != manifest.info.id {
            throw AidokuRuntimeError.sourceIDMismatch(expected: expectedSourceID, actual: manifest.info.id)
        }
        guard wasmData.starts(with: [0x00, 0x61, 0x73, 0x6d]), wasmData.count >= 8 else {
            throw AidokuRuntimeError.invalidWasm
        }
        let inspection = try AidokuWasmSanitizer.inspect(wasmData)
        let requiredExports: Set<String> = [
            "memory", "start", "free_result", "get_search_manga_list",
            "get_manga_update", "get_page_list",
        ]
        let missingExports = requiredExports.subtracting(inspection.exports)
        guard missingExports.isEmpty else {
            throw AidokuRuntimeError.incompatibleSource(
                "missing required exports: \(missingExports.sorted().joined(separator: ", "))"
            )
        }
        let allowedNamespaces: Set<String> = ["env", "std", "defaults", "net", "html", "js", "canvas"]
        let unsupportedImports = inspection.imports.filter { item in
            guard let namespace = item.split(separator: ".", maxSplits: 1).first else { return true }
            return !allowedNamespaces.contains(String(namespace))
        }
        guard unsupportedImports.isEmpty else {
            throw AidokuRuntimeError.incompatibleSource(
                "unsupported imports: \(unsupportedImports.sorted().joined(separator: ", "))"
            )
        }
        _ = try AidokuWasmSanitizer.restrictingLinearMemory(in: wasmData)
        return AidokuValidatedPackage(
            archiveURL: archiveURL,
            manifest: manifest,
            paths: paths
        )
    }

    public static func isSafeSourceID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200, value != ".", value != ".." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validatePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains("\0"),
              URL(fileURLWithPath: path).pathComponents.allSatisfy({ $0 != ".." }),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." }) else {
            throw AidokuRuntimeError.unsafeArchivePath(path)
        }
    }

    private static func read(
        _ entry: Entry,
        from archive: Archive,
        maximumBytes: Int
    ) throws -> Data {
        guard Int(entry.uncompressedSize) <= maximumBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        var output = Data()
        output.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
            guard output.count <= maximumBytes - chunk.count else {
                throw AidokuRuntimeError.responseTooLarge
            }
            output.append(chunk)
        }
        return output
    }
}

public actor AidokuPackageInstaller {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func install(
        archiveURL: URL,
        expectedSourceID: String? = nil,
        migrate: (@Sendable (_ old: AidokuSourceManifest, _ new: AidokuSourceManifest, _ stagedSource: URL) async throws -> Void)? = nil
    ) async throws -> AidokuInstalledSource {
        let package = try AidokuPackageValidator.validate(
            archiveURL: archiveURL,
            expectedSourceID: expectedSourceID
        )
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let destination = rootDirectory.appendingPathComponent(package.manifest.info.id, isDirectory: true)
        let staging = rootDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let backup = rootDirectory.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw AidokuRuntimeError.invalidArchive
        }
        for entry in archive {
            let relative = entry.path.removingPrefix("Payload/")
            guard relative != entry.path, !relative.isEmpty else { continue }
            let target = staging.appendingPathComponent(relative)
            guard target.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/") else {
                throw AidokuRuntimeError.unsafeArchivePath(entry.path)
            }
            if entry.type == .directory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                _ = try archive.extract(entry, to: target, skipCRC32: false)
            }
        }
        let installedManifestURL = staging.appendingPathComponent("source.json")
        let installedWasmURL = staging.appendingPathComponent("main.wasm")
        guard fileManager.fileExists(atPath: installedManifestURL.path),
              fileManager.fileExists(atPath: installedWasmURL.path) else {
            throw AidokuRuntimeError.invalidArchive
        }
        let oldManifest = try existingManifest(at: destination)
        if let oldManifest,
           let breakingVersion = package.manifest.config?.breakingChangeVersion,
           oldManifest.info.version < breakingVersion,
           let migrate {
            try await migrate(oldManifest, package.manifest, staging)
        }
        var movedOld = false
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
                movedOld = true
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if movedOld, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
        return AidokuInstalledSource(
            manifest: package.manifest,
            directory: destination,
            installedAt: Date()
        )
    }

    public func uninstall(sourceID: String) throws {
        guard AidokuPackageValidator.isSafeSourceID(sourceID) else {
            throw AidokuRuntimeError.invalidSourceID
        }
        let destination = rootDirectory.appendingPathComponent(sourceID, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }

    public func installedSources() throws -> [AidokuInstalledSource] {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory in
            guard AidokuPackageValidator.isSafeSourceID(directory.lastPathComponent),
                  let manifest = try existingManifest(at: directory) else { return nil }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return AidokuInstalledSource(
                manifest: manifest,
                directory: directory,
                installedAt: (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            )
        }.sorted { $0.manifest.info.name.localizedStandardCompare($1.manifest.info.name) == .orderedAscending }
    }

    private func existingManifest(at directory: URL) throws -> AidokuSourceManifest? {
        let url = directory.appendingPathComponent("source.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= AidokuLimits.maximumJSONBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return try JSONDecoder().decode(AidokuSourceManifest.self, from: data)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
