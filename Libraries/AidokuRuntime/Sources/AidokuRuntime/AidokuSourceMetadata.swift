import Foundation

public enum AidokuSourceMetadata {
    public static func filters(in sourceDirectory: URL) throws -> [AidokuFilter] {
        let url = sourceDirectory.appendingPathComponent("filters.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try boundedData(at: url)
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return try objects.compactMap(decodeFilter)
    }

    public static func settings(in sourceDirectory: URL) throws -> [AidokuSetting] {
        let url = sourceDirectory.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try boundedData(at: url)
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return try flattenSettings(objects)
    }

    /// Encodes the defaults registered by Aidoku before a source starts.
    /// Persisted user values are merged over these defaults by the runtime.
    public static func defaultValues(in sourceDirectory: URL) throws -> [String: Data] {
        try defaultValues(for: settings(in: sourceDirectory))
    }

    public static func defaultValues(for settings: [AidokuSetting]) -> [String: Data] {
        var values: [String: Data] = [:]
        for setting in settings {
            var writer = AidokuPostcardWriter()
            switch setting {
            case .header, .login:
                continue
            case .switchValue(let id, _, let defaultValue, _):
                writer.write(defaultValue)
                values[id] = writer.data
            case .select(let id, _, let options, _, let defaultValue):
                guard let value = defaultValue ?? options.first else { continue }
                writer.write(value)
                values[id] = writer.data
            case .multiSelect(let id, _, _, _, let defaultValues):
                guard let defaultValues else { continue }
                writer.write(defaultValues) { $0.write($1) }
                values[id] = writer.data
            case .segment(let id, _, _, let defaultIndex):
                guard let defaultIndex else { continue }
                writer.write(defaultIndex)
                values[id] = writer.data
            case .text(let id, _, let defaultValue, _):
                guard let defaultValue else { continue }
                writer.write(defaultValue)
                values[id] = writer.data
            case .stepper(let id, _, let defaultValue, _, _, _):
                guard let defaultValue else { continue }
                writer.write(defaultValue)
                values[id] = writer.data
            case .editableList(let id, _, _, let defaultValues):
                guard let defaultValues else { continue }
                writer.write(defaultValues) { $0.write($1) }
                values[id] = writer.data
            }
        }
        return values
    }

    static func decodeFilters(_ data: Data) throws -> [AidokuFilter] {
        var reader = AidokuPostcardReader(data: data)
        let filters = try reader.readArray { reader -> AidokuFilter in
            let id = try reader.readOptional { try $0.readString() }
            let title = try reader.readOptional { try $0.readString() } ?? ""
            _ = try reader.readOptional { try $0.readBool() }
            let type = try reader.readString()
            let resolvedID = id ?? (!title.isEmpty ? title : type)
            switch type {
            case "text":
                return .text(id: resolvedID, title: title, placeholder: try reader.readOptional { try $0.readString() })
            case "sort":
                let canAscend = try reader.readOptional { try $0.readBool() } ?? true
                let options = try reader.readArray { try $0.readString() }
                let defaultValue = try reader.readOptional { reader in
                    (try reader.readInt32(), try reader.readBool())
                }
                return .sort(id: resolvedID, title: title, options: options, canAscend: canAscend && defaultValue?.1 != false)
            case "check":
                _ = try reader.readOptional { try $0.readString() }
                let canExclude = try reader.readOptional { try $0.readBool() } ?? false
                let value = try reader.readOptional { try $0.readBool() }.map { $0 ? 1 : 0 } ?? 0
                return .check(id: resolvedID, title: title, canExclude: canExclude, defaultValue: value)
            case "select":
                _ = try reader.readOptional { try $0.readBool() }
                _ = try reader.readOptional { try $0.readBool() }
                let options = try reader.readArray { try $0.readString() }
                let ids = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? options
                let defaultValue = try reader.readOptional { try $0.readString() }
                return .select(id: resolvedID, title: title, options: options, values: ids, defaultValue: defaultValue)
            case "multi-select":
                _ = try reader.readOptional { try $0.readBool() }
                _ = try reader.readOptional { try $0.readBool() }
                _ = try reader.readOptional { try $0.readBool() }
                let options = try reader.readArray { try $0.readString() }
                let ids = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? options
                _ = try reader.readOptional { try $0.readArray { try $0.readString() } }
                _ = try reader.readOptional { try $0.readArray { try $0.readString() } }
                return .multiSelect(id: resolvedID, title: title, options: options, values: ids)
            case "note":
                return .header(id: resolvedID, title: try reader.readString())
            case "range":
                let minimum = try reader.readOptional { try $0.readFloat() }
                let maximum = try reader.readOptional { try $0.readFloat() }
                let decimal = try reader.readOptional { try $0.readBool() } ?? false
                return .range(id: resolvedID, title: title, minimum: minimum, maximum: maximum, decimal: decimal)
            default:
                throw AidokuRuntimeError.malformedPostcard
            }
        }
        try reader.finish()
        return filters
    }

    static func decodeSettings(_ data: Data) throws -> [AidokuSetting] {
        var reader = AidokuPostcardReader(data: data)
        let settings = try reader.readArray { try decodeSetting(from: &$0) }.flatMap { $0 }
        try reader.finish()
        return settings
    }

    private static func boundedData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= AidokuLimits.maximumJSONBytes else {
            throw AidokuRuntimeError.responseTooLarge
        }
        return data
    }

