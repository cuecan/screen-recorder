import AudioKit
import Foundation
import ProjectKit
import TranscribeKit

/// What runs on its own after a recording or an import (docs/design.md, "How it works for the creator"):
/// transcribing each source, attaching SpeechAnalyzer's second reading, applying the vocabulary, and
/// cleaning each mic source into `audio/`.
///
/// It keeps Parakeet loaded between sources. Use one processor from one task at a time.
public final class SourceProcessor {
    /// What a processing pass did, for the app's status chips and the CLI's report.
    public typealias Report = ProcessingReport

    public let language: String?
    /// Whether to read the text on screen at each still moment ("Save screen text", docs/decisions.md, 58).
    public let readsScreenText: Bool
    private let parakeet = ParakeetEngine()
    private var parakeetLoaded = false
    /// The timing model, loaded on first use. Nil until then, and when it can't be had.
    private var wordTimer: WordTimer?
    private var wordTimerFailed = false

    public init(language: String? = "en", readsScreenText: Bool = true) {
        self.language = language
        self.readsScreenText = readsScreenText
    }

    /// Everything still to do in a project: transcripts for untranscribed sources, spellings for the
    /// current vocabulary, cleaned voices for the current settings, and the screen read for recordings with
    /// one. A source that fails is reported and the rest carry on.
    public func process(_ folder: ProjectFolder, progress: @escaping @Sendable (ProcessingProgress) -> Void = { _ in }) async throws -> Report {
        var report = Report()
        let project = try folder.loadProject()
        for source in project.sources where source.primaryAudioTrack != nil || source.track(.screen) != nil {
            do {
                guard source.primaryAudioTrack != nil else {
                    try await readScreen(source, in: folder, report: &report, progress: progress)
                    continue
                }
                if source.transcriptFile == nil {
                    progress(.init(stage: .transcribing, source: source.id, message: "Transcribing \(source.name)"))
                    _ = try await transcribe(source.id, in: folder) { message in
                        progress(.init(stage: .transcribing, source: source.id, message: message))
                    }
                    report.transcribed.append(source.id)
                }
                if let track = source.primaryAudioTrack, folder.loadLevels(for: source.id, original: track.file) == nil {
                    _ = try await SourceLevelsMeasure.levels(for: source.id, in: folder)
                }
                let terms = try folder.loadProject().vocabulary
                if !terms.isEmpty, try folder.loadSpellings(for: source.id)?.terms != terms {
                    progress(.init(stage: .applyingVocabulary, source: source.id, message: "Applying the vocabulary to \(source.name)"))
                    if try await applyVocabulary(to: source.id, in: folder) != nil { report.spelled.append(source.id) }
                }
                let edit = try folder.loadEdit()
                if let track = source.primaryAudioTrack,
                    folder.cleanedAudioURL(for: source.id, settings: edit.audio.settings(for: source.id), original: track.file) == nil
                {
                    progress(.init(stage: .cleaning, source: source.id, message: "Cleaning the voice in \(source.name)"))
                    if try await clean(source.id, in: folder) != nil { report.cleaned.append(source.id) }
                }
                try await readScreen(source, in: folder, report: &report, progress: progress)
            } catch {
                try Task.checkCancellation()
                report.failures[source.id] = error.localizedDescription
            }
        }
        return report
    }

    // MARK: - Transcribing

