import Foundation
import MCP
import ProjectKit

/// Places a picture or a clip on top of the main track (docs/decisions.md, 54): B-roll from a source, a
/// screenshot, or a video file, over words or over a stretch of time.
struct PlaceBrollTool: EditorTool {
    let name = "place_broll"
    let description = """
        Shows a picture or a clip on top of the main track, over a range of words (start_word_id to end_word_id) \
        or over a stretch of the edited timeline (start_time to end_time, for where nothing is said). It's \
        anchored to those words or that source time, so it moves with every cut. Give source_id for B-roll \
        from the project, or file for an image or video anywhere on disk (referenced where it is). \
        placement: covers_frame (like B-roll: the screen and camera are hidden) or in_screens_place (the \
        camera stays beside it). A video's own sound starts muted; set muted false to hear it. \
        To move or change one, give its overlay_id; remove true takes it out.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "source_id": Schema.string("B-roll from the project, such as src_3, from list_projects."),
                "file": Schema.string("Or an image or video file's path."),
                "start_word_id": Schema.string("The first main-track word it covers."),
                "end_word_id": Schema.string("The last main-track word it covers."),
                "start_time": Schema.number("Or where it starts, in seconds of the edited timeline."),
                "end_time": Schema.number("And where it ends, in seconds of the edited timeline."),
                "placement": Schema.oneOf(["covers_frame", "in_screens_place"], "Where it sits. covers_frame if left out."),
                "muted": Schema.boolean("For a video: whether its own sound is off. true if left out."),
                "source_in": Schema.number("Where in a video to start playing, in seconds. 0 if left out."),
                "overlay_id": Schema.string("An overlay to move or change instead of placing a new one."),
                "remove": Schema.boolean("With overlay_id: take the overlay out."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let request = try OverlayRequest(arguments)
        let folder = try context.folder(arguments)
        try request.validateSources(in: folder.loadProject())
        switch request {
        case .remove(let id):
            let (edit, _) = try context.change(folder, reason: "Removed \(id)") { edit, _ in try edit.removeOverlay(id) }
            return try EditingOutput.after("Removed \(id).", edit: edit, folder: folder)
        case .update(let id, let changes):
            let (edit, _) = try context.change(folder, reason: "Changed \(id)") { edit, transcripts in
                switch changes.target {
                case .words(let range): try edit.moveOverlay(id, over: range, transcripts: transcripts)
                case .timeline(let range): try edit.moveOverlay(id, overTimeline: range)
                case nil: break
                }
                try edit.updateOverlay(id) { overlay in
                    if let media = changes.media { overlay.media = media }
                    if let placement = changes.placement { overlay.placement = placement }
                    if let muted = changes.muted { overlay.isMuted = muted }
                    if let sourceIn = changes.sourceIn { overlay.sourceIn = sourceIn }
                }
            }
            return try EditingOutput.after("Changed \(id).", edit: edit, folder: folder)
        case .create(let media, let target, let placement, let muted, let sourceIn):
            let (edit, overlay) = try context.change(folder, reason: "Placed an overlay") { edit, transcripts in
                switch target {
                case .words(let range):
                    try edit.placeOverlay(media, over: range, placement: placement, sourceIn: sourceIn, muted: muted, transcripts: transcripts)
                case .timeline(let range):
                    try edit.placeOverlay(media, overTimeline: range, placement: placement, sourceIn: sourceIn, muted: muted)
                }
            }
            return try EditingOutput.after("Placed \(overlay.id) (\(overlay.name)).", edit: edit, folder: folder)
        }
    }
}
