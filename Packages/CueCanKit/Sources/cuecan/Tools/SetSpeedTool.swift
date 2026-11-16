import Foundation
import MCP
import ProjectKit

/// Plays a clip faster (docs/decisions.md, 59).
struct SetSpeedTool: EditorTool {
    let name = "set_speed"
    let description = """
        Plays a clip at 1, 1.5, 2, 4 or 8 times speed, for a wait worth showing rather than cutting (a build, an \
        install). Its sound keeps its pitch or is muted; above 2× it's muted unless sound is pitch_kept. Word \
        times and the SRT go through the speed. To speed up only part of a clip, split_clip it first at times. \
        rate 1 puts it back to normal.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "clip_id": Schema.string("The clip, such as c_3, from get_edit."),
                "rate": Schema.number("1, 1.5, 2, 4 or 8."),
                "sound": Schema.oneOf(ClipSpeed.Sound.allCases.map(\.rawValue).map { $0 == "pitchKept" ? "pitch_kept" : $0 }, "pitch_kept or muted. Muted above 2× if left out."),
            ],
            required: ["project", "clip_id", "rate"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let clipID = try arguments.clipID("clip_id")
        let rate = try arguments.double("rate")
        let sound = try arguments.optionalString("sound").map { name -> ClipSpeed.Sound in
            switch name {
            case "pitch_kept", "pitchKept": return .pitchKept
            case "muted": return .muted
            default: throw ToolError.invalidValue("sound", "use pitch_kept or muted.")
            }
        }
        guard let speed = ClipSpeed(rate: rate, sound: sound) else { throw EditError.invalidSpeed(rate) }
        let (edit, clip) = try context.change(folder, reason: "\(clipID) at \(speed.label)") { edit, _ in
            try edit.setSpeed(speed, for: clipID)
        }
        let message = speed.isNormal ? "\(clipID) plays at normal speed." : "\(clipID) plays at \(speed.label), \(speed.sound == .muted ? "muted" : "its sound pitch-kept"): \(String(format: "%.2f", clip.duration)) s."
        return try EditingOutput.after(message, edit: edit, folder: folder)
    }
}
