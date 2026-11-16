import Foundation

/// Why a tool call couldn't run as asked. Read by Claude, so each says what to send instead.
enum ToolError: Error, Equatable, LocalizedError {
    case missingArgument(String)
    case wrongType(String, expected: String)
    case invalidID(String, expected: String)
    case unknownTool(String)
    case invalidJSON(String)
    case invalidValue(String, String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name): "“\(name)” is required."
        case .wrongType(let name, let expected): "“\(name)” should be \(expected)."
        case .invalidID(let value, let expected): "“\(value)” isn't \(expected)."
        case .unknownTool(let name): "There's no tool called “\(name)”. Run `cuecan tools` to list them."
        case .invalidJSON(let reason): "The arguments aren't valid JSON: \(reason)"
        case .invalidValue(let name, let reason): "“\(name)”: \(reason)"
        }
    }
}
