/// A real silence in a transcript, such as `s_12`. Unique across the whole project.
public struct SilenceID: PrefixedID {
    public static let prefix = "s"
    public let number: Int
    public init(number: Int) { self.number = number }
}
