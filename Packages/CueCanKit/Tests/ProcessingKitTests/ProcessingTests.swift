import AVFoundation
import Foundation
import Testing
import ProjectKit
import TranscribeKit
@testable import ProcessingKit

private func draft(_ words: [(String, Double, Double)]) -> TranscriptDraft {
    TranscriptDraft(
        engine: "test", silenceDetector: "test", language: "en", audioDuration: 10,
        items: words.map { .word(.init(text: $0.0, start: $0.1, end: $0.2)) }
    )
}

@Suite struct AlternativeReadingTests {
    @Test func aDifferentReadingBecomesAnAlternativeOnTheWordsItCovers() {
        let parakeet = draft([("I", 0, 0.2), ("use", 0.2, 0.4), ("Q", 0.4, 0.6), ("can", 0.6, 0.8), ("daily.", 0.8, 1)])
        let apple = ["I", "use", "CueCan", "daily"].map { TimedWord(text: $0, start: 0, end: 0) }
        let alternatives = AlternativeReadings.alternatives(for: parakeet, secondReading: apple)
        #expect(alternatives == [TranscriptDraft.DraftAlternative(words: 2..<4, text: "CueCan")])
    }

    @Test func caseAndPunctuationAloneAreNotAnotherReading() {
        let parakeet = draft([("hello", 0, 0.2), ("there.", 0.2, 0.4)])
        let apple = ["Hello", "there"].map { TimedWord(text: $0, start: 0, end: 0) }
        #expect(AlternativeReadings.alternatives(for: parakeet, secondReading: apple).isEmpty)
    }

    @Test func alternativesGetTheWordsIDsWhenSaved() {
        var parakeet = draft([("I", 0, 0.2), ("use", 0.2, 0.4), ("Q", 0.4, 0.6), ("can", 0.6, 0.8)])
        parakeet.alternatives = [.init(words: 2..<4, text: "CueCan")]
        let transcript = parakeet.assigningIDs(source: SourceID(number: 1), firstWordNumber: 10, firstSilenceNumber: 1).transcript
        #expect(transcript.alternatives == [WordAlternative(words: ItemRange(first: .word(WordID(number: 12)), last: .word(WordID(number: 13))), text: "CueCan")])
    }

    @Test func aTrackThatStartsLateMovesItsTranscriptLater() {
        let shifted = draft([("Hi", 1, 1.5)]).shifted(by: 0.25)
        #expect(shifted.items == [.word(.init(text: "Hi", start: 1.25, end: 1.75))])
    }
}

@Suite struct SpellingMatcherTests {
    @Test func swapsLandOnTheWordsTheyReplace() {
        let transcript = draft([("my", 0, 0.2), ("pass", 0.2, 0.4), ("key", 0.4, 0.6), ("works", 0.6, 0.8)])
            .assigningIDs(source: SourceID(number: 2), firstWordNumber: 5, firstSilenceNumber: 1).transcript
        let boosted = ["my", "passkey", "works"].map { TimedWord(text: $0, start: 0, end: 0) }
        let spellings = SpellingMatcher.spellings(for: transcript, boosted: boosted, terms: ["passkey"])
        #expect(spellings.terms == ["passkey"])
        #expect(spellings.spellings == [.init(words: ItemRange(first: .word(WordID(number: 6)), last: .word(WordID(number: 7))), text: "passkey")])
    }
}

/// Cleaning on a synthetic tone, for the plumbing only: files in `audio/`, the record, and its matching.
@Suite struct CleaningTests {
    @Test func cleaningWritesAFileTheRenderCanFind() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-processing-\(UUID().uuidString)")
        let folder = try ProjectFolder.create(at: url, title: "Clean")
        let mic = folder.url(for: .recordings).appending(path: "mic.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for index in 0..<48_000 { buffer.floatChannelData![0][index] = 0.1 * Float(sin(2 * .pi * 200 * Double(index) / 48_000)) }
        try AVAudioFile(forWriting: mic, settings: format.settings).write(from: buffer)
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        try folder.updateProject { $0.addSource(name: "Mic", origin: .recorded, tracks: [track]) }
        let source = SourceID(number: 1)
        try folder.updateEdit(author: .system("Test"), reason: "Voice only") { edit in
            edit.audio.defaults = SourceAudioSettings(cleanup: CleanupSettings(mode: .off), voice: VoiceSettings(preset: .clear, amount: 50))
        }

        let record = try #require(try await SourceProcessor().clean(source, in: folder))
        #expect(record.file.hasPrefix("src_1-off-clear50-"))
        let again = try #require(try await SourceProcessor().clean(source, in: folder))
        #expect(again.file != record.file)
        #expect(FileManager.default.fileExists(atPath: folder.url(for: .audio).appending(path: record.file).path))
        let settings = try folder.loadEdit().audio.settings(for: source)
        #expect(folder.cleanedAudioURL(for: source, settings: settings, original: track.file) != nil)

        try folder.updateEdit(author: .system("Test"), reason: "Louder voice") { $0.audio.defaults.voice.amount = 80 }
        let changed = try folder.loadEdit().audio.settings(for: source)
        #expect(folder.cleanedAudioURL(for: source, settings: changed, original: track.file) == nil, "New settings need a new file.")
    }
}

/// Measuring a source's levels for checking cut edges, on a synthetic tone burst (docs/decisions.md, 75).
@Suite struct LevelsMeasureTests {
    @Test func levelsAreMeasuredOnceSavedAndFollowTheTrack() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-levels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Levels")
        let mic = folder.url(for: .recordings).appending(path: "mic.wav")
        // Two seconds: quiet, a tone from 0.5 to 1.5 s, quiet.
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        buffer.frameLength = 96_000
        for index in 0..<96_000 {
            let loud = index >= 24_000 && index < 72_000
            buffer.floatChannelData![0][index] = Float(loud ? 0.1 : 0.0003) * Float(sin(2 * .pi * 200 * Double(index) / 48_000))
        }
        try AVAudioFile(forWriting: mic, settings: format.settings).write(from: buffer)
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), media: MediaInfo(duration: 2, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        try folder.updateProject { $0.addSource(name: "Mic", origin: .recorded, tracks: [track]) }
        let source = SourceID(number: 1)

        let levels = try #require(try await SourceLevelsMeasure.levels(for: source, in: folder))
        #expect(levels.detector == "energy" && levels.minimumSound == EnergySilenceDetector.Settings().minimumSound)
        let envelope = levels.envelope
        #expect(envelope.levels.count == 200)
        // The threshold sits between the quiet and the tone, as the detector sets it.
        #expect(envelope.levels[10] < levels.threshold && envelope.levels[100] > levels.threshold)
        #expect(folder.loadLevels(for: source, original: track.file) == levels, "Saved in audio/.")

        // An edge in the middle of the tone runs across sound; one in the quiet doesn't.
        let edit = Edit(main: [Clip(id: ClipID(number: 1), source: source, sourceIn: 0.2, sourceOut: 1.0)])
        let edges = EdgeSound.edges(in: edit, levels: [source: levels])
        #expect(edges.map(\.edge) == [.end])
        #expect(abs(edges[0].soundBefore - 0.5) < 0.011 && abs(edges[0].soundAfter - 0.5) < 0.011)
    }
}
