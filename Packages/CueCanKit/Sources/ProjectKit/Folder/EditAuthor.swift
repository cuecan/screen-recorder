import Foundation

/// Provenance of a saved edit. Agent, command and system names are open-ended; their roles are not.
public enum EditAuthor: Codable, Equatable, Sendable {
    case app
    case agent(String)
    case commandLine(String)
    case system(String)

    public var displayName: String {
        switch self { case .app: "You"; case .agent(let name), .commandLine(let name), .system(let name): name }
    }
    private enum Role: String, Codable { case app, agent, commandLine, system }
    private enum CodingKeys: String, CodingKey { case role, name }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Role.self, forKey: .role) {
        case .app: self = .app
        case .agent: self = .agent(try values.decode(String.self, forKey: .name))
        case .commandLine: self = .commandLine(try values.decode(String.self, forKey: .name))
        case .system: self = .system(try values.decode(String.self, forKey: .name))
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        let role: Role = switch self { case .app: .app; case .agent: .agent; case .commandLine: .commandLine; case .system: .system }
        try values.encode(role, forKey: .role)
        if self != .app { try values.encode(displayName, forKey: .name) }
    }
}
