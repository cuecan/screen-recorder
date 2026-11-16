import AudioKit
import CoreML
internal import FluidAudio
import Foundation
import ProjectKit

/// Places words that are already known in the audio: Parakeet writes the transcript, and this says when
/// each word starts (docs/decisions.md, 95).
///
/// It runs the timing head of NVIDIA's Nemotron 3.5 Transcribe, which NVIDIA trained to place another
/// model's words, in its 4-bit Core ML form: FluidInference's port, downloaded from Hugging Face and patched
/// on this Mac so the head gives every piece's probability on every 40 ms frame, not only its best guess
/// (``TimingModelDownload``). The words are cut into the model's pieces (``PieceTokenizer``) and the
/// best path through them is found (``ForcedAligner``), a stretch at a time (``AlignmentPlan``).
///
/// On a real 93-second take, the words after a pause started a median of 35 ms from the audible onset this
/// way, against 205 ms for Parakeet's own times (docs/bakeoff-findings.md).
public final class WordTimer {
    /// The model's folder name, with the version of the export in it.
    public static let folderName = "nemotron-timing-p4-1"

    /// Where the model lives once it's downloaded: Application Support/CueCan/Models.
    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "CueCan/Models/\(folderName)", directoryHint: .isDirectory)
    }

    /// Whether every file the model needs is at ``directory``.
    public static var isInstalled: Bool { isInstalled(at: directory) }

    public static func isInstalled(at directory: URL) -> Bool {
        requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path(percentEncoded: false)) }
    }

    static let requiredFiles = ["model.mlmodelc/coremldata.bin", "model.mlmodelc/model.mil", "vocab.json", "mel_window.bin", "mel_filterbank.bin"]

    // The model's layout: 16 kHz audio, 10 ms mel frames, eight of them to an encoder frame, two 40 ms output
    // frames to an encoder frame, and 30 s (3,000 mel frames) to a window.
    static let sampleRate = 16_000
    static let hop = 160
    static let melBins = 128
    static let stack = 8
    static let windowMelFrames = 3_000
    static let frameDuration: TimeInterval = 0.04
    public static let windowDuration: TimeInterval = 30

    private let model: MLModel
    private let mel: AudioMelSpectrogram
    let tokenizer: PieceTokenizer

    /// Loads the model from its folder.
    public init(directory: URL = WordTimer.directory) throws {
        guard Self.isInstalled(at: directory) else {
            throw AudioKitError.modelFailed("Word timing", "The timing model isn't downloaded.")
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            model = try MLModel(contentsOf: directory.appending(path: "model.mlmodelc"), configuration: configuration)
            tokenizer = try PieceTokenizer(contentsOf: directory.appending(path: "vocab.json"))
            let window = try Self.floats(directory.appending(path: "mel_window.bin"))
            let filterbank = try Self.floats(directory.appending(path: "mel_filterbank.bin"))
            guard window.count == 400, filterbank.count == Self.melBins * 257 else { throw CocoaError(.fileReadCorruptFile) }
            mel = AudioMelSpectrogram(sampleRate: Self.sampleRate, nMels: Self.melBins, nFFT: 512, hopLength: Self.hop,
                                      winLength: 400, window: window, filterbank: filterbank)
        } catch let error as AudioKitError {
            throw error
        } catch {
            throw AudioKitError.modelFailed("Word timing", "Couldn't load the timing model: \(error.localizedDescription)")
        }
    }

    private static func floats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// A new start for each word the model could place, in seconds from the audio's start; nil for a word
    /// it couldn't, which keeps its own time.
    ///
    /// - Parameters:
    ///   - words: The transcript's words, in order of start.
    ///   - audio: The audio they were heard in, any sample rate.
    public func starts(of words: [TimedWord], in audio: AudioSamples) throws -> [TimeInterval?] {
        var result = [TimeInterval?](repeating: nil, count: words.count)
        guard !words.isEmpty else { return result }
        let samples = try audio.resampled(to: Double(Self.sampleRate)).samples
        guard samples.count > Self.hop * 2 else { return result }
        let pieces = words.map { tokenizer.encode($0.text) }
        let duration = Double(samples.count) / Double(Self.sampleRate)
        let spans = AlignmentPlan.spans(starts: words.map(\.start), duration: duration, window: Self.windowDuration)

        // A window's output is kept only while a stretch still needs it: three at most.
        var outputs: [Int: WindowOutput] = [:]
        for span in spans {
            try Task.checkCancellation()
            for window in span.windows where outputs[window] == nil {
                outputs[window] = try run(window: window, of: samples)
            }
            for window in outputs.keys where window < span.windows.lowerBound { outputs[window] = nil }

            // The words that can be placed, and the columns of the model's output their pieces need.
            let placeable = span.words.filter { pieces[$0] != nil }
            guard !placeable.isEmpty else { continue }
            var column: [Int: Int] = [tokenizer.blank: 0]
            var wordColumns: [[Int]] = []
            for index in placeable {
                wordColumns.append((pieces[index] ?? []).map { id in
                    if let known = column[id] { return known }
                    column[id] = column.count
                    return column.count - 1
                })
            }
            let ids = column.sorted { $0.value < $1.value }.map(\.key)
            var rows: [[Float]] = []
            var firstFrame = 0
            for (offset, window) in span.windows.enumerated() {
                guard let output = outputs[window] else { continue }
                if offset == 0 { firstFrame = window * Int(Self.windowDuration / Self.frameDuration) }
                rows.append(contentsOf: output.rows(for: ids))
            }
            guard let placements = ForcedAligner.align(logProbabilities: rows, words: wordColumns, blank: 0) else { continue }
            for (index, placement) in zip(placeable, placements) where span.kept.contains(index) {
                result[index] = Double(firstFrame + placement.frames.lowerBound) * Self.frameDuration
            }
        }
        return result
    }

    /// One window's output: every piece's log-probability on each of its 40 ms frames.
    struct WindowOutput {
        let array: MLMultiArray
        let frames: Int

        /// The frames' log-probabilities for these pieces only, in this order.
        func rows(for ids: [Int]) -> [[Float]] {
            let frameStride = array.strides[1].intValue, pieceStride = array.strides[2].intValue
            return array.withUnsafeBufferPointer(ofType: Float16.self) { values in
                (0..<frames).map { frame in
                    ids.map { Float(values[frame * frameStride + $0 * pieceStride]) }
                }
            }
        }
    }

    /// Runs the model on one 30 s window of the audio, as FluidInference's own evaluation does: the window's
    /// features are worked out and normalized by themselves.
    func run(window: Int, of samples: [Float]) throws -> WindowOutput {
        let length = Self.windowMelFrames * Self.hop
        let begin = window * length
        let part = Array(samples[min(begin, samples.count)..<min(begin + length, samples.count)])
        let valid = part.count / Self.hop
        guard valid > 1 else { throw AudioKitError.modelFailed("Word timing", "A window of the audio was empty.") }
        let frameCount = valid + 1
        let (flat, _, _) = mel.computeFlatTransposed(audio: part, paddingMode: .center, expectedFrameCount: frameCount)
        let input = try MLMultiArray(shape: [1, Self.melBins as NSNumber, Self.windowMelFrames as NSNumber], dataType: .float32)
        let rowStride = input.strides[1].intValue
        input.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            values.initialize(repeating: 0)
            // NeMo's per-feature normalization: each mel bin's mean and unbiased deviation over the valid frames.
            for bin in 0..<Self.melBins {
                var sum = 0.0
                for frame in 0..<valid { sum += Double(flat[frame * Self.melBins + bin]) }
                let mean = sum / Double(valid)
                var squares = 0.0
                for frame in 0..<valid {
                    let difference = Double(flat[frame * Self.melBins + bin]) - mean
                    squares += difference * difference
                }
                let deviation = (squares / Double(valid - 1)).squareRoot() + 1e-5
                for frame in 0..<valid {
                    values[bin * rowStride + frame] = Float((Double(flat[frame * Self.melBins + bin]) - mean) / deviation)
                }
            }
        }
        let encoderFrames = (valid + Self.stack - 1) / Self.stack
        let length32 = try MLMultiArray(shape: [1], dataType: .int32)
        length32[0] = NSNumber(value: encoderFrames)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": input, "enc_len": length32]))
        guard let table = output.featureValue(for: "logp_cast_fp16")?.multiArrayValue, table.dataType == .float16 else {
            throw AudioKitError.modelFailed("Word timing", "The timing model returned no probabilities.")
        }
        return WindowOutput(array: table, frames: min(2 * encoderFrames, table.shape[1].intValue))
    }
}
