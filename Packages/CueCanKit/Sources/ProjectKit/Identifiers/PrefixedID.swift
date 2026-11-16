import Foundation

/// A stable id with a short prefix and a number, written as `prefix_number` (`w_104`, `s_12`, `src_2`).
///
/// Ids are what Claude reads and writes, so they're short and never reused. Each kind of id has its own
/// type, so a word id can't be passed where a source id is expected.
public protocol PrefixedID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible,
    LosslessStringConvertible
{
    /// The prefix before the underscore, such as `w` for words.
    static var prefix: String { get }
    /// The number after the underscore.
    var number: Int { get }
    init(number: Int)
}

extension PrefixedID {
    public var description: String { "\(Self.prefix)_\(number)" }

    /// Parses `prefix_number`, such as `w_104`. Returns nil for anything else.
    public init?(_ description: String) {
        let expectedPrefix = Self.prefix + "_"
        guard description.hasPrefix(expectedPrefix),
            let number = Int(description.dropFirst(expectedPrefix.count)),
            number >= 0,
            description == "\(expectedPrefix)\(number)"
        else { return nil }
        self.init(number: number)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.number < rhs.number }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = Self(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(text)\" isn't a valid id. Expected \(Self.prefix)_<number>."
            )
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
