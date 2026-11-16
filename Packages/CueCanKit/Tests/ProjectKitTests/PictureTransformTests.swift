import Foundation
import Testing
@testable import ProjectKit

struct PictureTransformTests {
    private let first = ClipID(number: 1)
    private let second = ClipID(number: 2)
    private let source = SourceID(number: 1)

    @Test func valuesStayFiniteAndInsideTheRecordedPicture() {
        #expect(PictureTransform(centerX: .nan, centerY: .infinity, zoom: -.infinity) == .identity)
        #expect(PictureTransform(centerX: -2, centerY: 9, zoom: 8) == PictureTransform(centerX: 0, centerY: 1, zoom: 3))
    }

    @Test func splitAndCutPreserveBothFramingsButResetIsLocal() throws {
        var edit = fixture()
        let screen = PictureTransform(centerX: 0.7, centerY: 0.3, zoom: 1.8)
        let camera = PictureTransform(centerX: 0.4, centerY: 0.6, zoom: 1.3)
        try edit.setTransform(screen, picture: .screen, for: [first])
        try edit.setTransform(camera, picture: .camera, for: [first])
        _ = try edit.split(at: 4)
        #expect(edit.main.count == 2)
        #expect(edit.main.allSatisfy { $0.screenTransform == screen && $0.cameraTransform == camera })
        _ = try edit.cut(timeline: TimeRange(start: 1, end: 2))
        #expect(edit.main.count == 3)
        #expect(edit.main.allSatisfy { $0.screenTransform == screen && $0.cameraTransform == camera })
        try edit.setTransform(nil, picture: .screen, for: [edit.main[1].id])
        #expect(edit.main[1].screenTransform == nil)
        #expect(edit.main[0].screenTransform == screen)
        #expect(edit.main[2].screenTransform == screen)
        #expect(edit.main.allSatisfy { $0.cameraTransform == camera })
    }

    @Test func invalidSelectionCannotPartiallyApplyAChange() throws {
        var edit = fixture()
        let original = edit
        #expect(throws: EditError.self) {
            try edit.setTransform(.init(zoom: 2), picture: .screen, for: [first, second])
        }
        #expect(edit == original)
    }

    @Test func plainTransformsAreSparseAndOverridesRoundTrip() throws {
        var edit = fixture()
        let plain = try JSONEncoder().encode(edit)
        #expect(!String(decoding: plain, as: UTF8.self).contains("Transform"))
        try edit.setTransform(.identity, picture: .screen, for: [first])
        #expect(edit.main[0].screenTransform == nil)
        // Centred camera is a real override: a take might have an off-centre default.
        try edit.setTransform(.identity, picture: .camera, for: [first])
        try edit.setTransform(.init(centerX: 0.9, zoom: 2.5), picture: .screen, for: [first])
        #expect(try JSONDecoder().decode(Edit.self, from: JSONEncoder().encode(edit)) == edit)
        #expect(edit.main[0].cameraTransform == .identity)
    }

    @Test func differentlyFramedClipsNeverMergeWhenRestoringACut() {
        var a = fixture().main[0]
        var b = a
        b.cameraTransform = .init(zoom: 1.5)
        #expect(!a.hasSamePresentation(as: b))
        a.cameraTransform = b.cameraTransform
        #expect(a.hasSamePresentation(as: b))
        b.screenTransform = .init(zoom: 2)
        #expect(!a.hasSamePresentation(as: b))
    }

    private func fixture() -> Edit {
        Edit(main: [Clip(id: first, source: source, sourceIn: 0, sourceOut: 10)])
    }
}
