import Foundation
import ProjectKit

/// Captures inputs once for a trim gesture. The owner serializes requests and keeps only the latest
/// waiting target; this actor keeps file reads and candidate composition work away from the UI actor.
public actor TrimPreviewSession {
    private let inputs: RenderInputs

    public init(folder: ProjectFolder) throws { inputs = try RenderInputs.load(folder) }

    public func frames(for plan: TrimPreviewPlan) async throws -> TrimPreviewFrames {
        try Task.checkCancellation()
        let changed = inputs.withEdit { $0 = plan.edit }
        let output = inputs.project.effectiveFormat.outputs.first ?? .landscape
        let built = try await CompositionBuilder.build(changed, output: output, scale: 0.25)
        try Task.checkCancellation()
        let placements = plan.edit.placements
        func visibleTime(_ frame: TrimPreviewPlan.Frame?) -> TimeInterval? {
            guard let frame, let placed = placements.first(where: { $0.clip.id == frame.clip }) else { return nil }
            let time = frame.time
            // Never substitute a picture from the other clip.
            guard time >= placed.timeline.start - 1e-9, time < placed.timeline.end - 1e-9 else { return nil }
            return time
        }
        let outgoing = visibleTime(plan.outgoing)
        let incoming = visibleTime(plan.incoming)
        let times = [outgoing, incoming].compactMap { $0 }
        guard !times.isEmpty else { return TrimPreviewFrames(outgoing: nil, incoming: nil) }
        let stills = try await FrameGrabber.stills(of: built, at: times, maximumWidth: 320)
        return TrimPreviewFrames(outgoing: outgoing == nil ? nil : stills.first,
                                 incoming: incoming == nil ? nil : stills.last)
    }
}
