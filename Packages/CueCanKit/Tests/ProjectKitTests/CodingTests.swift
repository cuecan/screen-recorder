import Foundation
import Testing
@testable import ProjectKit

@Suite struct CodingTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try ProjectJSON.decoder.decode(T.self, from: ProjectJSON.encoder.encode(value))
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try ProjectJSON.encoder.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func transcriptRoundTrips() throws {
        #expect(try roundTrip(talkingHead) == talkingHead)
    }

    @Test func transcriptItemsAreFlatWithAType() throws {
        let word = try json(TranscriptItem.word(Word(id: WordID(number: 1), text: "Hi", start: 1, end: 2)))
        #expect(word["type"] as? String == "word")
        #expect(word["id"] as? String == "w_1")
        #expect(word["text"] as? String == "Hi")
        #expect(word["isFiller"] == nil, "Only fillers carry the flag.")

        let filler = try json(
            TranscriptItem.word(Word(id: WordID(number: 2), text: "um", start: 1, end: 2, isFiller: true))
        )
        #expect(filler["isFiller"] as? Bool == true)

        let silence = try json(TranscriptItem.silence(Silence(id: SilenceID(number: 3), start: 0, end: 1)))
        #expect(silence["type"] as? String == "silence")
        #expect(silence["id"] as? String == "s_3")
    }

    @Test func unknownItemTypeFailsToDecode() {
        let data = Data(#"{"type": "music", "id": "w_1", "start": 0, "end": 1}"#.utf8)
        #expect(throws: DecodingError.self) { try ProjectJSON.decoder.decode(TranscriptItem.self, from: data) }
    }

    @Test(arguments: [
        Layout.automatic,
        .sideBySide,
        .card(Card(position: .bottomRight, size: .small, shape: .square, screen: .full)),
        .card(.standard),
        .camera,
        .screen,
    ])
    func layoutsRoundTrip(layout: Layout) throws {
        #expect(try roundTrip(layout) == layout)
    }

    @Test func layoutIsFlatWithAKind() throws {
        let card = try json(Layout.card(Card(position: .top, size: .large, shape: .wide, screen: .full)))
        #expect(card["kind"] as? String == "card")
        #expect(card["size"] as? String == "large")
        #expect(card["position"] as? String == "top")
        #expect(card["screen"] as? String == "full")
        #expect(try json(Layout.sideBySide)["kind"] as? String == "sideBySide")
        #expect(try json(Layout.camera)["kind"] as? String == "camera")
    }

    @Test func aLayoutWithAnUnknownKindOrPositionIsRejected() {
        for text in [#"{"kind": "bubble", "size": "regular", "shape": "16:9"}"#,
                     #"{"kind": "card", "position": "middle", "size": "medium", "shape": "tall", "screen": "full", "roundness": 0.1}"#] {
            #expect(throws: DecodingError.self) { try ProjectJSON.decoder.decode(Layout.self, from: Data(text.utf8)) }
        }
    }

    @Test func aFormatOnlyHoldsALayoutItsDestinationOffers() throws {
        let both = VideoFormat(destination: .both, layout: .card(.standard))
        #expect(both.layout == .sideBySide(.nineByEight), "Both is Side by side only.")
        let card = VideoFormat(destination: .landscape, layout: .card(Card(position: .bottomRight, size: .small, shape: .square, screen: .full)))
        #expect(try roundTrip(card) == card)
        let data = Data(#"{"destination": "both", "layout": {"kind": "card", "position": "right", "size": "medium", "shape": "tall", "screen": "smaller", "roundness": 0.12}}"#.utf8)
        #expect(throws: DecodingError.self) { try ProjectJSON.decoder.decode(VideoFormat.self, from: data) }
    }

    @Test func projectWithAScreenRecordingAndImportedFootageRoundTrips() throws {
        var project = Project(title: "Editing with Claude", createdAt: Date(timeIntervalSince1970: 1_000))
        project.addSource(
            name: "Screen recording",
            origin: .recorded,
            tracks: [
                SourceTrack(
                    kind: .screen,
                    file: .inProject("recordings/screen.mov"),
                    media: MediaInfo(
                        duration: 60,
                        video: .init(width: 1944, height: 1620, frameRate: 60, captureRate: 60, codec: "hvc1")
                    )
                ),
                SourceTrack(
                    kind: .microphone,
                    file: .inProject("recordings/mic.wav"),
                    startOffset: 0.012,
                    media: MediaInfo(duration: 59.99, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))
                ),
            ],
            captureArea: CaptureArea(ratio: .nineByEight, heightPoints: 810)
        )
        project.addSource(
            name: "IMG_2231.MOV",
            origin: .imported,
            tracks: [
                SourceTrack(
                    kind: .video,
                    file: .external(URL(filePath: "/Volumes/Card/IMG_2231.MOV")),
                    media: MediaInfo(
                        duration: 120,
                        video: .init(
                            width: 3840, height: 2160, frameRate: 29.97, captureRate: 30, isVariableFrameRate: true,
                            codec: "hvc1", transferFunction: "ITU_R_2100_HLG", isHDR: true, bitDepth: 10
                        ),
                        audio: .init(sampleRate: 48_000, channels: 2, codec: "aac"),
                        timecode: "01:00:00:00"
                    )
                )
            ],
            sync: SourceSync(reference: SourceID(number: 1), offset: -3.25, method: .waveform)
        )
        #expect(try roundTrip(project) == project)
    }

    @Test func editRoundTrips() throws {
        var edit = Edit()
        edit.main = [
            Clip(
                id: edit.makeClipID(),
                source: SourceID(number: 1),
                sourceIn: 1.2,
                sourceOut: 4.5,
                layout: .sideBySide
            ),
            Clip(
                id: edit.makeClipID(),
                source: SourceID(number: 2),
                sourceIn: 10,
                sourceOut: 12,
                audio: ClipAudio(source: SourceID(number: 3), track: .audio),
                layout: .camera
            ),
        ]
        edit.overlays = [
            Overlay(id: edit.makeClipID(), media: .source(SourceID(number: 4)), over: .words(range(w(3), w(9)))),
            Overlay(id: edit.makeClipID(), media: .file(FileReference(path: "/tmp/shot.png"), isStill: true), over: .time(source: SourceID(number: 1), range: TimeRange(start: 2, end: 5)), placement: .inScreensPlace),
        ]
        edit.freezes = [Freeze(id: edit.makeFreezeID(), source: SourceID(number: 1), range: TimeRange(start: 3, end: 4))]
        edit.fixes = [
            WordFix(replaces: range(w(3), w(4)), words: [Word(id: WordID(number: 90), text: "CueCan", start: 1, end: 1.5)], isTimed: false),
            WordFix(replaces: range(w(90), w(90)), words: [Word(id: WordID(number: 91), text: "Cue", start: 1, end: 1.2),
                                                          Word(id: WordID(number: 92), text: "Can", start: 1.2, end: 1.5)], isTimed: true),
        ]
        edit.look = EditLook(inset: .none, rounded: false, background: "#d9d9d9", mirror: true)
        edit.main[1].look = ClipLook(cameraSide: .flipped)
        edit.main[0].speed = ClipSpeed(rate: 4)!
        edit.main[0].isMuted = true
        edit.main[0].startPlacedByHand = true
        edit.audio = AudioSettings(
            defaults: SourceAudioSettings(cleanup: CleanupSettings(mode: .natural, amount: 50)),
            sources: [SourceID(number: 3): SourceAudioSettings(
                cleanup: CleanupSettings(mode: .off, amount: 0),
                voice: VoiceSettings(preset: .broadcast, amount: 75)
            )],
            loudnessTarget: -16
        )
        #expect(try roundTrip(edit) == edit)
    }
}