    private static func decodeSetting(from reader: inout AidokuPostcardReader) throws -> [AidokuSetting] {
        _ = try reader.readString()
        let key = try reader.readString()
        let title = try reader.readString()
        _ = try reader.readOptional { try $0.readString() }
        _ = try reader.readOptional { try $0.readString() }
        _ = try reader.readOptional { try $0.readString() }
        _ = try reader.readOptional { try $0.readArray { try $0.readString() } }
        let variant = try reader.readVarUInt()
        switch variant {
        case 0:
            _ = try reader.readOptional { try $0.readString() }
            let children = try reader.readArray { try decodeSetting(from: &$0) }.flatMap { $0 }
            return (title.isEmpty ? [] : [.header(id: "header-\(title)", title: title)]) + children
        case 1:
            let values = try reader.readArray { try $0.readString() }
            let labels = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? values
            _ = try reader.readOptional { try $0.readBool() }
            let defaultValue = try reader.readOptional { try $0.readString() }
            return [.select(id: key, title: title, values: values, labels: labels, defaultValue: defaultValue)]
        case 2:
            let values = try reader.readArray { try $0.readString() }
            let labels = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? values
            _ = try reader.readOptional { try $0.readBool() }
            let defaultValues = try reader.readOptional { try $0.readArray { try $0.readString() } }
            return [.multiSelect(id: key, title: title, values: values, labels: labels, defaultValues: defaultValues)]
        case 3:
            _ = try reader.readOptional { try $0.readString() }
            _ = try reader.readOptional { try $0.readBool() }
            return [.switchValue(id: key, title: title, defaultValue: try reader.readBool(), secure: false)]
        case 4:
            let minimum = try reader.readDouble()
            let maximum = try reader.readDouble()
            let step = try reader.readOptional { try $0.readDouble() } ?? 1
            let defaultValue = try reader.readOptional { try $0.readDouble() }
            return [.stepper(id: key, title: title, defaultValue: defaultValue, min: minimum, max: maximum, step: step)]
        case 5:
            let values = try reader.readArray { try $0.readString() }
            let index = try reader.readOptional { try $0.readInt32() }
            return [.segment(id: key, title: title, options: values, defaultIndex: index)]
        case 6:
            _ = try reader.readOptional { try $0.readString() }
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readOptional { try $0.readBool() }
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readOptional { try $0.readInt32() }
            let secure = try reader.readOptional { try $0.readBool() } ?? false
            let defaultValue = try reader.readOptional { try $0.readString() }
            return [.text(id: key, title: title, defaultValue: defaultValue, secure: secure)]
        case 7:
            return [.header(id: key.isEmpty ? "button-\(title)" : key, title: title)]
        case 8:
            _ = try reader.readString()
            _ = try reader.readOptional { try $0.readBool() }
            return [.header(id: key.isEmpty ? "link-\(title)" : key, title: title)]
        case 9:
            let methodIndex = try reader.readVarUInt()
            let method: AidokuLoginMethod = methodIndex == 0 ? .basic : methodIndex == 1 ? .oauth : .web
            let url = try reader.readOptional { try $0.readString() }
            let urlKey = try reader.readOptional { try $0.readString() }
            _ = try reader.readOptional { try $0.readString() }
            _ = try reader.readBool()
            _ = try reader.readOptional { try $0.readString() }
            _ = try reader.readOptional { try $0.readString() }
            _ = try reader.readBool()
            let localStorageKeys = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? []
            return [.login(AidokuLoginConfiguration(key: key, title: title, method: method, url: url, urlKey: urlKey, localStorageKeys: localStorageKeys))]
        case 10:
            let children = try reader.readArray { try decodeSetting(from: &$0) }.flatMap { $0 }
            _ = try reader.readOptional { try $0.readBool() }
            _ = try reader.readOptional { try $0.readBool() }
            try skipPageIcon(&reader)
            _ = try reader.readOptional { try $0.readString() }
            return (title.isEmpty ? [] : [.header(id: "page-\(title)", title: title)]) + children
        case 11:
            _ = try reader.readOptional { try $0.readInt32() }
            _ = try reader.readBool()
            let placeholder = try reader.readOptional { try $0.readString() }
            let defaultValues = try reader.readOptional { try $0.readArray { try $0.readString() } }
            return [.editableList(id: key, title: title, placeholder: placeholder, defaultValues: defaultValues)]
        case 12:
            let values = try reader.readArray { try $0.readString() }
            let labels = try reader.readOptional { try $0.readArray { try $0.readString() } } ?? values
            let defaultValue = try reader.readOptional { try $0.readString() }
            return [.select(id: key, title: title, values: values, labels: labels, defaultValue: defaultValue)]
        default:
            throw AidokuRuntimeError.malformedPostcard
        }
    }

