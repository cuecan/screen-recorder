import Foundation
import Testing
@testable import ProjectKit

/// The audio lane's level lines (docs/decisions.md, 71): where a level's line sits, and dragging it.
struct AudioLaneTests {
    let source = SourceID(number: 1)

    func context(_ edit: Edit, tool: TimelineTool = .select) -> TimelineInteraction.Context {
        .init(edit: edit, transcripts: TranscriptIndex([talkingHead]), zoom: 100, snapping: false,
              selection: .none, tool: tool, playhead: 0, snapper: EditSnapper(transcripts: TranscriptIndex([talkingHead])))
    }

    func twoClips(firstLevel: Double = 0) -> Edit {
        Edit(main: [
            Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 2, voiceLevel: firstLevel),
            Clip(id: ClipID(number: 2), source: source, sourceIn: 3, sourceOut: 5),
        ])
    }

    func onLine(_ time: Double, level: Double) -> CGPoint {
        CGPoint(x: TimelineLane.leading + time * 100, y: AudioLane.lineY(for: level))
    }

    @Test func zeroDecibelsSitsThreeQuartersUpAndTheScaleRunsBothWays() {
        #expect(AudioLane.fraction(of: 0) == 0.75)
        #expect(AudioLane.fraction(of: 12) == 1)
        #expect(AudioLane.fraction(of: -60) == 0)
        let levels = Array(stride(from: -60.0, through: 12, by: 1))
        let fractions = levels.map(AudioLane.fraction(of:))
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 }, "Louder is always higher.")
        #expect(levels.allSatisfy { AudioLane.level(atFraction: AudioLane.fraction(of: $0)) == $0 }, "Every whole decibel reads back.")
        #expect(levels.allSatisfy { AudioLane.level(atY: AudioLane.lineY(for: $0)) == $0 })
        // Near 0 dB a decibel is most of a point, so the line can be set by hand.
        let step = AudioLane.lineY(for: -1) - AudioLane.lineY(for: 0)
        #expect(step > 0.6 && step < 1.5, "\(step)")
        #expect(AudioLane.voice.contains(AudioLane.lineY(for: 12)) && AudioLane.voice.contains(AudioLane.lineY(for: -60)))
        #expect(AudioLane.system.lowerBound > AudioLane.voice.upperBound)
        #expect(AudioLane.system.upperBound < TimelineLane.audio.top + TimelineLane.audio.height)
    }

    @Test func pressingTheLinePicksItUpAndElsewhereTheClip() {
        let edit = twoClips(firstLevel: -6)
        let interaction = TimelineInteraction()
        #expect(interaction.hit(onLine(1, level: -6), in: context(edit)) == .voiceLevel(ClipID(number: 1)))
        #expect(interaction.hit(onLine(1, level: 0), in: context(edit)) == .clip(ClipID(number: 1), edge: nil), "Its line is lower.")
        #expect(interaction.hit(onLine(1, level: -6), in: context(edit, tool: .blade)) == .clip(ClipID(number: 1), edge: nil))
    }

    @Test func draggingTheLineSetsTheLevelAsOneAction() {
        let edit = twoClips()
        var interaction = TimelineInteraction()
        let origin = onLine(3, level: 0)
        // Pressed a point below the line's middle: the line still moves from where it was.
        let pressed = CGPoint(x: origin.x, y: origin.y + 1)
        let target = AudioLane.lineY(for: -6) + 1
        _ = interaction.changed(from: pressed, to: CGPoint(x: origin.x + 30, y: target), in: context(edit))
        #expect(interaction.drag == .level(clip: ClipID(number: 2), start: 0, current: -6))
        let actions = interaction.ended(from: pressed, to: CGPoint(x: origin.x + 30, y: target), in: context(edit))
        #expect(actions == [.setVoiceLevel(ClipID(number: 2), -6), .select(.clips([ClipID(number: 2)]))])
    }

    @Test func aClickOnTheLineOnlySelectsTheClip() {
        let edit = twoClips()
        var interaction = TimelineInteraction()
        let origin = onLine(3, level: 0)
        _ = interaction.changed(from: origin, to: origin, in: context(edit))
        #expect(interaction.ended(from: origin, to: origin, in: context(edit)) == [.click(.clip(ClipID(number: 2), edge: nil))])
    }

    @Test func theLineStopsAtTheTopAndTheBottom() {
        let edit = twoClips()
        var interaction = TimelineInteraction()
        let origin = onLine(1, level: 0)
        _ = interaction.changed(from: origin, to: CGPoint(x: origin.x, y: origin.y - 500), in: context(edit))
        #expect(interaction.drag == .level(clip: ClipID(number: 1), start: 0, current: 12))
        _ = interaction.changed(from: origin, to: CGPoint(x: origin.x, y: origin.y + 500), in: context(edit))
        #expect(interaction.drag == .level(clip: ClipID(number: 1), start: 0, current: -60))
    }
}
