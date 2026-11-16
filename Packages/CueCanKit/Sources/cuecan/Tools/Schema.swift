import MCP

/// Builds the JSON Schema for a tool's arguments.
enum Schema {
    /// A tool's arguments. Claude's API takes no `oneOf`, `anyOf` or `allOf` at the top of a tool's schema, so
    /// arguments that exclude each other are described in words and checked when the tool runs (`EditTarget`,
    /// `OverlayRequest`, `SplitRequest`, `FreezeRequest`).
    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    static func string(_ description: String) -> Value {
        ["type": "string", "description": .string(description)]
    }

    static func number(_ description: String) -> Value {
        ["type": "number", "description": .string(description)]
    }

    static func boolean(_ description: String) -> Value {
        ["type": "boolean", "description": .string(description)]
    }

    static func oneOf(_ choices: [String], _ description: String) -> Value {
        ["type": "string", "enum": .array(choices.map { .string($0) }), "description": .string(description)]
    }

    static func list(of items: Value, _ description: String) -> Value {
        ["type": "array", "items": items, "description": .string(description)]
    }

    static func anyObject(_ description: String) -> Value {
        ["type": "object", "description": .string(description)]
    }

    /// The `project` argument every project tool takes.
    static let project = string("The project: its folder path, or its id or title from list_projects.")
}
