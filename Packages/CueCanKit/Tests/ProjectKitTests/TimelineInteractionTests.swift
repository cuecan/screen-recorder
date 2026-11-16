import Foundation
import Testing
@testable import ProjectKit

struct TimelineInteractionTests {
    let source = SourceID(number: 1)
    func clip(_ id: Int, _ start: Double, _ end: Double, rate: Double = 1) throws -> Clip {
        Clip(id: ClipID(number: id), source: source, sourceIn: start, sourceOut: end,
             speed: try #require(ClipSpeed(rate: rate)))
    }
    func context(_ edit: Edit, selection: EditorSelection = .none, snapping: Bool = false) -> TimelineInteraction.Context {
        .init(edit: edit, transcripts: TranscriptIndex([talkingHead]), zoom: 100, snapping: snapping,
              selection: selection, tool: .select, playhead: 0,
              snapper: EditSnapper(transcripts: TranscriptIndex([talkingHead])))
    }
    func point(_ time: Double, lane: TimelineLane = .video) -> CGPoint {
        CGPoint(x: TimelineLane.leading + time * 100, y: lane.top + 10)
    }

    @Test func aSelectedEdgeWinsAtAJoinAndSmallMovementsOnlySelect() throws {
        let edit = Edit(main: [try clip(1, 0, 2), try clip(2, 3, 5)])
        let context = context(edit, selection: .clips([ClipID(number: 1)]))
        var interaction = TimelineInteraction()
        let origin = point(2)
        #expect(interaction.hit(origin, in: context) == .clip(ClipID(number: 1), edge: .end))
        _ = interaction.changed(from: origin, to: point(2.02), in: context)
        let actions = interaction.ended(from: origin, to: point(2.02), in: context)
        #expect(actions == [.select(.clipEdge(clip: ClipID(number: 1), edge: .end))])
        #expect(interaction.state == .idle)
    }

    @Test func trimmingUsesSourceSpeedAndStopsAtTheNeighbour() throws {
        let edit = Edit(main: [try clip(1, 0, 2, rate: 2), try clip(2, 3, 5)])
        let context = context(edit, selection: .clips([ClipID(number: 1)]))
        var interaction = TimelineInteraction()
        _ = interaction.changed(from: point(1), to: point(1.4), in: context)
        let actions = interaction.ended(from: point(1), to: point(1.4), in: context)
        #expect(actions == [.trim(ClipID(number: 1), .end, 2.8, rolling: false)])
        _ = interaction.changed(from: point(1), to: point(4), in: context)
        let limited = interaction.ended(from: point(1), to: point(4), in: context)
        #expect(limited == [.trim(ClipID(number: 1), .end, 3, rolling: false)])
    }

    // MARK: - Rolling a join (the Trim tool only)

    func context(_ edit: Edit, tool: TimelineTool) -> TimelineInteraction.Context {
        .init(edit: edit, transcripts: TranscriptIndex([talkingHead]), zoom: 100, snapping: false,
              selection: .none, tool: tool, playhead: 0, snapper: EditSnapper(transcripts: TranscriptIndex([talkingHead])))
    }

    @Test func theTrimToolPressedOnAJoinRollsItEitherWay() throws {
        // The halves of a split: 0–3 and 3–6 of the same recording.
        let edit = Edit(main: [try clip(1, 0, 3), try clip(2, 3, 6)])
        let trim = context(edit, tool: .trim)
        for origin in [2.98, 3.02] {
            var interaction = TimelineInteraction()
            _ = interaction.changed(from: point(origin), to: point(origin - 1), in: trim)
            #expect(interaction.ended(from: point(origin), to: point(origin - 1), in: trim) == [.trim(ClipID(number: 2), .start, 2, rolling: true)],
                    "Earlier, the later clip's start moves out, whichever side of the join was pressed.")
            _ = interaction.changed(from: point(origin), to: point(origin + 1), in: trim)
            #expect(interaction.ended(from: point(origin), to: point(origin + 1), in: trim) == [.trim(ClipID(number: 1), .end, 4, rolling: true)])
        }
        // It changes direction mid-drag with the pointer.
        var interaction = TimelineInteraction()
        _ = interaction.changed(from: point(3), to: point(2), in: trim)
        _ = interaction.changed(from: point(3), to: point(4.5), in: trim)
        #expect(interaction.ended(from: point(3), to: point(4.5), in: trim) == [.trim(ClipID(number: 1), .end, 4.5, rolling: true)])
        // The edit it makes moves both edges.
        var rolled = edit
        try rolled.setEdge(.start, of: ClipID(number: 2), to: 2, sourceDuration: 7, rolling: true)
        #expect(rolled.main.map(\.playedRange) == [TimeRange(start: 0, end: 2), TimeRange(start: 2, end: 6)])
    }

