import Foundation
import MCP
import ProjectKit

/// What every clip shares, in the video and the Short alike (docs/decisions.md, 61, 66, 77, 81 and 86). The camera side is
/// each clip's own, set with `set_layout`.
struct SetLookTool: EditorTool {
    let name = "set_look"
    let description = """
        Sets what every clip shares, in the 16:9 video and the 9:16 Short alike (nothing is set per shape): inset (none, S, M or L: the space \
        around the screen and between it and Side by side's camera, 0, 30, 60 or 90 px at 1080p; it never frames the camera alone or a full screen under a card), rounded (true or false: the tiles' corners; \
        a card has its own roundness), background (one plain colour, like \
        #1E1E20), backdrop (a base look in place of the plain colour: "paper", white and still; "daylight", \
        white with the light slowly drifting; "aura", white with a pale bloom of the camera's own colours; \
        "ink", near-black and still; "glow", near-black with a deeper bloom; or "plain" for the plain colour), \
        shadows and lit_edge (each true or false, on any look, and on to start with), and \
        mirror (true flips the camera's picture so the creator faces the screen). Each clip's camera \
        side is its own: set it with set_layout. Check with preview_frames.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "inset": Schema.oneOf(["none", "S", "M", "L"], "The space around and between the tiles, in every clip."),
                "rounded": Schema.boolean("Round the tiles' corners."),
                "background": Schema.string("A colour like #D9D9D9."),
                "backdrop": Schema.oneOf(["plain", "paper", "daylight", "aura", "ink", "glow"], "A base look behind the tiles, or the plain colour."),
                "shadows": Schema.boolean("Two soft shadows under every tile."),
                "lit_edge": Schema.boolean("A hairline around every tile, brighter along its top."),
                "mirror": Schema.boolean("Flip the camera's picture left to right."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let inset = try arguments.optionalString("inset").map { name in
            guard let inset = OutputLook.Inset.allCases.first(where: { $0.label.lowercased() == name.lowercased() || $0.rawValue == name.lowercased() })
            else { throw ToolError.invalidValue("inset", "use none, S, M or L.") }
            return inset
        }
        let rounded = try arguments.optionalBool("rounded")
        let mirror = try arguments.optionalBool("mirror")
        let background = try arguments.optionalString("background")
        let backdropName = try arguments.optionalString("backdrop")
        let backdrop = backdropName.flatMap { OutputLook.Backdrop(rawValue: $0.lowercased()) }
        if backdropName != nil, backdrop == nil { throw ToolError.invalidValue("backdrop", "use plain, paper, daylight, aura, ink or glow.") }
        let addOns: [(OutputLook.AddOn, String)] = [(.shadows, "shadows"), (.litEdge, "lit_edge")]
        var switched: [(OutputLook.AddOn, Bool)] = []
        for (addOn, key) in addOns {
            if let on = try arguments.optionalBool(key) { switched.append((addOn, on)) }
        }
        if let background, OutputLook.normalizedColor(background) == nil { throw ToolError.invalidValue("background", "use a colour like #1E1E20.") }
        let (edit, _) = try context.change(folder, reason: "Set the look") { edit, _ in
            if let inset { edit.look.inset = inset }
            if let rounded { edit.look.rounded = rounded }
            if let background { edit.look.background = background }
            if let backdrop { edit.look.choose(backdrop) }
            for (addOn, on) in switched {
                if on { edit.look.addOns.insert(addOn) } else { edit.look.addOns.remove(addOn) }
            }
            if let mirror { edit.look.mirror = mirror }
        }
        return try EditingOutput.after("Set the look.", edit: edit, folder: folder)
    }
}
