import Foundation
import Testing
@testable import ProjectKit

/// Each clip's own camera side, over the inset and the rest the edit shares (docs/decisions.md, 68 and 86).
@Suite struct ClipLookTests {
    let source = SourceID(number: 1)

    func clip(_ number: Int, _ start: Double, _ end: Double, side: OutputLook.CameraSide = .standard) -> Clip {
        Clip(id: ClipID(number: number), source: source, sourceIn: start, sourceOut: end, look: ClipLook(cameraSide: side))
    }

    @Test func aClipIsDrawnWithItsOwnSideOverTheInsetAndTheRestTheEditShares() {
        var edit = Edit(main: [clip(1, 0, 4, side: .flipped), clip(2, 4, 8)])
        edit.look = EditLook(inset: .none, rounded: false, background: "#FFFFFF", mirror: true)
        #expect(edit.look(of: edit.main[0]) == OutputLook(inset: .none, rounded: false, background: "#FFFFFF", cameraSide: .flipped, mirror: true))
        // The inset is the edit's: every clip has the same (docs/decisions.md, 86).
        edit.look.inset = .large
        #expect(edit.main.map { edit.look(of: $0).inset } == [.large, .large])
    }

    @Test func theInsetIsWrittenOnceInTheEditsLookAndNeverInAClip() throws {
        var edit = Edit(main: [clip(1, 0, 4)])
        edit.look.inset = .small
        let object = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(edit)) as? [String: Any])
        #expect((object["look"] as? [String: Any])?["inset"] as? String == "small")
        let clips = try #require(object["main"] as? [[String: Any]])
        #expect((clips[0]["look"] as? [String: Any])?["inset"] == nil)
        // A look saved without an inset doesn't read: there's no older shape to fall back on (65).
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(EditLook.self, from: Data(##"{"rounded":true,"background":"#000000","mirror":false}"##.utf8))
        }
        let look = OutputLook(inset: .large, cameraSide: .flipped)
        #expect(look.shared.inset == .large && look.clip == ClipLook(cameraSide: .flipped))
    }

    @Test func aLookStartsWithShadowsAndALitEdgeAndTheyAreWrittenOnlyWhenOn() throws {
        let encoder = JSONEncoder()
        #expect(EditLook().addOns == [.shadows, .litEdge] && OutputLook().addOns == [.shadows, .litEdge])
        #expect(OutputLook.AddOn.allCases == [.shadows, .litEdge], "The spike's other five are gone.")
        let starting = try #require(String(data: try encoder.encode(EditLook()), encoding: .utf8))
        // In the add-ons' own order, so the file doesn't change from one save to the next.
        #expect(starting.contains(#""addOns":["shadows","litEdge"]"#) && !starting.contains("backdrop"))
        #expect(try JSONDecoder().decode(EditLook.self, from: Data(starting.utf8)) == EditLook())
        // With both off, nothing is written, and that reads back as both off.
        let bare = try #require(String(data: try encoder.encode(EditLook(addOns: [])), encoding: .utf8))
        #expect(!bare.contains("addOns"))
        #expect(try JSONDecoder().decode(EditLook.self, from: Data(bare.utf8)).addOns.isEmpty)
        // One that was removed doesn't read.
        let old = starting.replacingOccurrences(of: #""litEdge""#, with: #""trace""#)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(EditLook.self, from: Data(old.utf8)) }
        // A clip's look carries them from what the edit shares, and gives them back.
        let look = OutputLook(EditLook(backdrop: .glow, addOns: [.shadows]), ClipLook())
        #expect(look.backdrop == .glow && look.addOns == [.shadows] && look.shared == EditLook(backdrop: .glow, addOns: [.shadows]))
        #expect(try JSONDecoder().decode(OutputLook.self, from: try encoder.encode(look)) == look)
    }

    @Test func aBaseLookBringsItsOwnBackgroundAndThePlainColourKeepsTheLooks() {
        #expect(OutputLook(background: "#203A5C").shownBackground == "#203A5C")
        for base in OutputLook.Backdrop.allCases where base.isPreset {
            let look = OutputLook(background: "#203A5C", backdrop: base)
            #expect(look.shownBackground == (base.isDark ? "#0D0E10" : "#FFFFFF"))
            // The plain colour is kept for going back to Plain.
            #expect(look.background == "#203A5C")
        }
        #expect(OutputLook.Backdrop.allCases.filter(\.isDark) == [.ink, .glow])
        #expect(OutputLook(backdrop: .paper).backgroundComponents == (1, 1, 1))
    }

    @Test func choosingABaseLookLeavesTheAddOnsAsTheyAre() {
        var look = EditLook()
        look.choose(.paper)
        #expect(look.backdrop == .paper && look.addOns == [.shadows, .litEdge])
        look.addOns = [.litEdge]
        look.choose(.ink)
        #expect(look.addOns == [.litEdge])
        // Switched off, they stay off.
        look.addOns = []
        look.choose(.glow)
        #expect(look.addOns.isEmpty)
    }

    @Test func eachSectionsResetPutsBackItsOwnFieldsAndLeavesTheOthers() {
        let changed = EditLook(inset: .large, rounded: false, background: "#203A5C", backdrop: .ink, addOns: [.shadows], mirror: true)
        #expect(EditLook().hasStartingAppearance && EditLook().hasStartingBackground)
        #expect(!changed.hasStartingAppearance && !changed.hasStartingBackground)
        var appearance = changed
        appearance.resetAppearance()
        #expect(appearance == EditLook(background: "#203A5C", backdrop: .ink, addOns: [.shadows]))
        #expect(appearance.hasStartingAppearance && !appearance.hasStartingBackground)
        var background = changed
        background.resetBackground()
        #expect(background == EditLook(inset: .large, rounded: false, mirror: true))
        #expect(background.hasStartingBackground && !background.hasStartingAppearance)
        // Any one field off its start is enough to offer the reset.
        #expect(!EditLook(inset: .small).hasStartingAppearance && !EditLook(mirror: true).hasStartingAppearance)
        #expect(!EditLook(addOns: [.shadows]).hasStartingBackground && !EditLook(addOns: []).hasStartingBackground && !EditLook(background: "#FFFFFF").hasStartingBackground)
    }

    @Test func settingOneFieldLeavesTheOther() throws {
        var edit = Edit(main: [clip(1, 0, 4)])
        try edit.changeLook(for: ClipID(number: 1)) { $0.captions = true }
        try edit.changeLook(for: ClipID(number: 1)) { $0.cameraSide = .flipped }
        #expect(edit.main[0].look == ClipLook(cameraSide: .flipped, captions: true))
    }

    /// Nothing is kept once for the video and again for the Short (docs/decisions.md, 77).
    @Test func aClipAndAnEditEachWriteOneLook() throws {
        var edit = Edit(main: [clip(1, 0, 4)])
        // The caption style is the one thing with a value for each shape: its own sizes, never set apart.
        let styles = try JSONEncoder().encode(edit.captions)
        edit.captions = try JSONDecoder().decode(Captions.self, from: styles)
        let object = try #require(JSONSerialization.jsonObject(with: try JSONEncoder().encode(edit)) as? [String: Any])
        let rest = object.filter { $0.key != "captions" }
        let json = try #require(String(data: try JSONSerialization.data(withJSONObject: rest), encoding: .utf8))
        #expect(!json.contains("landscape") && !json.contains("vertical") && !json.contains("shortLayout") && !json.contains("looks"))
        #expect(json.contains("\"look\""))
    }

    @Test func anUnknownClipIsRefused() {
        var edit = Edit(main: [clip(1, 0, 4)])
        #expect(throws: EditError.unknownClip(ClipID(number: 9))) { try edit.changeLook(for: ClipID(number: 9)) { $0.cameraSide = .flipped } }
    }

    @Test func clipsWithDifferentLooksAreNeverJoined() {
        let one = clip(1, 0, 4)
        var other = clip(2, 4, 8)
        #expect(one.hasSamePresentation(as: other))
        other.look.cameraSide = .flipped
        #expect(!one.hasSamePresentation(as: other))
    }

    @Test func aWholeTakeStartsWithTheLookChosenWhileRecording() throws {
        var edit = Edit()
        var project = Project(title: "Look")
        let take = project.addSource(name: "Take", origin: .recorded, tracks: [
            SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
        ])
        let look = ClipLook(cameraSide: .flipped)
        let added = edit.addWholeSource(take, look: look)
        #expect(added?.look == look)
    }

    @Test func theNextTakeStartsWithTheLookThatCoversTheMostTime() {
        var edit = Edit(main: [clip(1, 0, 3), clip(2, 3, 10, side: .flipped), clip(3, 10, 12)])
        edit.look.inset = .large
        #expect(edit.prevailingLook?.cameraSide == .flipped)
        #expect(edit.prevailingLook?.inset == .large, "The inset is the edit's own.")
        #expect(Edit().prevailingLook == nil)
    }

    @Test func aTieGoesToTheEarliestClip() {
        let edit = Edit(main: [clip(1, 0, 3, side: .flipped), clip(2, 3, 6)])
        #expect(edit.prevailingLook?.cameraSide == .flipped)
    }

    @Test func clipLooksRoundTrip() throws {
        let original = clip(1, 0, 4, side: .flipped)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Clip.self, from: data) == original)
    }
}
