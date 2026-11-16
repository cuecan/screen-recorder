/// A clip on the edit's timeline, such as `c_3`.
public struct ClipID: PrefixedID {
    public static let prefix = "c"
    public let number: Int
    public init(number: Int) { self.number = number }
}
