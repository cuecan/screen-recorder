import Foundation

/// The Amount dials' range, from 0 to 100 percent.
enum AudioAmount {
    static let range: ClosedRange<Double> = 0...100

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.upperBound
    }

    /// Reads an amount, refusing one outside 0 to 100 rather than quietly changing it.
    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Double {
        let value = try container.decode(Double.self, forKey: key)
        guard range.contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "An amount is a percentage from 0 to 100, not \(value)."
            )
        }
        return value
    }
}
