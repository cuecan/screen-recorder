import AudioKit
internal import FluidAudio
import Foundation

/// NVIDIA's Parakeet TDT through FluidAudio, on Core ML: one model writes the words and times them, from the
/// encoder frames that emitted each word's tokens. It writes the primary transcript, because it keeps the
/// repeats and fillers an editor needs (docs/bakeoff-findings.md).
///
/// - **v3** is multilingual (25 European languages), and it's the one that ships (docs/decisions.md, 39).
///   **v2** is English only, kept for the bake-off: it dropped fillers v3 kept in real recordings.
/// - The model's license is CC-BY-4.0, which needs an attribution line when it ships (VERIFY the wording).
/// - **Vocabulary boosting:** given terms to listen for, such as names and jargon from a script, it checks the
///   words that sound like them against a second, small model's reading of the audio (FluidAudio's Parakeet
///   CTC 110M, 97.5 MB), and swaps in a term where the audio supports it better. Swapped words keep the
///   time of the words they replace (``VocabularyCorrection``). See docs/decisions.md, 42.
public final class ParakeetEngine: TranscriptionEngine {
    /// Which Parakeet model.
    public enum Version: String, Sendable, CaseIterable {
        case v2
        case v3

        var fluidAudio: AsrModelVersion {
            switch self {
            case .v2: .v2
            case .v3: .v3
            }
        }
    }

    public let version: Version
    public var id: String { "parakeet-tdt-\(version.rawValue)" + (terms.isEmpty ? "" : "-boosted") }
    public var displayName: String { "Parakeet TDT \(version.rawValue)" + (terms.isEmpty ? "" : ", boosted") }
    public var weightsDescription: String {
        let model = "Parakeet TDT \(version.rawValue) for Core ML, through FluidAudio"
        return terms.isEmpty ? model : model + ", and Parakeet CTC 110M for vocabulary boosting"
    }
    /// Terms to listen for, such as names and jargon from the script. Empty turns boosting off. Blank terms
    /// are ignored.
    public var vocabulary: [String] {
        didSet {
            if vocabulary != oldValue { boosting = nil }
        }
    }
    /// How readily a heard word is swapped for a term.
    public var boostingThresholds: VocabularyBoostingThresholds {
        didSet {
            if boostingThresholds != oldValue { boosting = nil }
        }
    }
    /// FluidAudio splits long audio itself, into 15-second windows with overlapping, silence-aligned seams,
    /// and merges them, so it gets the whole recording.
    public let maximumChunkDuration: TimeInterval? = nil

    /// Models are usable only once the complete load (including optional boosting) succeeds.
    private enum State {
        case unloaded
        case loading
        case ready(AsrManager)
    }
    private var state: State = .unloaded

    private var terms: [String] {
        vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var ctcModels: CtcModels?
    private var boosting: VocabularyBoostingSession?

    public init(
        version: Version = .v3,
        vocabulary: [String] = [],
        boostingThresholds: VocabularyBoostingThresholds = VocabularyBoostingThresholds()
    ) {
        self.version = version
        self.vocabulary = vocabulary
        self.boostingThresholds = boostingThresholds
    }

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        switch state {
        case .ready: return
        case .loading: throw AudioKitError.modelFailed(displayName, "It is already loading.")
        case .unloaded: break
        }
        state = .loading
        do {
            let models = try await AsrModels.downloadAndLoad(version: version.fluidAudio) { update in
                progress("\(Int(update.fractionCompleted * 100))%")
            }
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            if !terms.isEmpty {
                progress("Vocabulary model")
                _ = try await boostingSession()
            }
            try Task.checkCancellation()
            state = .ready(manager)
        } catch {
            unload()
            throw error
        }
    }

    public func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        guard case .ready(let manager) = state else { throw AudioKitError.modelFailed(displayName, "It isn't loaded.") }
        let input = try audio.resampled(to: 16_000)
        // FluidAudio needs at least 300 ms of audio.
        guard input.samples.count >= 4_800 else { return [] }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await manager.transcribe(input.samples, decoderState: &state)
        } catch {
            throw AudioKitError.modelFailed(displayName, error.localizedDescription)
        }
        let tokens = result.tokenTimings ?? []
        let words = Self.words(from: tokens)
        guard let session = try await boostingSession(),
            let output = await session.rescore(text: result.text, tokenTimings: tokens, audioSamples: input.samples),
            output.wasModified
        else { return words }
        return VocabularyCorrection.apply(output.text, to: words)
    }

    public func unload() {
        state = .unloaded
        ctcModels = nil
        boosting = nil
    }

    /// The boosting session for the current vocabulary, made on first use. Nil when there's no vocabulary.
    private func boostingSession() async throws -> VocabularyBoostingSession? {
        guard !terms.isEmpty else { return nil }
        if let boosting { return boosting }
        do {
            let models: CtcModels
            if let ctcModels {
                models = ctcModels
            } else {
                models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
                ctcModels = models
            }
            let terms = terms.map { CustomVocabularyTerm(text: $0) }
            let thresholds = VocabularyBoostingSession.Thresholds(
                cbw: Float(boostingThresholds.termBonus),
                minSimilarity: Float(boostingThresholds.minimumSimilarity)
            )
            let session = try await VocabularyBoostingSession(
                vocabulary: CustomVocabularyContext(terms: terms), ctcModels: models, thresholds: thresholds
            )
            boosting = session
            return session
        } catch {
            throw AudioKitError.modelFailed(displayName, "Vocabulary boosting couldn't start: \(error.localizedDescription)")
        }
    }

    /// Groups sub-word tokens into words, as FluidAudio's `buildWordTimings` does, keeping each word's
    /// average token confidence too.
    static func words(from tokens: [TokenTiming]) -> [TimedWord] {
        var words: [TimedWord] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var confidences: [Float] = []

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let confidence = confidences.isEmpty ? nil : Double(confidences.reduce(0, +) / Float(confidences.count))
            words.append(TimedWord(text: trimmed, start: start, end: end, confidence: confidence))
        }

        for token in tokens {
            let piece = token.token
            guard !piece.isEmpty, piece != "<blank>", piece != "<pad>" else { continue }
            // SentencePiece marks the first token of a word with "▁"; some exports use a plain space.
            let startsWord = piece.hasPrefix("▁") || piece.hasPrefix(" ") || text.isEmpty
            if startsWord {
                flush()
                text = String(piece.drop { $0 == "▁" || $0 == " " })
                start = token.startTime
                confidences = []
            } else {
                text += piece
            }
            end = token.endTime
            confidences.append(token.confidence)
        }
        flush()
        return words
    }
}
