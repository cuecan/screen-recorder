import Foundation
import MCP
import ProjectKit

/// Sets clips' sound (docs/decisions.md, 71): the same operation as the editor's level line and its Sound
/// section.
struct SetClipSoundTool: EditorTool {
    let name = "set_clip_sound"
    let description = """
        Sets the sound of one or more clips: the voice's level and system audio's level in dB, and mute. 0 dB \
        plays it as recorded; levels run from -60 (off) to +12. Give only what should change; the rest stays \
        as each clip has it. Exports level the whole mix to -14 LUFS afterwards, so levels set the balance \
        between clips and between the voice and system audio, not how loud the video is. get_edit shows each \
        clip's levels. Cleanup and Voice are the take's, not the clip's, and aren't set here.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "clip_ids": Schema.list(of: Schema.string("A clip, such as c_3."), "The clips to change, from get_edit."),
                "voice_db": Schema.number("The voice's level in dB, -60 to 12."),
                "system_audio_db": Schema.number("System audio's level in dB, -60 to 12."),
                "muted": Schema.boolean("Whether the clips play silently: no voice and no system audio."),
            ],
            required: ["project", "clip_ids"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let ids = try (arguments.strings("clip_ids") ?? []).map { text in
            guard let id = ClipID(text) else { throw ToolError.invalidID(text, expected: "a clip id like c_3") }
            return id
        }
        guard !ids.isEmpty else { throw ToolError.invalidValue("clip_ids", "name at least one clip.") }
        let change = ClipSoundChange(
            voiceLevel: try arguments.optionalDouble("voice_db"),
            systemAudioLevel: try arguments.optionalDouble("system_audio_db"),
            isMuted: try arguments.optionalBool("muted")
        )
        guard !change.isEmpty else { throw ToolError.invalidValue("voice_db", "give voice_db, system_audio_db or muted.") }
        let names = ids.map(\.description).joined(separator: ", ")
        let (edit, _) = try context.change(folder, reason: "Sound of \(names)") { edit, _ in
            try edit.setSound(change, for: ids)
        }
        let described = ids.compactMap { id in edit.main.first { $0.id == id } }.map { clip in
            "\(clip.id): voice \(SoundLevel.label(clip.voiceLevel)), system audio \(SoundLevel.label(clip.systemAudioLevel))\(clip.isMuted ? ", muted" : "")"
        }
        return try EditingOutput.after(described.joined(separator: "; ") + ".", edit: edit, folder: folder)
    }
}
