import Foundation
import MCP
import ProjectKit

struct SetLayoutTool: EditorTool {
    let name = "set_layout"
    let description = """
        Sets a clip's layout. A clip has one layout, drawn for whichever shape is shown or exported: nothing is \
        set once for the 16:9 video and again for the 9:16 Short (a Short that should differ is a duplicate of \
        the project). Layouts are objects with a kind (docs/decisions.md, 89): {"kind":"automatic"} is the layout \
        the take was set up with; {"kind":"camera"} is the camera filling the frame; {"kind":"screen"} the screen \
        alone; {"kind":"sideBySide"} the camera beside the screen (above or below it in a Short), only for a take \
        recorded with room beside the screen, whose share can't change afterwards; and a card over the screen: \
        {"kind":"card","position":"right","size":"medium","shape":"tall","screen":"smaller","roundness":0.12}. \
        A card's position is topLeft, top, topRight, left, center, right, bottomLeft, bottom or bottomRight; its \
        size small, medium or large; its shape square, tall or wide; its roundness 0 to 0.5 of its shorter side \
        (0.3 on a square is the bubble). Its screen is full (the screen fills the frame under the card) or \
        smaller (a 16:9 video only: the screen shrinks until two-thirds of the card is over it and a third hangs off its edge). A \
        take made for both has no card. camera_side is Side by side's: standard or flipped; right or left as the \
        video shows it; above or below as the Short does. A split keeps both in each piece. \
        The inset, corners, background and mirror are shared by every clip (set_look); the inset frames the \
        screen and never the camera alone. Try a layout first with preview_frames' layout.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "clip_id": Schema.string("The clip, such as c_3. Use \"all\" for every clip."),
                "layout": Schema.anyObject("The layout. Leave out to keep it."),
                "camera_side": Schema.oneOf(["standard", "flipped", "right", "left", "above", "below"],
                                            "Side by side's camera: standard or flipped; or right or left as the video shows it, above or below as the Short does."),
            ],
            required: ["project", "clip_id"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let target = try arguments.string("clip_id")
        let layout = try arguments.decode(Layout.self, "layout")
        let side = try arguments.optionalString("camera_side")
        guard layout != nil || side != nil else { throw ToolError.missingArgument("layout") }
        let project = try folder.loadProject()
        let destination = project.effectiveFormat.destination
        let (edit, _) = try context.change(folder, reason: "Set the layout of \(target)") { edit, _ in
            let ids = target == "all" ? edit.main.map(\.id) : [try ToolArguments(["clip_id": .string(target)]).clipID("clip_id")]
            for id in ids {
                if let layout {
                    if case .card = layout, !TakeLayout.offersCard(destination) {
                        throw ToolError.invalidValue("layout", "a take made for both has no card: use sideBySide, camera or screen.")
                    }
                    try edit.setLayout(layout, for: id)
                }
                if let side {
                    guard let value = OutputLook.CameraSide(name: side, in: .landscape) ?? OutputLook.CameraSide(name: side, in: .vertical) else {
                        throw ToolError.invalidValue("camera_side", "use standard or flipped, right or left, or above or below.")
                    }
                    try edit.changeLook(for: id) { $0.cameraSide = value }
                }
            }
        }
        return try EditingOutput.after("Set the layout of \(target).", edit: edit, folder: folder)
    }
}
