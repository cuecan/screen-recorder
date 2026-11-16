import Foundation
import MCP
import ProjectKit
import RenderKit

/// Animated captions, drawn into the 16:9 video and the 9:16 Short from the edit and the time
/// (docs/decisions.md, 80): never a rendered video, so every cut and word fix moves them.
struct SetCaptionsTool: EditorTool {
    let name = "set_captions"
    let description = """
        Animated captions burned into the video and the Short, drawn from the transcript with its fixes, through \
        every cut, speed change and freeze. A spike: one style (Pop) for the creator to judge. on turns them on or \
        off, for the clips listed in clips or for every clip when it's left out: each clip has its own, and \
        a split copies it into both pieces; style and timing are the edit's, the same for the video and the Short, \
        which lays the captions out again for its narrower frame. style picks a style by name; style_changes changes some of the style's values for this \
        project, in the same shape get_edit shows (for example {"spoken":{"fill":"#00FF66"},"words":{"atOnce":2}}). \
        emphasize and unemphasize take word ids (w_12) to draw bigger in the emphasis colour; break_before and \
        no_break_before take word ids a line starts at. lead shows every word that many \
        seconds earlier. Look with preview_frames before rendering; the SRT export is unchanged.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "on": Schema.boolean("Show captions, in the clips listed or every clip."),
                "clips": Schema.list(of: ["type": "string"], "Clip ids (c_3) that on applies to. Every clip if left out."),
                "style": Schema.oneOf(CaptionStyle.catalog(for: .landscape).map(\.name), "A style by name. It replaces any style_changes made before."),
                "style_changes": Schema.anyObject("Values of the style to change, in its own JSON shape. null takes an optional part away, such as the shadow."),
                "emphasize": Schema.list(of: ["type": "string"], "Word ids to emphasise."),
                "unemphasize": Schema.list(of: ["type": "string"], "Word ids to stop emphasising."),
                "break_before": Schema.list(of: ["type": "string"], "Word ids that start a new line."),
                "no_break_before": Schema.list(of: ["type": "string"], "Word ids that no longer start a new line."),
                "lead": Schema.number("Show words this many seconds earlier (negative: later). From -0.5 to 0.5."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let on = try arguments.optionalBool("on")
        let clips = try arguments.strings("clips").map { texts in
            Set(try texts.map { text in
                guard let id = ClipID(text) else { throw ToolError.invalidID(text, expected: "a clip id like c_3") }
                return id
            })
        }
        if clips != nil, on == nil { throw ToolError.invalidValue("clips", "clips go with on: say whether to turn captions on or off in them.") }
        let styleName = try arguments.optionalString("style")
        if let styleName, CaptionStyle.named(styleName, for: .landscape) == nil {
            throw ToolError.invalidValue("style", "the styles are \(CaptionStyle.catalog(for: .landscape).map(\.name).joined(separator: ", ")).")
        }
        let changes = try arguments.values["style_changes"].flatMap { $0 == .null ? nil : $0 }.map { try JSONEncoder().encode($0) }
        let lead = try arguments.optionalDouble("lead")
        if let lead, !(-0.5...0.5).contains(lead) { throw ToolError.invalidValue("lead", "use -0.5 to 0.5 seconds.") }
        func ids(_ key: String) throws -> [WordID] {
            try (arguments.strings(key) ?? []).map { text in
                guard let id = WordID(text) else { throw ToolError.invalidID(text, expected: "a word id like w_12") }
                return id
            }
        }
        let emphasize = try ids("emphasize"), unemphasize = try ids("unemphasize")
        let breakBefore = try ids("break_before"), noBreakBefore = try ids("no_break_before")

        let (edit, _) = try context.change(folder, reason: "Set the captions") { edit, transcripts in
            if let clips, let unknown = clips.first(where: { id in !edit.main.contains { $0.id == id } }) {
                throw ToolError.invalidValue("clips", "\(unknown) isn't a clip on the main track; get_edit lists them.")
            }
            for id in emphasize + breakBefore where transcripts.source(of: .word(id)) == nil {
                throw ToolError.invalidValue("word", "\(id) isn't a word in the transcript; get_transcript lists them.")
            }
            if let styleName { edit.captions.setStyle(named: styleName) }
            if let changes {
                do { try edit.captions.changeStyle(with: changes) } catch {
                    throw ToolError.invalidValue("style_changes", (error as? LocalizedError)?.errorDescription ?? "\(error)")
                }
            }
            if let lead { edit.captions.timing.lead = lead }
            if let on { edit.setCaptions(on, for: clips) }
            edit.captions.setEmphasis(emphasize, on: true)
            edit.captions.setEmphasis(unemphasize, on: false)
            edit.captions.setLineBreaks(before: breakBefore, on: true)
            edit.captions.setLineBreaks(before: noBreakBefore, on: false)
        }
        let shown = edit.main.filter(\.look.captions).count
        let state = shown == 0 ? "off" : shown == edit.main.count ? "on in every clip" : "on in \(shown) of \(edit.main.count) clips"
        return try EditingOutput.after("Captions — \(state), \(edit.captions.styleName).", edit: edit, folder: folder)
    }
}
