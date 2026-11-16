import Foundation
import MCP
import ProjectKit

/// What happened on screen over a range of time (docs/decisions.md, 58): the recording's log of apps,
/// windows, clicks and scrolling, and the screen's changes, still moments and text, read after recording.
struct GetScreenTimelineTool: EditorTool {
    let name = "get_screen_timeline"
    let description = """
        What happened on screen over a stretch of time: app and window changes, clicks, drags, scrolling, typing \
        (how many keys, never which) and shortcuts (only the modifiers), \
        when the screen was changing and when it went still, and the text on screen at each still moment. Use \
        it to find a wait worth cutting or speeding up, the moment a result appears, or a key or token on \
        screen the creator should cut. start_time and end_time are on the edited timeline, or in source_id's \
        own time; leave both out for the whole edit. The pointer's path, which is long, only with \
        include_pointer. Still moments are good places to cut.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_time": Schema.number("From, in seconds of the edited timeline (or of source_id's time)."),
                "end_time": Schema.number("To."),
                "source_id": Schema.string("Read times as this source's own, and include parts the edit doesn't play."),
                "include_pointer": Schema.boolean("Also the pointer's path, sampled a few times a second."),
                "full_text": Schema.boolean("All the text at each still moment, not just its start."),
            ],
            required: ["project"]
        )
    }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let project = try folder.loadProject()
        let edit = try folder.loadEdit()
        let pointer = try arguments.optionalBool("include_pointer") == true
        let fullText = try arguments.optionalBool("full_text") == true

        // The stretches of source time to describe, each with how it maps onto the timeline.
        var pieces: [(source: Source, range: TimeRange, timelineStart: TimeInterval?, rate: Double)] = []
        if let id = try arguments.optionalSourceID("source_id") {
            guard let source = project.source(id) else { throw EditError.unknownSource(id) }
            let range = arguments.values["start_time"] == nil ? TimeRange(start: 0, end: source.duration) : try arguments.timeRange()
            pieces.append((source, range, nil, 1))
        } else {
            let range = arguments.values["start_time"] == nil ? TimeRange(start: 0, end: edit.duration) : try arguments.timeRange()
            for piece in edit.sourcePieces(of: range) {
                guard let source = project.source(piece.source) else { continue }
                let placed = edit.placements[piece.index]
                pieces.append((source, piece.range, placed.timelineTime(ofSourceTime: piece.range.start), placed.clip.speed.rate))
            }
        }
        guard !pieces.isEmpty else { return ToolOutput(text: "Nothing plays in that range.") }

        var sections: [String] = []
        var anything = false
        for piece in pieces {
            let source = piece.source
            func when(_ t: TimeInterval) -> String {
                guard let start = piece.timelineStart else { return String(format: "%7.2f", t) }
                return String(format: "%7.2f", start + (t - piece.range.start) / piece.rate)
            }
            var header = "\(source.id) \(piece.range.formatted)"
            if let start = piece.timelineStart { header = String(format: "%.2f s on the timeline: ", start) + header }
            var lines = [header]
            let events = folder.loadScreenLogEvents(for: source)
            // The state in force at the start: the last app, window and cursor before it.
            for type in [ScreenLog.EventType.app, .window] {
                if let state = events.last(where: { $0.type == type && $0.t <= piece.range.start }) {
                    lines.append("\(when(piece.range.start))  \(type.rawValue) \(Self.place(state)) (at the start)")
                }
            }
            var entries: [(TimeInterval, String)] = []
            for event in events where event.t > piece.range.start && event.t < piece.range.end {
                switch event.type {
                case .area, .cursor: continue
                case .app, .window: entries.append((event.t, "\(event.type.rawValue) \(Self.place(event))"))
                case .click:
                    let count = (event.count ?? 1) > 1 ? " ×\(event.count ?? 2)" : ""
                    entries.append((event.t, "click \(event.button?.rawValue ?? "left")\(count)\(Self.point(event.at)) on \(Self.place(event))"))
                case .drag:
                    entries.append((event.t, "drag\(Self.point(event.at)) to\(Self.point(event.to)) until \(when(event.end ?? event.t).trimmingCharacters(in: .whitespaces)) on \(Self.place(event))"))
                case .keys:
                    entries.append((event.t, "typed \(event.count ?? 0) keys until \(when(event.end ?? event.t).trimmingCharacters(in: .whitespaces)) in \(Self.place(event))"))
                case .shortcut:
                    let symbols = (event.modifiers ?? []).map { modifier in
                        switch modifier {
                        case .control: "⌃"
                        case .option: "⌥"
                        case .shift: "⇧"
                        case .command: "⌘"
                        }
                    }.joined()
                    let count = (event.count ?? 1) > 1 ? " ×\(event.count ?? 1)" : ""
                    entries.append((event.t, "\(symbols) shortcut\(count) in \(Self.place(event))"))
                case .scroll:
                    entries.append((event.t, String(format: "scroll dx %.0f dy %.0f until %@ on %@", event.dx ?? 0, event.dy ?? 0, when(event.end ?? event.t).trimmingCharacters(in: .whitespaces), Self.place(event))))
                }
            }
            if let analysis = try folder.loadScreenAnalysis(for: source.id) {
                for change in analysis.changes where change.end > piece.range.start && change.start < piece.range.end {
                    entries.append((max(change.start, piece.range.start), "changing until \(when(min(change.end, piece.range.end)).trimmingCharacters(in: .whitespaces))"))
                }
                for still in analysis.stills where still.start >= piece.range.start && still.start < piece.range.end {
                    var line = "still until \(when(min(still.end, piece.range.end)).trimmingCharacters(in: .whitespaces))"
                    if let text = still.text, !text.isEmpty {
                        let all = still.plainText.replacingOccurrences(of: "\n", with: " · ")
                        line += " · text: “\(fullText || all.count <= 300 ? all : String(all.prefix(300)) + "…")”"
                    } else if !analysis.readText {
                        line += " (Save screen text is off)"
                    }
                    entries.append((still.start, line))
                }
            } else if source.track(.screen) != nil {
                lines.append("        The screen hasn't been read yet: when it changes, goes still and its text come after processing.")
            }
            if pointer {
                let path = folder.loadPointerPath(for: source).filter { $0.t >= piece.range.start && $0.t < piece.range.end }
                // A few a second is plenty to follow it.
                var last = -Double.infinity
                for sample in path where sample.t - last >= 0.25 {
                    entries.append((sample.t, String(format: "pointer %.2f, %.2f", sample.x, sample.y)))
                    last = sample.t
                }
            }
            anything = anything || !entries.isEmpty
            lines += entries.sorted { $0.0 < $1.0 }.map { "\(when($0.0))  \($0.1)" }
            sections.append(lines.joined(separator: "\n"))
        }
        var text = "Times are seconds of the edited timeline\(pieces.first?.timelineStart == nil ? " (here, the source's own time)" : ""). Positions are fractions of the recorded area from its top left.\n\n"
        text += sections.joined(separator: "\n\n")
        if !anything { text += "\n\nNothing was logged here: no screen log or screen reading for this stretch." }
        return ToolOutput(text: text)
    }

    static func place(_ event: ScreenLog.Event) -> String {
        var text = event.app ?? "an app"
        if let window = event.window, !window.isEmpty { text += " — “\(window)”" }
        return text
    }

    static func point(_ point: ScreenLog.Point?) -> String {
        guard let point else { return "" }
        return String(format: " at %.2f, %.2f%@", point.x, point.y, point.isInArea ? "" : " (outside the area)")
    }
}

/// When a piece of text shows on screen.
struct FindOnScreenTool: EditorTool {
    let name = "find_on_screen"
    let description = """
        When a piece of text appears on screen, from the text read at each still moment of the screen \
        recording: each match with its time on the edited timeline (or "not in the edit" when that part was \
        cut), its source time, and the line it's in. Ignores case. Use it to find where a page loads, an error \
        shows, or a key or password is visible, to cut it or to freeze on it.
        """
    var inputSchema: Value {
        Schema.object(
            ["project": Schema.project, "text": Schema.string("The text to look for.")],
            required: ["project", "text"]
        )
    }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let query = try arguments.string("text")
        let project = try folder.loadProject()
        let edit = try folder.loadEdit()
        var lines: [String] = []
        var read = false
        for source in project.sources {
            guard let analysis = try folder.loadScreenAnalysis(for: source.id) else { continue }
            read = read || analysis.readText
            for (still, matches) in analysis.find(query) {
                let times = edit.timelinePieces(of: TimeRange(start: still.start, end: max(still.end, still.start + 0.001)), in: source.id)
                let timeline = times.isEmpty ? "not in the edit" : times.map { String(format: "%.2f s", $0.timeline.start) }.joined(separator: ", ")
                for line in matches.prefix(3) {
                    lines.append(String(format: "%@ · %@ %.2f–%.2f s · “%@”", timeline, source.id.description, still.start, still.end, line.text))
                }
            }
        }
        if lines.isEmpty {
            return ToolOutput(text: read ? "“\(query)” wasn't seen on screen." : "No screen text has been read for this project: it comes after processing, with Save screen text on.")
        }
        return ToolOutput(text: "“\(query)” on screen, by timeline time:\n" + lines.joined(separator: "\n"))
    }
}
