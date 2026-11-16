import Foundation
import MCP
import ProjectKit
import RenderKit

struct PreviewFramesTool: EditorTool {
    /// More stills than this in one call would be a lot to look at, and a lot to send.
    static let maximumStills = 12

    let name = "preview_frames"
    let description = """
        Stills of the edit exactly as it will render, layout, look, card and overlays included, so you can look \
        before rendering: a cut that lands mid-blink, a card over code, an overlay in the wrong place. Ask for times on the edited \
        timeline, or at_cuts for the frames either side of each cut. Up to 12 at a time. Each still is listed with its clip and \
        layout. To try a layout before setting it, pass layout (the same objects set_layout takes): every clip is shown in it, \
        in the shape asked for, and the edit isn't changed. Captions are drawn when they're on (set_captions), and each \
        still lists the words on screen with the one being said in brackets; to look at them before turning them on, pass \
        captions true.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "times": Schema.list(of: ["type": "number"], "Seconds on the edited timeline."),
                "at_cuts": Schema.boolean("The frames just before and after each cut."),
                "shape": Schema.oneOf(OutputShape.allCases.map(\.rawValue), "landscape (16:9) or vertical (9:16). The project's first shape if left out."),
                "captions": Schema.boolean("Draw captions even if they're off, in the style they have, without changing the edit."),
                "layout": Schema.anyObject("A layout to try, such as {\"kind\":\"card\",\"position\":\"bottomRight\",\"size\":\"small\",\"shape\":\"square\",\"screen\":\"full\"}, shown for every clip without changing the edit."),
            ],
            required: ["project"]
        )
    }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        var inputs = try RenderInputs.load(folder)
        let shape = try arguments.optionalString("shape").map { name in
            guard let shape = OutputShape(rawValue: name) else { throw ToolError.invalidValue("shape", "use landscape or vertical.") }
            return shape
        } ?? inputs.project.effectiveFormat.outputs[0]
        if let trying = try arguments.decode(Layout.self, "layout") {
            inputs = inputs.withEdit { edit in
                for index in edit.main.indices { edit.main[index].layout = trying }
            }
        }
        if try arguments.optionalBool("captions") == true {
            inputs = inputs.withEdit { $0.setCaptions(true) }
        }
        let built = try await CompositionBuilder.build(inputs, output: shape)
        let captionPages = CaptionReading.pages(inputs, timeline: built.timeline, output: shape)
        let frameDuration = built.videoComposition.frameDuration.seconds

        var times = try arguments.numbers("times") ?? []
        if try arguments.optionalBool("at_cuts") == true { times += FrameGrabber.cutTimes(of: built) }
        if times.isEmpty { times = [0] }
        let asked = times.count
        times = Array(times.prefix(Self.maximumStills))

        let stills = try await FrameGrabber.stills(of: built, at: times, maximumWidth: shape == .landscape ? 960 : 540)
        let destination = inputs.project.effectiveFormat.destination
        var lines = stills.map { still in
            guard let index = built.timeline.clipIndex(at: still.time) else { return "\(String(format: "%.2f", still.time)) s · end · \(shape.ratioName)" }
            let clip = built.timeline.clips[index].clip
            let layout = inputs.project.source(clip.source).map { source in
                let pictures = ClipPictures(source: source)
                let resolved = LayoutGeometry.resolved(clip.layout, in: shape, pictures: pictures)
                let isOwn = source.layout.map { resolved == $0.layout } ?? false
                return resolved.described + (isOwn ? ", as recorded" : "")
            } ?? ""
            let caption = captionPages.map { pages in
                CaptionReading.text(at: still.time, pages: pages, style: inputs.edit.captions[shape].style, frameDuration: frameDuration)
                    .map { " · captions: \($0)" } ?? " · captions: none on screen"
            } ?? ""
            return "\(String(format: "%.2f", still.time)) s · \(clip.id) · \(layout) · \(shape.ratioName)\(caption)"
        }
        if asked > times.count { lines.append("Only the first \(Self.maximumStills) of \(asked) times; ask again for the rest.") }
        return ToolOutput(text: lines.joined(separator: "\n"), images: stills.map { .init(data: $0.jpeg, mimeType: "image/jpeg") })
    }
}
