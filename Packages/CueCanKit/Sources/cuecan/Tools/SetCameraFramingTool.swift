import Foundation
import MCP
import ProjectKit
import RenderKit

/// Frames a source's camera in one kind of slot, or all of them: the point the slot is cropped around, and
/// how far in (docs/decisions.md, 52). The recording keeps the whole camera frame, so this changes the
/// render only, and it can be undone like any other change.
struct SetCameraFramingTool: EditorTool {
    let name = "set_camera_framing"
    let description = """
        Frames the camera in one kind of slot, or every slot: the point it's cropped around, and the zoom, \
        from 1 (as much of the camera as the slot's shape allows) to 3. Each kind of slot is framed on its \
        own: slot is "card" (the card over the screen, whatever its size and shape), "split" (Side by side's camera: beside the screen in \
        the video, above or below it in the Short, one framing for both), "fullScreen" (the \
        camera filling the frame; until it's framed it follows Side by side's), or "all" (the \
        default). A framing is the same in the video and the Short; each crops its own shape around it. get_edit shows each source's framing by slot; \
        a slot not listed is centred. The recording keeps the whole frame, so this only changes the render. \
        center_on_face finds the creator's face in the camera's file and centres on it, so for "zoom in on \
        my face a bit and centre it" use center_on_face with a zoom such as 1.3, or zoom_by 1.2 to go in from \
        where it is. center_x and center_y are fractions of the recorded picture from its top left. \
        It applies to every source with a camera unless source_id is given. Check it with preview_frames.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "source_id": Schema.string("The source, such as src_1. Every source with a camera if left out."),
                "slot": Schema.string("card, split, fullScreen, or all (the default)."),
                "center_on_face": Schema.boolean("Centre on the creator's face, found in the camera's file."),
                "center_x": Schema.number("The point to frame around, 0 to 1 across the picture from the left."),
                "center_y": Schema.number("The point to frame around, 0 to 1 down the picture from the top."),
                "zoom": Schema.number("How far in, from 1 to 3."),
                "zoom_by": Schema.number("Zoom in (above 1) or out (below 1) from the current zoom, such as 1.2."),
                "reset": Schema.boolean("Back to the middle, not zoomed, before anything else given."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let project = try folder.loadProject()
        let cameraSources = project.sources.filter { $0.track(.camera) != nil }
        let sources: [Source]
        if let id = try arguments.optionalSourceID("source_id") {
            guard let source = project.source(id) else { throw ToolError.invalidValue("source_id", "there's no source \(id) in this project.") }
            guard source.track(.camera) != nil else { throw ToolError.invalidValue("source_id", "\(id) has no camera to frame.") }
            sources = [source]
        } else {
            guard !cameraSources.isEmpty else { throw ToolError.invalidValue("project", "no source in this project has a camera.") }
            sources = cameraSources
        }

        let slots: [CameraSlot]
        switch try arguments.optionalString("slot") {
        case nil, "all": slots = CameraSlot.allCases
        case let name?:
            guard let slot = CameraSlot(rawValue: name) else {
                throw ToolError.invalidValue("slot", "use card, split, fullScreen or all.")
            }
            slots = [slot]
        }
        let centerX = try arguments.optionalDouble("center_x")
        let centerY = try arguments.optionalDouble("center_y")
        let zoom = try arguments.optionalDouble("zoom")
        let zoomBy = try arguments.optionalDouble("zoom_by")
        let reset = try arguments.optionalBool("reset") == true
        let onFace = try arguments.optionalBool("center_on_face") == true
        for (key, value) in [("center_x", centerX), ("center_y", centerY)] {
            if let value, !(0...1).contains(value) { throw ToolError.invalidValue(key, "use a fraction from 0 to 1.") }
        }
        if let zoom, !CameraFraming.zoomRange.contains(zoom) { throw ToolError.invalidValue("zoom", "use a zoom from 1 to 3.") }
        if let zoomBy, !zoomBy.isFinite || zoomBy <= 0 { throw ToolError.invalidValue("zoom_by", "use a finite positive number, such as 1.2.") }
        guard reset || onFace || centerX != nil || centerY != nil || zoom != nil || zoomBy != nil else {
            throw ToolError.missingArgument("center_on_face, center_x, center_y, zoom, zoom_by or reset")
        }

        // Faces first: finding them reads the camera files, which happens outside the project's lock.
        var faces: [SourceID: FaceLocator.Face] = [:]
        var notes: [String] = []
        if onFace {
            for source in sources {
                guard let camera = source.track(.camera) else { continue }
                if let face = try await FaceLocator.face(in: camera.file.url(relativeTo: folder.url)) {
                    faces[source.id] = face
                    notes.append(String(format: "Found a face in %@ centred at %.2f, %.2f, about %.0f%% of the picture's height.",
                                        source.id.description, face.center.x, face.center.y, face.box.height * 100))
                } else {
                    notes.append("Found no face in \(source.id)'s camera, so its point wasn't moved.")
                }
            }
        }

        let reason = slots.count == 1 ? "Framed the camera: \(slots[0].label)" : "Framed the camera"
        let (edit, _) = try context.change(folder, reason: reason) { edit, _ in
            for source in sources {
                for slot in slots {
                    // What the slot shows now: a full-screen camera that isn't framed yet follows Side by side's.
                    var framing = reset ? .centered : edit.framings(for: source.id).framing(for: slot)
                    if let face = faces[source.id] {
                        framing = CameraFraming(centerX: face.center.x, centerY: face.center.y, zoom: framing.zoom)
                    }
                    framing = CameraFraming(
                        centerX: centerX ?? framing.centerX,
                        centerY: centerY ?? framing.centerY,
                        zoom: zoom ?? framing.zoom * (zoomBy ?? 1)
                    )
                    // Centred is what an unframed slot shows, so it's stored as no entry; except a lone
                    // full-screen camera, which would otherwise go back to following the large camera.
                    var framings = edit.framings(for: source.id)
                    framings[slot] = framing.isCentered && (slot != .fullScreen || slots.count > 1) ? nil : framing
                    edit.setFramings(framings, for: source.id)
                }
            }
        }
        let framed = sources.map { source in
            let framings = edit.framings(for: source.id)
            let parts = slots.map { slot in
                let framing = framings.framing(for: slot)
                return String(format: "%@ centred at %.2f, %.2f, zoom %.2f", slot.rawValue, framing.centerX, framing.centerY, framing.zoom)
            }
            return "\(source.id): \(parts.joined(separator: "; "))."
        }
        let message = (notes + ["Framed the camera. " + framed.joined(separator: " "), "Check it with preview_frames."]).joined(separator: "\n")
        return try EditingOutput.after(message, edit: edit, folder: folder)
    }
}