    private static func skipPageIcon(_ reader: inout AidokuPostcardReader) throws {
        guard try reader.readBool() else { return }
        switch try reader.readVarUInt() {
        case 0:
            _ = try reader.readString()
            _ = try reader.readString()
            _ = try reader.readOptional { try $0.readInt32() }
        case 1:
            _ = try reader.readString()
        default:
            throw AidokuRuntimeError.malformedPostcard
        }
    }

    private static func decodeFilter(_ object: [String: Any]) throws -> AidokuFilter? {
        guard let type = object["type"] as? String else { return nil }
        let title = object["title"] as? String ?? ""
        let id = object["id"] as? String ?? (!title.isEmpty ? title : type)
        switch type {
        case "text":
            return .text(id: id, title: title, placeholder: object["placeholder"] as? String)
        case "sort":
            let options = object["options"] as? [String] ?? []
            return .sort(id: id, title: title, options: options, canAscend: object["can_ascend"] as? Bool ?? object["canAscend"] as? Bool ?? true)
        case "check":
            let defaultValue = (object["default"] as? Bool).map { $0 ? 1 : 0 } ?? 0
            return .check(id: id, title: title, canExclude: object["can_exclude"] as? Bool ?? object["canExclude"] as? Bool ?? false, defaultValue: defaultValue)
        case "select":
            let options = object["options"] as? [String] ?? []
            let ids = object["ids"] as? [String] ?? options
            let defaultValue = object["default"] as? String
            return .select(id: id, title: title, options: options, values: ids, defaultValue: defaultValue)
        case "multi-select":
            let options = object["options"] as? [String] ?? []
            return .multiSelect(id: id, title: title, options: options, values: object["ids"] as? [String] ?? options)
        case "range":
            return .range(
                id: id,
                title: title,
                minimum: (object["min"] as? NSNumber)?.floatValue,
                maximum: (object["max"] as? NSNumber)?.floatValue,
                decimal: object["decimal"] as? Bool ?? false
            )
        case "note":
            return .header(id: id, title: object["text"] as? String ?? title)
        default:
            return nil
        }
    }

