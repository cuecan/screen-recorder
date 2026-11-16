import Testing
@testable import ProjectKit

/// The tool strip's Noise reduction and Equalizer switches (docs/ui.md, E6).
struct AudioSwitchTests {
    let first = SourceID(number: 1), second = SourceID(number: 2)

    @Test func aNewTakeHasBothOn() {
        let audio = AudioSettings()
        for audioSwitch in AudioSwitch.allCases { #expect(audioSwitch.isOn(for: [first], in: audio)) }
        #expect(!AudioSwitch.equalizer.isOn(for: [], in: audio), "With no mic there's nothing to be on.")
    }

    @Test func noiseReductionSwitchesCleanupAndKeepsItsAmount() {
        var settings = SourceAudioSettings(cleanup: CleanupSettings(mode: .natural, amount: 50))
        AudioSwitch.noiseReduction.set(false, in: &settings)
        #expect(settings.cleanup == CleanupSettings(mode: .off, amount: 50) && settings.voice == VoiceSettings())
        AudioSwitch.noiseReduction.set(true, in: &settings)
        #expect(settings.cleanup == CleanupSettings(mode: .natural, amount: 50))
    }

    @Test func theEqualizerComesBackWithThePresetItHad() {
        var settings = SourceAudioSettings(voice: VoiceSettings(preset: .broadcast, amount: 75))
        AudioSwitch.equalizer.set(false, in: &settings)
        #expect(settings.voice == VoiceSettings(preset: .off, amount: 75))
        AudioSwitch.equalizer.set(true, in: &settings, restoring: .broadcast)
        #expect(settings.voice == VoiceSettings(preset: .broadcast, amount: 75))
        // With nothing remembered it's Clear, and switching on what's already on leaves its preset.
        var unknown = SourceAudioSettings(voice: VoiceSettings(preset: .off))
        AudioSwitch.equalizer.set(true, in: &unknown)
        #expect(unknown.voice.preset == .clear)
        AudioSwitch.equalizer.set(true, in: &settings, restoring: .clear)
        #expect(settings.voice.preset == .broadcast)
    }

    @Test func oneClickSwitchesEveryMicAndMixedCountsAsOff() {
        var audio = AudioSettings()
        var quiet = SourceAudioSettings()
        quiet.cleanup.mode = .off
        audio.set(quiet, for: second)
        #expect(!AudioSwitch.noiseReduction.isOn(for: [first, second], in: audio), "One mic off: a click turns it on for both.")
        let turnedOn = audio.set(.noiseReduction, on: true, for: [first, second])
        #expect(turnedOn)
        #expect(AudioSwitch.noiseReduction.isOn(for: [first, second], in: audio))
        let again = audio.set(.noiseReduction, on: true, for: [first, second])
        #expect(!again, "Nothing to change the second time.")
        let turnedOff = audio.set(.equalizer, on: false, for: [first, second])
        #expect(turnedOff)
        #expect(!AudioSwitch.equalizer.isOn(for: [first], in: audio) && AudioSwitch.noiseReduction.isOn(for: [first], in: audio))
        audio.set(.equalizer, on: true, for: [first, second], restoring: [second: .broadcast])
        #expect(audio.settings(for: first).voice.preset == .clear && audio.settings(for: second).voice.preset == .broadcast)
    }
}
