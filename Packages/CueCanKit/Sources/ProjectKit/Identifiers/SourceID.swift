/// A source in `project.json`: one recording or one imported file, such as `src_1`.
public struct SourceID: PrefixedID {
    public static let prefix = "src"
    public let number: Int
    public init(number: Int) { self.number = number }
}

/// Source ids key `AudioSettings.sources`, so they encode as an object's keys (`{"src_2": …}`) rather
/// than as an array of alternating keys and values.
extension SourceID: CodingKeyRepresentable {
    public var codingKey: any CodingKey { IDCodingKey(stringValue: description) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }
}

/// A coding key that's just a string, for encoding ids as dictionary keys.
struct IDCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
