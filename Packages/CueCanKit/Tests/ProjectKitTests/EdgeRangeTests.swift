import Foundation
import Testing
@testable import ProjectKit

struct EdgeRangeTests {
    private let source = SourceID(number: 1)
    private func clip(_ id: Int, _ start: Double, _ end: Double) -> Clip {
        Clip(id: ClipID(number: id), source: source, sourceIn: start, sourceOut: end)
    }

    @Test func recordingEndsAndMinimumDurationBoundBothEdges() throws {
        let edit = Edit(main: [clip(1, 2, 6)])
        let start = try #require(edit.edgeRange(.start, of: ClipID(number: 1), sourceDuration: 10))
        let end = try #require(edit.edgeRange(.end, of: ClipID(number: 1), sourceDuration: 10))
        #expect(start.lowerBound == 0)
        #expect(abs(start.upperBound - 5.98) < 1e-9)
        #expect(abs(end.lowerBound - 2.02) < 1e-9)
        #expect(end.upperBound == 10)
    }

    @Test func aGapStopsAtTheOtherEdgeAndARollPreservesTheNeighbour() throws {
        let gap = Edit(main: [clip(1, 0, 3), clip(2, 5, 10)])
        #expect(gap.edgeRange(.end, of: ClipID(number: 1), sourceDuration: 10)?.upperBound == 5)
        #expect(gap.edgeRange(.start, of: ClipID(number: 2), sourceDuration: 10)?.lowerBound == 3)
        let roll = Edit(main: [clip(1, 0, 5), clip(2, 5, 10)])
        let end = try #require(roll.edgeRange(.end, of: ClipID(number: 1), sourceDuration: 10))
        let start = try #require(roll.edgeRange(.start, of: ClipID(number: 2), sourceDuration: 10))
        #expect(abs(end.upperBound - 9.98) < 1e-9)
        #expect(abs(start.lowerBound - 0.02) < 1e-9)
    }

    @Test func everyBoundCanBeCommittedThroughTheExactEditOperation() throws {
        let configurations = [Edit(main: [clip(1, 2, 6)]), Edit(main: [clip(1, 0, 5), clip(2, 5, 10)])]
        for original in configurations {
            for clip in original.main {
                for edge in ClipEdge.allCases {
                    let range = try #require(original.edgeRange(edge, of: clip.id, sourceDuration: 10))
                    for bound in [range.lowerBound, range.upperBound] {
                        var edit = original
                        _ = try edit.setEdge(edge, of: clip.id, to: bound, sourceDuration: 10, byHand: true)
                        #expect(edit.main.allSatisfy { $0.playedRange.duration >= Edit.minimumClipDuration - 1e-9 })
                    }
                }
            }
        }
    }
}
