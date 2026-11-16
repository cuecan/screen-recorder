/// A word in a transcript, such as `w_104`. Unique across the whole project, not just one transcript,
/// so an id alone names one word in one source.
public struct WordID: PrefixedID {
    public static let prefix = "w"
    public let number: Int
    public init(number: Int) { self.number = number }
}
