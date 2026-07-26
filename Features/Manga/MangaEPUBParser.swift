import Foundation

nonisolated enum MangaEPUBParserError: Error {
    case invalidContainer
    case invalidPackage
}

nonisolated struct MangaEPUBResource: Equatable, Sendable {
    let id: String
    let path: String
    let mediaType: String
}

nonisolated struct MangaEPUBPackage: Equatable, Sendable {
    let packagePath: String
    let resources: [String: MangaEPUBResource]
    let spineItemIDs: [String]

    func orderedImagePaths(
        documentData: (String) throws -> Data?
    ) throws -> [String] {
        var paths: [String] = []
        for itemID in spineItemIDs {
            guard let resource = resources[itemID] else { continue }
            if MangaMediaTypes.isImagePath(resource.path),
               resource.mediaType.lowercased().hasPrefix("image/"),
               resource.path.pathExtension.lowercased() != "svg" {
                paths.append(resource.path)
                continue
            }
            guard let data = try documentData(resource.path) else { continue }
            let references = try MangaEPUBParser.imageReferences(in: data)
            paths.append(contentsOf: references.compactMap {
                MangaEPUBParser.resolve(reference: $0, relativeTo: resource.path)
            }.filter(MangaMediaTypes.isImagePath))
        }

        if paths.isEmpty {
            paths = resources.values
                .map(\.path)
                .filter(MangaMediaTypes.isImagePath)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return paths
    }
}

nonisolated enum MangaEPUBParser {
    static func packagePath(in containerData: Data) throws -> String {
        let delegate = ContainerDelegate()
        try parse(containerData, delegate: delegate)
        guard let path = delegate.packagePath,
              let resolved = resolve(reference: path, relativeTo: "") else {
            throw MangaEPUBParserError.invalidContainer
        }
        return resolved
    }

    static func package(
        at packagePath: String,
        data: Data
    ) throws -> MangaEPUBPackage {
        let delegate = PackageDelegate(packagePath: packagePath)
        try parse(data, delegate: delegate)
        guard !delegate.resources.isEmpty, !delegate.spineItemIDs.isEmpty else {
            throw MangaEPUBParserError.invalidPackage
        }
        return MangaEPUBPackage(
            packagePath: packagePath,
            resources: delegate.resources,
            spineItemIDs: delegate.spineItemIDs
        )
    }

    static func imageReferences(in documentData: Data) throws -> [String] {
        let delegate = ContentDocumentDelegate()
        try parse(documentData, delegate: delegate)
        return delegate.references
    }

    static func resolve(reference: String, relativeTo documentPath: String) -> String? {
        let withoutFragment = reference
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? reference
        let withoutQuery = withoutFragment
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutFragment
        let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.lowercased().hasPrefix("data:"),
              !trimmed.contains("://") else {
            return nil
        }

        let base = NSString(string: documentPath).deletingLastPathComponent
        let combined = NSString(string: base)
            .appendingPathComponent(trimmed)
            .replacingOccurrences(of: "\\", with: "/")
        var components: [Substring] = []
        for component in combined.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    private static func parse(
        _ data: Data,
        delegate: XMLParserDelegate
    ) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw parser.parserError ?? MangaEPUBParserError.invalidPackage
        }
    }
}

nonisolated private final class ContainerDelegate: NSObject, XMLParserDelegate {
    var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard packagePath == nil, elementName.lowercased() == "rootfile" else { return }
        packagePath = attributeDict.localValue(named: "full-path")
    }
}

nonisolated private final class PackageDelegate: NSObject, XMLParserDelegate {
    private let packagePath: String
    var resources: [String: MangaEPUBResource] = [:]
    var spineItemIDs: [String] = []

    init(packagePath: String) {
        self.packagePath = packagePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "item":
            guard let id = attributeDict.localValue(named: "id"),
                  let href = attributeDict.localValue(named: "href"),
                  let mediaType = attributeDict.localValue(named: "media-type"),
                  let path = MangaEPUBParser.resolve(
                    reference: href,
                    relativeTo: packagePath
                  ) else {
                return
            }
            resources[id] = MangaEPUBResource(
                id: id,
                path: path,
                mediaType: mediaType
            )
        case "itemref":
            guard attributeDict.localValue(named: "linear")?.lowercased() != "no",
                  let idref = attributeDict.localValue(named: "idref") else {
                return
            }
            spineItemIDs.append(idref)
        default:
            break
        }
    }
}

nonisolated private final class ContentDocumentDelegate: NSObject, XMLParserDelegate {
    var references: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "img":
            append(attributeDict.localValue(named: "src"))
        case "image":
            append(attributeDict.localValue(named: "href"))
        case "object":
            append(attributeDict.localValue(named: "data"))
        default:
            break
        }
    }

    private func append(_ reference: String?) {
        guard let reference, !reference.isEmpty else { return }
        references.append(reference)
    }
}

nonisolated private extension Dictionary where Key == String, Value == String {
    func localValue(named name: String) -> String? {
        if let value = self[name] {
            return value
        }
        return first { key, _ in
            key.split(separator: ":").last?.lowercased() == name.lowercased()
        }?.value
    }
}

nonisolated private extension String {
    var pathExtension: String {
        URL(fileURLWithPath: self).pathExtension
    }
}
