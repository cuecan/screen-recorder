import Foundation
import MCP
import Testing
import ProjectKit
@testable import cuecan

struct RequestValidationTests {
    /// Claude's API rejects a tool whose schema has oneOf, anyOf or allOf at the top, and with it every
    /// request that offers the tool, so exclusive argument shapes are checked when the tool runs instead.
    @Test func noToolSchemaCombinesShapesAtTheTop() {
        for tool in ToolCatalog.all {
            guard case .object(let schema) = tool.inputSchema else {
                Issue.record("\(tool.name)'s schema isn't an object")
                continue
            }
            #expect(schema["type"] == "object", "\(tool.name)")
            for key in ["oneOf", "anyOf", "allOf", "not"] {
                #expect(schema[key] == nil, "\(tool.name) has \(key) at the top of its schema")
            }
        }
    }

    @Test func integerDecodingIsExactAndNeverTraps() throws {
        #expect(try ToolArguments(["value": .int(Int.max)]).optionalInt("value") == Int.max)
        #expect(try ToolArguments(["value": .string(String(Int.max))]).optionalInt("value") == Int.max)
        #expect(try ToolArguments(["value": .int(Int.min)]).optionalInt("value") == Int.min)
        for value: Value in [.string("9223372036854775808"), .string("-9223372036854775809"), .double(1e100), .string("inf"), .string("-inf"), .string("nan"), .double(1.5)] {
            #expect(throws: ToolError.self) { try ToolArguments(["value": value]).optionalInt("value") }
        }
        for value: Value in [.string("nan"), .string("inf"), .double(.infinity)] {
            #expect(throws: ToolError.self) { try ToolArguments(["value": value]).double("value") }
            #expect(throws: ToolError.self) { try ToolArguments(["value": .array([value])]).numbers("value") }
        }
        #expect(throws: ToolError.self) { try ToolArguments(["value": "1,inf"]).numbers("value") }
    }

    @Test func conflictingTargetsAndIncompletePairsAreRejected() {
        for arguments: [String: Value] in [
            ["start_id": "w_1", "start_time": 0, "end_time": 1],
            ["start_id": "w_1", "source_id": "src_1"],
            ["end_id": "w_2"], ["start_time": 0], ["end_time": 1],
        ] {
            #expect(throws: ToolError.self) { try EditTarget.read(ToolArguments(arguments)) }
        }
        #expect(throws: ToolError.self) { try SplitRequest(ToolArguments(["time": 1, "clip_id": "c_1", "before_word_id": "w_1"])) }
        #expect(throws: ToolError.self) { try FreezeRequest(ToolArguments(["remove": true, "freeze_id": "f_1", "start_time": 0, "end_time": 1])) }
        #expect(throws: ToolError.self) { try FreezeRequest(ToolArguments(["freeze_id": "f_1", "start_time": 0, "end_time": 1])) }
    }

    @Test func overlayOperationsAreMutuallyExclusive() {
        for arguments: [String: Value] in [
            ["remove": true],
            ["overlay_id": "c_1", "remove": true, "muted": false],
            ["source_id": "src_1", "file": "/tmp/any", "start_time": 0, "end_time": 1],
            ["overlay_id": "c_1", "start_word_id": "w_1", "start_time": 0, "end_time": 1],
            ["overlay_id": "c_1", "source_in": -1],
            ["overlay_id": "c_1"],
        ] {
            #expect(throws: ToolError.self) { try OverlayRequest(ToolArguments(arguments)) }
        }
    }
}