    private static func flattenSettings(_ objects: [[String: Any]]) throws -> [AidokuSetting] {
        var output: [AidokuSetting] = []
        for object in objects {
            let type = object["type"] as? String ?? ""
            let title = object["title"] as? String ?? ""
            let key = object["key"] as? String ?? ""
            switch type {
            case "group", "page":
                if !title.isEmpty { output.append(.header(id: "header-\(output.count)-\(title)", title: title)) }
                if let items = object["items"] as? [[String: Any]] {
                    output.append(contentsOf: try flattenSettings(items))
                }
            case "switch":
                guard !key.isEmpty else { continue }
                output.append(.switchValue(id: key, title: title, defaultValue: object["default"] as? Bool ?? false, secure: false))
            case "select", "picker":
                guard !key.isEmpty else { continue }
                let values = object["values"] as? [String] ?? []
                output.append(.select(id: key, title: title, values: values, labels: object["titles"] as? [String] ?? values, defaultValue: object["default"] as? String))
            case "multi-select":
                guard !key.isEmpty else { continue }
                let values = object["values"] as? [String] ?? []
                output.append(.multiSelect(
                    id: key,
                    title: title,
                    values: values,
                    labels: object["titles"] as? [String] ?? values,
                    defaultValues: object["default"] as? [String]
                ))
            case "segment":
                guard !key.isEmpty else { continue }
                let values = object["options"] as? [String] ?? []
                let index = (object["default"] as? NSNumber)?.int32Value
                output.append(.segment(id: key, title: title, options: values, defaultIndex: index))
            case "text":
                guard !key.isEmpty else { continue }
                output.append(.text(id: key, title: title, defaultValue: object["default"] as? String, secure: object["secure"] as? Bool ?? false))
            case "stepper":
                guard !key.isEmpty else { continue }
                let minimum = (object["minimum_value"] as? NSNumber)?.doubleValue ?? (object["minimumValue"] as? NSNumber)?.doubleValue ?? 0
                let maximum = (object["maximum_value"] as? NSNumber)?.doubleValue ?? (object["maximumValue"] as? NSNumber)?.doubleValue ?? 100
                let step = (object["step_value"] as? NSNumber)?.doubleValue ?? (object["stepValue"] as? NSNumber)?.doubleValue ?? 1
                output.append(.stepper(id: key, title: title, defaultValue: (object["default"] as? NSNumber)?.doubleValue, min: minimum, max: maximum, step: step))
            case "editable-list":
                guard !key.isEmpty else { continue }
                output.append(.editableList(
                    id: key,
                    title: title,
                    placeholder: object["placeholder"] as? String,
                    defaultValues: object["default"] as? [String]
                ))
            case "login":
                guard !key.isEmpty, let methodValue = object["method"] as? String, let method = AidokuLoginMethod(rawValue: methodValue) else { continue }
                output.append(.login(AidokuLoginConfiguration(
                    key: key,
                    title: title,
                    method: method,
                    url: object["url"] as? String,
                    urlKey: object["url_key"] as? String ?? object["urlKey"] as? String,
                    localStorageKeys: object["local_storage_keys"] as? [String] ?? object["localStorageKeys"] as? [String] ?? []
                )))
            default:
                continue
            }
        }
        return output
    }
}
