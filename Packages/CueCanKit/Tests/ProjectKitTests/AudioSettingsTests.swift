import Foundation
import Testing
@testable import ProjectKit

@Suite struct AudioSettingsTests {
    let studioMic = SourceID(number: 1)
    let cameraMic = SourceID(number: 2)

    @Test func defaultsMatchTheDecisions() {
        let settings = AudioSettings()
        #expect(settings.defaults.cleanup == CleanupSettings(mode: .natural, amount: 75))
        #expect(settings.defaults.voice.preset == .clear)
        #expect(settings.loudnessTarget == -14)
        #expect(settings.truePeakCeiling == -1)
        #expect(settings.sources.isEmpty)
    }

    @Test func everySourceStartsFromTheDefault() {
        var settings = AudioSettings()
        settings.defaults.cleanup.amount = 70
        #expect(settings.settings(for: studioMic).cleanup.amount == 70)
        #expect(settings.settings(for: cameraMic).cleanup.amount == 70)
    }

    @Test func aSourceCanHaveItsOwnSettings() {
        var settings = AudioSettings()
        let camera = SourceAudioSettings(
            cleanup: CleanupSettings(mode: .off, amount: 100),
            voice: VoiceSettings(preset: .broadcast, amount: 80)
        )
        settings.set(camera, for: cameraMic)
        #expect(settings.settings(for: cameraMic) == camera)
        #expect(settings.settings(for: studioMic) == settings.defaults)

        // A source with its own settings keeps them when the default changes.
        settings.defaults.voice.amount = 10
        #expect(settings.settings(for: cameraMic).voice.amount == 80)

        settings.useDefaults(for: cameraMic)
        #expect(settings.settings(for: cameraMic) == settings.defaults)
    }

    @Test func sourcesAreEncodedAsAnObjectKeyedByID() throws {
        var settings = AudioSettings()
        settings.set(SourceAudioSettings(cleanup: CleanupSettings(mode: .off, amount: 0)), for: cameraMic)
        let data = try ProjectJSON.encoder.encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sources = try #require(object["sources"] as? [String: Any])
        #expect(Array(sources.keys) == ["src_2"])
        #expect(try ProjectJSON.decoder.decode(AudioSettings.self, from: data) == settings)
    }

    @Test func modesAndPresetsReadAsWords() throws {
        let data = try ProjectJSON.encoder.encode(SourceAudioSettings(
            cleanup: CleanupSettings(mode: .off, amount: 25),
            voice: VoiceSettings(preset: .broadcast, amount: 40)
        ))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""mode" : "off""#))
        #expect(text.contains(#""preset" : "broadcast""#))
    }

    @Test(arguments: [-1.0, 100.5, 250])
    func amountsOutsideZeroToAHundredAreRefused(amount: Double) {
        let json = #"{"mode": "natural", "amount": \#(amount)}"#
        #expect(throws: DecodingError.self) {
            try ProjectJSON.decoder.decode(CleanupSettings.self, from: Data(json.utf8))
        }
        let voice = #"{"preset": "clear", "amount": \#(amount)}"#
        #expect(throws: DecodingError.self) {
            try ProjectJSON.decoder.decode(VoiceSettings.self, from: Data(voice.utf8))
        }
    }

    @Test func amountsSetInCodeAreKeptInRange() {
        #expect(CleanupSettings(amount: 140).amount == 100)
        #expect(VoiceSettings(amount: -5).amount == 0)
        #expect(CleanupSettings(amount: .nan).amount == 100)
    }

    @Test func aBadSourceKeyIsRefused() {
        let json = #"{"defaults": {"cleanup": {"mode": "natural", "amount": 50}, "voice": {"preset": "clear", "amount": 50}}, "sources": {"mic": {"cleanup": {"mode": "off", "amount": 0}, "voice": {"preset": "off", "amount": 0}}}, "loudnessTarget": -14, "truePeakCeiling": -1}"#
        #expect(throws: DecodingError.self) {
            try ProjectJSON.decoder.decode(AudioSettings.self, from: Data(json.utf8))
        }
    }

    @Test func audioChangesAreUndoable() throws {
        let url = try makeTemporaryFolder().appending(path: "Audio")
        let folder = try ProjectFolder.create(at: url, title: "Audio")
        try folder.updateEdit(author: .app, reason: "Camera mic: no cleanup") { edit in
            edit.audio.set(SourceAudioSettings(cleanup: CleanupSettings(mode: .off, amount: 60)), for: SourceID(number: 2))
        }
        #expect(try folder.loadEdit().audio.settings(for: SourceID(number: 2)).cleanup.mode == .off)
        try folder.undo()
        #expect(try folder.loadEdit().audio.settings(for: SourceID(number: 2)).cleanup.mode == .natural)
    }
}
