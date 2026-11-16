import Testing
@testable import ProjectKit

struct ClipPickingTests {
    let clips = (1...5).map { ClipID(number: $0) }

    @Test func shiftExtendsFromTheOriginalAnchorInEitherDirection() {
        var picking = ClipPicking()
        var selected = picking.pick(clips[1], mode: .replace, selected: [], ordered: clips)
        selected = picking.pick(clips[4], mode: .extend, selected: selected, ordered: clips)
        #expect(selected == Set(clips[1...4]))
        selected = picking.pick(clips[0], mode: .extend, selected: selected, ordered: clips)
        #expect(selected == Set(clips[0...1]))
    }

    @Test func commandTogglesOneClipWithoutSelectingThoseBetween() {
        var picking = ClipPicking()
        var selected = picking.pick(clips[0], mode: .replace, selected: [], ordered: clips)
        selected = picking.pick(clips[4], mode: .toggle, selected: selected, ordered: clips)
        #expect(selected == [clips[0], clips[4]])
        selected = picking.pick(clips[4], mode: .toggle, selected: selected, ordered: clips)
        #expect(selected == [clips[0]])
    }

    @Test func aRemovedAnchorFallsBackToAnExistingSelection() {
        var picking = ClipPicking()
        var selected = picking.pick(clips[0], mode: .replace, selected: [], ordered: clips)
        selected = picking.pick(clips[2], mode: .toggle, selected: selected, ordered: clips)
        selected = picking.pick(clips[4], mode: .extend, selected: selected, ordered: [clips[0], clips[1], clips[3], clips[4]])
        #expect(selected == [clips[0], clips[1], clips[3], clips[4]])
    }

    @Test func clearingStartsTheNextShiftPickAtItsOwnClip() {
        var picking = ClipPicking()
        _ = picking.pick(clips[0], mode: .replace, selected: [], ordered: clips)
        picking.clear()
        let selected = picking.pick(clips[4], mode: .extend, selected: [], ordered: clips)
        #expect(selected == [clips[4]])
    }
}
