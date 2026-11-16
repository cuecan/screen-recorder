import Foundation
import ProcessingKit
import ProjectKit

/// What an editing tool says back: what it did, then the edit as it now stands.
enum EditingOutput {
    static func after(_ message: String, edit: Edit, folder: ProjectFolder) throws -> ToolOutput {
        let summary = try ToolOutput.json(EditSummary(edit: edit, project: try folder.loadProject(), transcripts: try folder.loadTranscripts()))
        return ToolOutput(text: message + "\n\n" + summary.text)
    }

    /// The same, with the clip edges the change made or moved checked by their sound (docs/decisions.md, 75):
    /// any that sound runs across are named, with how far to nudge them.
    static func afterChecking(_ message: String, before: Edit, edit: Edit, folder: ProjectFolder) async throws -> ToolOutput {
        let check = await EdgeCheck(before: before, after: edit, folder: folder)
        var text = message
        if let warning = check.warning { text += "\n\n" + warning }
        let summary = try ToolOutput.json(EditSummary(edit: edit, project: try folder.loadProject(), transcripts: try folder.loadTranscripts(),
                                                      edgeSounds: check.now))
        return ToolOutput(text: text + "\n\n" + summary.text)
    }
}

/// Clip edges checked against each source's measured levels.
struct EdgeCheck {
    /// Every edge sound runs across in the edit now.
    let now: [EdgeSound]
    /// Sources that play sound in the edit but have no levels, so their edges weren't checked.
    let unchecked: [SourceID]
    /// What to tell Claude about edges the change made or moved, or nil when there's nothing.
    let warning: String?

    init(before: Edit? = nil, after edit: Edit, folder: ProjectFolder) async {
        let sources = Self.soundSources(edit).union(before.map(Self.soundSources) ?? [])
        let levels = await SourceLevelsMeasure.levels(for: sources, in: folder)
        now = EdgeSound.edges(in: edit, levels: levels)
        // A source with no audio has nothing to check.
        let project = try? folder.loadProject()
        unchecked = Self.soundSources(edit)
            .filter { levels[$0] == nil && project?.source($0)?.primaryAudioTrack != nil }
            .sorted { $0.number < $1.number }
        var lines: [String] = []
        if let before {
            let new = EdgeSound.new(in: now, comparedTo: EdgeSound.edges(in: before, levels: levels))
            if !new.isEmpty {
                lines.append("May catch a word: sound runs right across \(new.count == 1 ? "this edge" : "these edges"), measured against the recording's own silence level. You can't hear it, so check with preview or the creator, or nudge it clear.")
                lines += new.map(Self.describe)
            }
        } else if !now.isEmpty {
            lines.append("May catch a word: sound runs right across \(now.count) clip \(now.count == 1 ? "edge" : "edges"), measured against the recording's own silence level. Each is under its clip's soundAtEdges, with the nudge_cut that clears it.")
        }
        if !unchecked.isEmpty {
            lines.append("The sound at the edges of \(unchecked.map(\.description).joined(separator: ", ")) wasn't checked: its audio couldn't be measured.")
        }
        warning = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func soundSources(_ edit: Edit) -> Set<SourceID> {
        Set(edit.main.map { $0.audio?.source ?? $0.source })
    }

    /// One edge, in words, with the nudges that clear it.
    static func describe(_ sound: EdgeSound) -> String {
        let reach = EdgeSound.reach
        func seconds(_ value: TimeInterval) -> String {
            value >= reach - 0.005 ? "more than \(Int(reach)) s" : String(format: "%.2f s", value)
        }
        var line = "- \(sound.clip) \(sound.edge.rawValue), at \(String(format: "%.2f", sound.timelineTime)) s on the timeline "
            + "(\(String(format: "%.2f", sound.sourceTime)) s in the source): \(String(format: "%.0f", sound.overSilence)) dB over the silence level. "
            + "The sound started \(seconds(sound.soundBefore)) before the edge and runs on \(seconds(sound.soundAfter)) after it."
        // nudge_cut moves an edge later with a positive number, in the source's time.
        let outward = sound.edge == .start ? -1.0 : 1.0
        var nudges: [String] = []
        if sound.toKeepIt < reach - 0.005 { nudges.append("to keep it whole, by \(milliseconds(outward * sound.toKeepIt)) ms") }
        if sound.toLeaveItOut < reach - 0.005 { nudges.append("to leave it out, by \(milliseconds(-outward * sound.toLeaveItOut)) ms") }
        if !nudges.isEmpty {
            line += " nudge_cut the \(sound.edge.rawValue) \(nudges.joined(separator: ", or "))."
        } else {
            line += " There's no quiet within \(Int(reach)) s either side: this is running speech."
        }
        // A dip between words or syllables is the smaller move (docs/decisions.md, 74).
        var dips: [String] = []
        if let earlier = sound.dipBefore { dips.append("\(milliseconds(-earlier)) ms") }
        if let later = sound.dipAfter { dips.append("\(milliseconds(later)) ms") }
        if !dips.isEmpty {
            line += " To cut between words instead, at the nearest dip in the sound: nudge_cut the \(sound.edge.rawValue) by \(dips.joined(separator: " or "))."
        }
        return line
    }

    private static func milliseconds(_ seconds: TimeInterval) -> String {
        let value = Int((seconds * 1000).rounded())
        return value > 0 ? "+\(value)" : "\(value)"
    }
}
