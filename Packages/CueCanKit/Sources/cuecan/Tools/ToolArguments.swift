import Foundation
import MCP
import ProjectKit

/// A tool call's arguments, with typed reads that say plainly what was wrong.
struct ToolArguments: Sendable {
    let values: [String: Value]

    init(_ values: [String: Value]) {
        self.values = values
    }

    func string(_ key: String) throws -> String {
        guard let value = values[key] else { throw ToolError.missingArgument(key) }
        guard let string = value.stringValue else { throw ToolError.wrongType(key, expected: "a string") }
        return string
    }

    func optionalString(_ key: String) throws -> String? {
        guard values[key] != nil, values[key] != .null else { return nil }
        return try string(key)
    }

    func double(_ key: String) throws -> Double {
        guard let value = values[key] else { throw ToolError.missingArgument(key) }
        return try Self.finiteNumber(value, key: key)
    }

    private static func finiteNumber(_ value: Value, key: String) throws -> Double {
        let number: Double?
        switch value {
        case .double(let value): number = value
        case .int(let value): number = Double(value)
        case .string(let text): number = Double(text)
        default: number = nil
        }
        guard let number, number.isFinite else { throw ToolError.wrongType(key, expected: "a finite number") }
        return number
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard values[key] != nil, values[key] != .null else { return nil }
        return try double(key)
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = values[key], value != .null else { return nil }
        switch value {
        case .bool(let flag): return flag
        case .string("true"): return true
        case .string("false"): return false
        default: throw ToolError.wrongType(key, expected: "true or false")
        }
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = values[key], value != .null else { return nil }
        if case .int(let number) = value { return number }
        if case .string(let text) = value {
            guard let number = Int(text) else { throw ToolError.wrongType(key, expected: "a representable whole number") }
            return number
        }
        let number = try Self.finiteNumber(value, key: key)
        guard let exact = Int(exactly: number) else { throw ToolError.wrongType(key, expected: "a representable whole number") }
        return exact
    }

    func strings(_ key: String) throws -> [String]? {
        guard let value = values[key], value != .null else { return nil }
        if let text = value.stringValue {
            return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        guard let array = value.arrayValue else { throw ToolError.wrongType(key, expected: "a list of strings") }
        return try array.map { item in
            guard let text = item.stringValue else { throw ToolError.wrongType(key, expected: "a list of strings") }
            return text
        }
    }

    func numbers(_ key: String) throws -> [Double]? {
        guard let value = values[key], value != .null else { return nil }
        let items: [Value]
        if let text = value.stringValue {
            items = text.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) }
        } else if let array = value.arrayValue {
            items = array
        } else { throw ToolError.wrongType(key, expected: "a list of numbers") }
        return try items.map { try Self.finiteNumber($0, key: key) }
    }

    func has(_ key: String) -> Bool { values[key] != nil && values[key] != .null }

    func reject(_ keys: [String], because reason: String) throws {
        if let key = keys.first(where: has) { throw ToolError.invalidValue(key, reason) }
    }

    func itemID(_ key: String) throws -> TranscriptItemID {
        let text = try string(key)
        guard let id = TranscriptItemID(text) else { throw ToolError.invalidID(text, expected: "a word or silence id like w_12 or s_3") }
        return id
    }

    func wordID(_ key: String) throws -> WordID {
        let text = try string(key)
        guard let id = WordID(text) else { throw ToolError.invalidID(text, expected: "a word id like w_12") }
        return id
    }

    func clipID(_ key: String) throws -> ClipID {
        let text = try string(key)
        guard let id = ClipID(text) else { throw ToolError.invalidID(text, expected: "a clip id like c_3") }
        return id
    }

    func sourceID(_ key: String) throws -> SourceID {
        let text = try string(key)
        guard let id = SourceID(text) else { throw ToolError.invalidID(text, expected: "a source id like src_1") }
        return id
    }

    func optionalSourceID(_ key: String) throws -> SourceID? {
        guard values[key] != nil, values[key] != .null else { return nil }
        return try sourceID(key)
    }

    /// A range from two ids, such as `start_id` and `end_id`. A missing end means the one item.
    func range(from first: String, to last: String) throws -> ItemRange {
        let start = try itemID(first)
        let end = values[last] == nil ? start : try itemID(last)
        return ItemRange(first: start, last: end)
    }

    /// A range of time from `start_time` and `end_time`.
    func timeRange(from first: String = "start_time", to last: String = "end_time") throws -> TimeRange {
        let start = try double(first)
        let end = try double(last)
        guard end > start else { throw ToolError.invalidValue(last, "it has to be after \(first).") }
        return TimeRange(start: start, end: end)
    }

    func optionalFreezeID(_ key: String) throws -> FreezeID? {
        guard let text = try optionalString(key) else { return nil }
        guard let id = FreezeID(text) else { throw ToolError.invalidID(text, expected: "a freeze id like f_4") }
        return id
    }

    /// A value decoded as one of the edit's own JSON shapes, such as a layout.
    func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
        guard let value = values[key], value != .null else { return nil }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw ToolError.invalidValue(key, Self.describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context): context.debugDescription
        case .keyNotFound(let key, _): "it needs “\(key.stringValue)”."
        case .typeMismatch(_, let context), .valueNotFound(_, let context): context.debugDescription
        @unknown default: error.localizedDescription
        }
    }
}

extension TimeRange {
    /// "12.30–14.05 s".
    var formatted: String { String(format: "%.2f–%.2f s", start, end) }
}