    @Test func theTrimToolAwayFromTheJoinTrimsTheNearerEdgeWithoutRolling() throws {
        let edit = Edit(main: [try clip(1, 0, 3), try clip(2, 3, 6)])
        let trim = context(edit, tool: .trim)
        var interaction = TimelineInteraction()
        // In the second clip's body, nearer its start: inward it trims that clip alone.
        _ = interaction.changed(from: point(3.5), to: point(4), in: trim)
        #expect(interaction.ended(from: point(3.5), to: point(4), in: trim) == [.trim(ClipID(number: 2), .start, 3.5, rolling: false)])
        // Outward it has nowhere to go, so the edge is only picked.
        _ = interaction.changed(from: point(3.5), to: point(2.5), in: trim)
        #expect(interaction.ended(from: point(3.5), to: point(2.5), in: trim) == [.select(.clipEdge(clip: ClipID(number: 2), edge: .start))])
    }

    @Test func theSelectToolNeverRollsAJoin() throws {
        var edit = Edit(main: [try clip(1, 0, 3), try clip(2, 3, 6)])
        let select = context(edit, tool: .select)
        var interaction = TimelineInteraction()
        // Outward from either side of the join, nothing moves.
        for (origin, to) in [(2.98, 4.0), (3.02, 2.0)] {
            _ = interaction.changed(from: point(origin), to: point(to), in: select)
            let actions = interaction.ended(from: point(origin), to: point(to), in: select)
            #expect(actions.count == 1)
            guard case .select(.clipEdge) = actions.first else { Issue.record("Expected only a picked edge, got \(actions)."); continue }
        }
        // Inward it trims the one clip, as before.
        _ = interaction.changed(from: point(2.98), to: point(1.98), in: select)
        #expect(interaction.ended(from: point(2.98), to: point(1.98), in: select) == [.trim(ClipID(number: 1), .end, 2, rolling: false)])
        // The edit model, asked not to roll, stops an outward edge at the join and leaves the neighbour.
        try edit.setEdge(.end, of: ClipID(number: 1), to: 4, sourceDuration: 7, rolling: false)
        #expect(edit.main.map(\.playedRange) == [TimeRange(start: 0, end: 3), TimeRange(start: 3, end: 6)])
        #expect(edit.edgeRange(.end, of: ClipID(number: 1), sourceDuration: 7, rolling: false)?.upperBound == 3)
        let nudged = try edit.nudge(.end, of: ClipID(number: 1), by: 0.5, transcripts: TranscriptIndex([talkingHead]), rolling: false)
        #expect(nudged.clip.playedRange.end == 3 && edit.main[1].playedRange.start == 3)
    }

    @Test func anExternalEditCancelsUntilThePointerIsReleased() throws {
        var edit = Edit(main: [try clip(1, 0, 7)])
        var interaction = TimelineInteraction()
        _ = interaction.changed(from: point(7), to: point(6), in: context(edit))
        edit.revision += 1
        let updated = context(edit)
        _ = interaction.changed(from: point(7), to: point(5), in: updated)
        #expect(interaction.state == .cancelled)
        _ = interaction.changed(from: point(7), to: point(4), in: updated)
        #expect(interaction.state == .cancelled)
        let actions = interaction.ended(from: point(7), to: point(4), in: updated)
        #expect(actions.isEmpty)
        #expect(interaction.state == .idle)
    }

