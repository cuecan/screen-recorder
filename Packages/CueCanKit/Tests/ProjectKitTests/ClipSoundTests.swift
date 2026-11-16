import Foundation
import Testing
@testable import ProjectKit

/// Sound per clip (docs/decisions.md, 71): each clip's voice and system audio levels and Mute, and each
/// overlay's level. Cleanup and Voice stay per mic source.
@Suite struct ClipSoundTests {
    let transcripts = TranscriptIndex([talkingHead, secondAngle])

    /// All of `talkingHead` as one clip, then split at 3 s into c_1 and c_2.
    func twoClips() throws -> Edit {
        var edit = Edit()
        try edit.addClip(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        try edit.split(at: 3)
        return edit
    }

    @Test func settingSoundChangesOnlyWhatsGiven() throws {
        var edit = try twoClips()
        let ids = edit.main.map(\.id)
        try edit.setSound(ClipSoundChange(voiceLevel: -6), for: [ids[0]])
        #expect(edit.main[0].voiceLevel == -6 && edit.main[1].voiceLevel == 0)
        try edit.setSound(ClipSoundChange(systemAudioLevel: -12, isMuted: true), for: ids)
        #expect(edit.main.map(\.systemAudioLevel) == [-12, -12])
        #expect(edit.main.allSatisfy { $0.isMuted })
        #expect(edit.main[0].voiceLevel == -6, "A change without a voice level leaves it alone.")
    }

    @Test func levelsStayInRange() throws {
        var edit = try twoClips()
        try edit.setSound(ClipSoundChange(voiceLevel: 40, systemAudioLevel: -200), for: [edit.main[0].id])
        #expect(edit.main[0].voiceLevel == SoundLevel.range.upperBound)
        #expect(edit.main[0].systemAudioLevel == SoundLevel.range.lowerBound)
        try edit.setSound(ClipSoundChange(voiceLevel: .nan), for: [edit.main[0].id])
        #expect(edit.main[0].voiceLevel == 0, "A level that isn't a number is 0 dB.")
        #expect(SoundLevel.label(-60) == "Off" && SoundLevel.label(-5.6) == "−6 dB" && SoundLevel.label(0.2) == "0 dB" && SoundLevel.label(3) == "+3 dB")
    }

    @Test func anUnknownClipChangesNothing() throws {
        var edit = try twoClips()
        let before = edit
        #expect(throws: EditError.self) {
            try edit.setSound(ClipSoundChange(voiceLevel: -6), for: [edit.main[0].id, ClipID(number: 99)])
        }
        #expect(edit == before)
    }

    @Test func aSplitKeepsTheLevelsOnBothHalves() throws {
        var edit = Edit()
        try edit.addClip(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        try edit.setSound(ClipSoundChange(voiceLevel: -3, systemAudioLevel: -9), for: [edit.main[0].id])
        try edit.split(at: 3)
        #expect(edit.main.map(\.voiceLevel) == [-3, -3])
        #expect(edit.main.map(\.systemAudioLevel) == [-9, -9])
    }

    @Test func clipsAtDifferentLevelsArentTheSame() throws {
        var edit = try twoClips()
        #expect(edit.main[0].hasSamePresentation(as: edit.main[1]))
        try edit.setSound(ClipSoundChange(voiceLevel: -6), for: [edit.main[1].id])
        #expect(!edit.main[0].hasSamePresentation(as: edit.main[1]))
    }

    @Test func levelsRoundTripAndAreOnlyWrittenWhenSet() throws {
        var edit = try twoClips()
        try edit.setSound(ClipSoundChange(voiceLevel: -4.5, systemAudioLevel: -10), for: [edit.main[1].id])
        edit.overlays.append(Overlay(id: ClipID(number: 9), media: .file(FileReference(path: "/tmp/a.mov"), isStill: false),
                                     over: .words(range(w(1), w(2))), isMuted: false, level: -8))
        let data = try JSONEncoder().encode(edit)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"levels\""), "The edit-wide levels are gone.")
        let clips = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["main"] as? [[String: Any]])
        #expect(clips[0]["voiceLevel"] == nil && clips[0]["systemAudioLevel"] == nil, "A clip at 0 dB writes no levels.")
        #expect(clips[1]["voiceLevel"] as? Double == -4.5 && clips[1]["systemAudioLevel"] as? Double == -10)
        let read = try JSONDecoder().decode(Edit.self, from: data)
        #expect(read == edit)
        #expect(read.overlays[0].level == -8)
        #expect(read.formatVersion == Edit.currentFormatVersion)
    }
}