    /// Transcribes a source's main audio with Parakeet, fits its word times to the audio, places real
    /// silences, attaches SpeechAnalyzer's reading where it differs, and saves the transcript.
    public func transcribe(_ id: SourceID, in folder: ProjectFolder, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Transcript {
        let (track, audio) = try await primaryAudio(of: id, in: folder)
        let detector = EnergySilenceDetector()
        let measured = detector.analyze(audio)
        let silences = measured.silences
        // Kept for checking cut edges by their sound (docs/decisions.md, 75).
        try folder.saveLevels(SourceLevelsMeasure.record(measured, by: detector, for: id, track: track))
        try await loadParakeet(progress: progress)
        let heard = try await Transcriber.transcribe(audio, with: parakeet, silences: silences, language: language, progress: progress)
        // The timing model says when each word starts (docs/decisions.md, 95); then the words are fitted to
        // the audio before anything reads them (74). Without the model, Parakeet's own times are fitted, as
        // they were before it.
        let words: [TimedWord]
        if let placed = await placed(heard, in: audio, progress: progress) {
            words = WordFitter.fit(placed, to: measured, settings: .afterTiming)
        } else {
            words = WordFitter.fit(heard, to: measured)
        }

        var draft = TranscriptAssembler.draft(
            words: words,
            silences: silences,
            duration: audio.duration,
            engine: parakeet.id,
            silenceDetector: "energy",
            language: language
        )
        // The second reading is a help, not a requirement: a transcript is still written without it.
        let apple = SpeechAnalyzerEngine()
        if let reading = try? await Transcriber.transcribe(audio, with: apple, silences: silences, language: language) {
            draft.alternatives = AlternativeReadings.alternatives(for: draft, secondReading: reading)
        }
        return try folder.addTranscript(draft.shifted(by: track.startOffset), for: id)
    }

    /// The words with the timing model's starts, or nil when the model can't be downloaded, loaded or run:
    /// a transcript is still written then, with Parakeet's times.
    private func placed(_ words: [TimedWord], in audio: AudioSamples, progress: @escaping @Sendable (String) -> Void) async -> [TimedWord]? {
        guard !words.isEmpty, !wordTimerFailed else { return nil }
        do {
            if wordTimer == nil {
                if !WordTimer.isInstalled {
                    progress("Downloading the timing model")
                    try await TimingModelDownload.install()
                }
                wordTimer = try WordTimer()
            }
            guard let wordTimer else { return nil }
            progress("Timing the words")
            return WordRetimer.retime(words, starts: try wordTimer.starts(of: words, in: audio))
        } catch {
            // Once is enough to try in a pass: every later source would fail the same way.
            wordTimerFailed = true
            FileHandle.standardError.write(Data("cuecan: words keep Parakeet's times: \(error.localizedDescription)\n".utf8))
            return nil
        }
    }

    // MARK: - Vocabulary

    /// Runs vocabulary boosting with the project's terms on a transcribed source and saves its spellings.
    /// Nil if the source isn't transcribed or the project has no terms.
    @discardableResult
    public func applyVocabulary(to id: SourceID, in folder: ProjectFolder) async throws -> VocabularySpellings? {
        let terms = try folder.loadProject().vocabulary
        guard !terms.isEmpty, let transcript = try folder.loadTranscript(for: id) else { return nil }
        let (track, audio) = try await primaryAudio(of: id, in: folder)
        let boosted = ParakeetEngine(vocabulary: terms)
        try await boosted.load(progress: { _ in })
        defer { boosted.unload() }
        let silences = EnergySilenceDetector().detect(in: audio)
        let words = try await Transcriber.transcribe(audio, with: boosted, silences: silences, language: language)
            .map { $0.offset(by: track.startOffset) }
        let spellings = SpellingMatcher.spellings(for: transcript, boosted: words, terms: terms)
        try folder.saveSpellings(spellings)
        return spellings
    }

    // MARK: - Cleaning

    /// Runs Cleanup and Voice on a mic source with its current settings and writes the result to `audio/`.
    /// Nil when both stages are off, since the raw mic is what plays then.
    @discardableResult
    public func clean(_ id: SourceID, in folder: ProjectFolder) async throws -> CleanedAudio? {
        let settings = try folder.loadEdit().audio.settings(for: id)
        guard settings.cleanup.mode != .off || settings.voice.preset != .off else { return nil }
        let (track, original) = try await primaryAudio(of: id, in: folder)

        var audio = try await AlignedCleanup.apply(settings.cleanup, to: original)
        if let preset = VoicePreset.preset(settings.voice.preset) {
            audio = VoiceProcessor.process(audio, preset: preset, amount: settings.voice.amount)
        }

        let name = CleanedAudio.newFileName(for: id, settings: settings)
        try AudioFileWriter.writeWAV(audio, to: folder.url(for: .audio).appending(path: name), encoding: .float32)
        let record = CleanedAudio(source: id, settings: settings, file: name, original: track.file)
        try folder.saveCleanedAudio(record)
        return record
    }

    // MARK: - The screen

    /// Reads a source's screen if it hasn't been read, or was read without its text and the text is now
    /// wanted.
    private func readScreen(_ source: Source, in folder: ProjectFolder, report: inout Report, progress: @escaping @Sendable (ProcessingProgress) -> Void) async throws {
        guard source.track(.screen) != nil else { return }
        if let existing = try folder.loadScreenAnalysis(for: source.id), existing.readText || !readsScreenText { return }
        progress(.init(stage: .readingScreen, source: source.id, message: "Reading the screen in \(source.name)"))
        guard let analysis = try await ScreenReader().analyze(source, in: folder, readText: readsScreenText, progress: { message in
            progress(.init(stage: .readingScreen, source: source.id, message: message))
        }) else { return }
        try folder.saveScreenAnalysis(analysis)
        report.screensRead.append(source.id)
    }

    // MARK: - For another editor

    /// The mic cleaned with Cleanup only, no Voice or loudness, for the export to another editor
    /// (docs/decisions.md, 60): those belong to that editor's mix. It's written to `audio/` beside the
    /// preview's file, which it never replaces. Nil when Cleanup is off.
    public func cleanupOnly(_ source: Source, settings requested: SourceAudioSettings, in folder: ProjectFolder) async throws -> URL? {
        var settings = requested
        guard settings.cleanup.mode != .off else { return nil }
        settings.voice = VoiceSettings(preset: .off, amount: 0)
        guard let track = source.primaryAudioTrack else { throw ProcessingError.noAudio(source.id) }
        if let cached = folder.cleanedAudioURL(for: source.id, settings: settings, original: track.file, purpose: .handoff) { return cached }
        let original = try await readAudio(track, source: source.id, in: folder)
        let aligned = try await AlignedCleanup.apply(settings.cleanup, to: original)
        let name = CleanedAudio.newFileName(for: source.id, settings: settings)
        let url = folder.url(for: .audio).appending(path: name)
        try AudioFileWriter.writeWAV(aligned, to: url, encoding: .float32)
        try folder.saveCleanedAudio(CleanedAudio(source: source.id, settings: settings, file: name, original: track.file), purpose: .handoff)
        return url
    }

    // MARK: - Reading

    private func primaryAudio(of id: SourceID, in folder: ProjectFolder) async throws -> (SourceTrack, AudioSamples) {
        guard let source = try folder.loadProject().source(id) else { throw EditError.unknownSource(id) }
        guard let track = source.primaryAudioTrack else { throw ProcessingError.noAudio(id) }
        return (track, try await readAudio(track, source: id, in: folder))
    }

    private func readAudio(_ track: SourceTrack, source id: SourceID, in folder: ProjectFolder) async throws -> AudioSamples {
        let url = track.file.url(relativeTo: folder.url)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ProcessingError.missingFile(url) }
        let tracks = try await AudioFileReader.audioTracks(in: url)
        guard !tracks.isEmpty else { throw ProcessingError.noAudio(id) }
        return try await AudioFileReader.readMono(url, track: 0, sampleRate: 48_000)
    }

    private func loadParakeet(progress: @escaping @Sendable (String) -> Void) async throws {
        guard !parakeetLoaded else { return }
        try await parakeet.load(progress: progress)
        parakeetLoaded = true
    }
}
