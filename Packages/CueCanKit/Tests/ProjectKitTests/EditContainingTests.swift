import Testing
@testable import ProjectKit

@Suite struct EditContainingTests {
    let screen = SourceID(number: 1)
    let other = SourceID(number: 2)

    var edit: Edit {
        Edit(main: [
            Clip(id: ClipID(number: 1), source: screen, sourceIn: 0, sourceOut: 5),
            Clip(id: ClipID(number: 2), source: other, sourceIn: 6, sourceOut: 9),
            Clip(id: ClipID(number: 3), source: screen, sourceIn: 6, sourceOut: 9),
        ])
    }

    @Test func holdBelongsToTheClipPlayingItsStretch() {
        let freeze = Freeze(id: FreezeID(number: 1), source: screen, range: TimeRange(start: 7, end: 8))
        #expect(edit.clip(holding: freeze)?.id == ClipID(number: 3))
    }

    @Test func holdOutsideEveryClipHasNone() {
        let freeze = Freeze(id: FreezeID(number: 1), source: screen, range: TimeRange(start: 5, end: 6))
        #expect(edit.clip(holding: freeze) == nil)
    }

    @Test func positionsCountFromOne() {
        #expect(edit.position(of: ClipID(number: 3)) == 3)
        #expect(edit.position(of: ClipID(number: 9)) == nil)
    }
}
