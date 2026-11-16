import Foundation
import Testing
@testable import ProjectKit

/// Framing the camera (docs/decisions.md, 52): a point and a zoom, kept in the edit.
@Suite struct CameraFramingTests {
    @Test func nonFiniteInputsCannotProduceAnInvalidCropOrUnencodableEdit() throws {
        let framing = CameraFraming(centerX: .nan, centerY: -.infinity, zoom: .nan)
        #expect(framing.centerX == 0.5)
        #expect(framing.centerY == 0)
        #expect(framing.zoom == 1)
        #expect(framing.zoomed(to: .infinity).zoom == 3)
        #expect(framing.zoomed(to: 2).centerY == 0)
        _ = try ProjectJSON.encoder.encode(framing)
    }

    @Test func aFramingStaysOnThePictureAndInRange() {
        let framing = CameraFraming(centerX: 1.4, centerY: -0.2, zoom: 9)
        #expect(framing.centerX == 1)
        #expect(framing.centerY == 0)
        #expect(framing.zoom == 3)
        #expect(CameraFraming(centerX: 0.5, centerY: 0.5, zoom: 0.2).zoom == 1)
        #expect(CameraFraming.centered.isCentered)
    }

    @Test func eachSlotIsFramedOnItsOwn() {
        var edit = Edit()
        let source = SourceID(number: 1)
        #expect(edit.framings(for: source).framing(for: .card) == .centered)
        let bubble = CameraFraming(centerX: 0.4, centerY: 0.35, zoom: 1.3)
        edit.setFraming(bubble, slot: .card, for: source)
        let framings = edit.framings(for: source)
        #expect(framings.framing(for: .card) == bubble)
        #expect(framings.framing(for: .split) == .centered, "Framing the card never changes the large camera.")
        edit.setFramings(CameraFramings(), for: source)
        #expect(edit.camera.isEmpty)
    }

    /// No slot is framed once for the video and again for the Short (docs/decisions.md, 77).
    @Test func noSlotBelongsToOneShape() {
        #expect(CameraSlot.allCases == [.card, .split, .fullScreen])
    }

    @Test func aFullScreenCameraStartsFromSplits() {
        let split = CameraFraming(centerX: 0.45, centerY: 0.4, zoom: 1.2)
        var framings = CameraFramings([.split: split])
        #expect(framings.framing(for: .fullScreen) == split)
        let full = CameraFraming(centerX: 0.6, centerY: 0.5, zoom: 1.1)
        framings[.fullScreen] = full
        #expect(framings.framing(for: .fullScreen) == full, "Once framed, it's its own.")
        #expect(CameraFramings().framing(for: .fullScreen) == .centered)
    }

    @Test func anUnknownSlotIsAnError() {
        let unknown = Data(#"{"somethingNew": {"centerX": 0.1, "centerY": 0.1, "zoom": 2}}"#.utf8)
        #expect(throws: DecodingError.self) { try ProjectJSON.decoder.decode(CameraFramings.self, from: unknown) }
    }

    @Test func framingRoundTrips() throws {
        var edit = Edit()
        edit.setFraming(CameraFraming(centerX: 0.4, centerY: 0.35, zoom: 1.3), slot: .split, for: SourceID(number: 2))
        let data = try ProjectJSON.encoder.encode(edit)
        #expect(try ProjectJSON.decoder.decode(Edit.self, from: data) == edit)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"src_2\""))
        #expect(text.contains("\"split\""))
    }
}