    @Test func movingAnOverlayClampsAtZeroAndResizingKeepsADuration() throws {
        var edit = Edit(main: [try clip(1, 0, 7)])
        let overlay = try edit.placeOverlay(.file(at: URL(filePath: "/tmp/fixture.png")), overTimeline: TimeRange(start: 1, end: 3))
        let context = context(edit)
        var interaction = TimelineInteraction()
        _ = interaction.changed(from: point(2, lane: .overlays), to: point(-2, lane: .overlays), in: context)
        let moved = interaction.ended(from: point(2, lane: .overlays), to: point(-2, lane: .overlays), in: context)
        #expect(moved == [.moveOverlay(overlay.id, TimeRange(start: 0, end: 2)), .select(.overlays([overlay.id]))])
        _ = interaction.changed(from: point(3, lane: .overlays), to: point(0, lane: .overlays), in: context)
        let resized = interaction.ended(from: point(3, lane: .overlays), to: point(0, lane: .overlays), in: context)
        #expect(resized == [.moveOverlay(overlay.id, TimeRange(start: 1, end: 1.1)), .select(.overlays([overlay.id]))])
    }

    @Test func aRepeatedFreezeUsesTheSpeedOfTheHoveredOccurrence() throws {
        var edit = Edit(main: [try clip(1, 0, 7), try clip(2, 0, 7, rate: 2)])
        let freeze = try #require(try edit.freeze(timeline: TimeRange(start: 2, end: 4)).first)
        let context = context(edit)
        var interaction = TimelineInteraction()
        let origin = CGPoint(x: point(9).x, y: TimelineLane.video.top + TimelineLane.video.height - 5)
        let end = CGPoint(x: origin.x + 25, y: origin.y)
        _ = interaction.changed(from: origin, to: end, in: context)
        let actions = interaction.ended(from: origin, to: end, in: context)
        #expect(actions == [.stretchFreeze(freeze.id, TimeRange(start: 2, end: 4.5)), .select(.freeze(freeze.id))])
    }

    @Test func scrubbingUsesTheSharedSnapPoints() throws {
        let context = context(Edit(main: [try clip(1, 0, 7)]), snapping: true)
        var interaction = TimelineInteraction()
        let origin = CGPoint(x: 9, y: 5)
        let target = CGPoint(x: 12, y: 5)
        let time = interaction.changed(from: origin, to: target, in: context)
        #expect(time == 0)
        let actions = interaction.ended(from: origin, to: target, in: context)
        #expect(actions.isEmpty)
    }

    @Test func shortClipsRemainSelectableWhenFitMakesTheirEdgesOverlap() throws {
        let edit = Edit(main: [try clip(1, 0, 0.05), try clip(2, 1, 1.05), try clip(3, 2, 2.05)])
        let context = context(edit, selection: .clips([ClipID(number: 1)]))
        let hit = TimelineInteraction().hit(point(0.075), in: context)
        #expect(hit == .clip(ClipID(number: 2), edge: nil))
    }

    @Test func explicitlyPickedEdgesStillTrimAShortClip() throws {
        let edit = Edit(main: [try clip(1, 0, 0.05), try clip(2, 1, 1.05)])
        let context = context(edit, selection: .clipEdge(clip: ClipID(number: 1), edge: .end))
        let hit = TimelineInteraction().hit(point(0.05), in: context)
        #expect(hit == .clip(ClipID(number: 1), edge: .end))
    }

    @Test func fitScaleKeepsAUsefulBodyEvenWithAnotherClipsEdgeSelected() throws {
        let edit = Edit(main: [try clip(1, 0, 0.15), try clip(2, 1, 1.15)])
        let context = context(edit, selection: .clipEdge(clip: ClipID(number: 1), edge: .end))
        #expect(TimelineInteraction().hit(point(0.25), in: context) == .clip(ClipID(number: 2), edge: nil))
    }

    @Test func unsnappedPointerEditsLandOnTheOutputFrameClockThroughRetiming() throws {
        let edit = Edit(main: [try clip(1, 0, 4, rate: 2)])
        let context = TimelineInteraction.Context(edit: edit, transcripts: TranscriptIndex([]), zoom: 100, snapping: false,
                                                  selection: .none, tool: .select, playhead: 0,
                                                  snapper: EditSnapper(transcripts: TranscriptIndex([])), frameDuration: 1.0 / 60)
        var interaction = TimelineInteraction()
        _ = interaction.changed(from: point(2), to: point(1.371), in: context)
        let actions = interaction.ended(from: point(2), to: point(1.371), in: context)
        guard case .trim(_, .end, let sourceTime, _) = actions.first else { Issue.record("Expected a trim."); return }
        #expect(abs(sourceTime / 2 * 60 - 82) < 0.000_001)
        let scrub = context.snapped(1.371, tolerance: 0)
        #expect(abs(scrub * 60 - 82) < 0.000_001)
    }
}
