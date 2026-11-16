import Foundation
import MCP
import ProjectKit
import RenderKit

/// The inspector's static zoom and pan, available to an agent without changing a whole take's framing.
struct SetClipFramingTool: EditorTool {
    let name = "set_clip_framing"
    let description = """
        Sets a static zoom and centre for the screen or camera in selected clips. No keyframes or \
        animation. picture is screen or camera; center_x and center_y are fractions of the original \
        recorded picture from its top left, 0 to 1; zoom is 1 to 3. Give only parameters that should \
        change: each clip keeps its other values. A camera starts from the take's framing for that \
        clip's layout; this overrides it for these clips only. reset removes the override (screen \
        shows the whole recorded area; camera follows the take again). A split copies the framing. \
        The same values apply to the video and Short. get_edit shows overrides; preview_frames \
        shows the result. Use set_camera_framing to change a take's default framing instead.
        """
    var inputSchema: Value {
        Schema.object([
            "project": Schema.project,
            "clip_ids": Schema.list(of: Schema.string("A clip id, such as c_3."), "The clips to change."),
            "picture": Schema.string("screen or camera."),
            "center_x": Schema.number("The centre across the recorded picture, from 0 to 1."),
            "center_y": Schema.number("The centre down the recorded picture, from 0 to 1."),
            "zoom": Schema.number("A static enlargement, from 1 to 3."),
            "reset": Schema.boolean("Remove the clip override before applying any given parameters."),
        ], required: ["project", "clip_ids", "picture"])
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let project = try folder.loadProject()
        let name = try arguments.string("picture")
        guard let picture = Edit.Picture(rawValue: name) else { throw ToolError.invalidValue("picture", "use screen or camera.") }
        let ids = try (arguments.strings("clip_ids") ?? []).map { text in
            guard let id = ClipID(text) else { throw ToolError.invalidID(text, expected: "a clip id like c_3") }
            return id
        }
        guard !ids.isEmpty else { throw ToolError.invalidValue("clip_ids", "name at least one clip.") }
        let x = try arguments.optionalDouble("center_x"), y = try arguments.optionalDouble("center_y")
        let zoom = try arguments.optionalDouble("zoom")
        let reset = try arguments.optionalBool("reset") == true
        for (key, value) in [("center_x", x), ("center_y", y)] {
            if let value, !(0...1).contains(value) { throw ToolError.invalidValue(key, "use a fraction from 0 to 1.") }
        }
        if let zoom, !PictureTransform.zoomRange.contains(zoom) { throw ToolError.invalidValue("zoom", "use a zoom from 1 to 3.") }
        guard reset || x != nil || y != nil || zoom != nil else { throw ToolError.missingArgument("center_x, center_y, zoom or reset") }
        let (edit, _) = try context.change(folder, reason: "Reframed \(picture.rawValue) in \(ids.count) \(ids.count == 1 ? "clip" : "clips")") { edit, _ in
            // Validate the entire selection before changing any value.
            let clips = try ids.map { id -> Clip in
                guard let clip = edit.main.first(where: { $0.id == id }) else { throw EditError.unknownClip(id) }
                guard project.source(clip.source)?.track(picture == .screen ? .screen : .camera) != nil else {
                    throw ToolError.invalidValue("clip_ids", "\(id) has no \(picture.rawValue) picture.")
                }
                return clip
            }
            for clip in clips {
                var changed = clip
                if reset {
                    if picture == .screen { changed.screenTransform = nil } else { changed.cameraTransform = nil }
                }
                if reset { try edit.setTransform(nil, picture: picture, for: [clip.id]) }
                guard x != nil || y != nil || zoom != nil else { continue }
                guard let source = project.source(clip.source) else { throw EditError.unknownClip(clip.id) }
                let current = LayoutGeometry.transform(of: picture, clip: changed, source: source, edit: edit, in: project.effectiveFormat.outputs[0])
                try edit.setTransform(current.changing(centerX: x, centerY: y, zoom: zoom), picture: picture, for: [clip.id])
            }
        }
        return try EditingOutput.after("Updated \(picture.rawValue) framing in \(ids.count) \(ids.count == 1 ? "clip" : "clips"). Check it with preview_frames.", edit: edit, folder: folder)
    }
}
