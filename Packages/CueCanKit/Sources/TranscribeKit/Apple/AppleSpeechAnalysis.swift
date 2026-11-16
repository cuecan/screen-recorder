import AVFoundation
import AudioKit
import Foundation
import Speech

/// Runs Apple's speech modules (`SpeechTranscriber`, `SpeechDetector`) over audio in memory, in one
/// analysis: the shared plumbing behind ``SpeechAnalyzerEngine`` and ``SpeechDetectorSilenceDetector``.
///
/// It does what Apple's documentation asks: installs any missing language assets, asks `SpeechAnalyzer`
/// for the format every module accepts, converts the audio to it, and streams it in. Feeding the modules
/// another format can stop the program rather than throw (`SpeechDetector` with float samples, macOS 27.2).
enum AppleSpeechAnalysis {
    /// How long each piece of audio handed to the analyzer is.
    static let pieceDuration: TimeInterval = 1

    /// A buffer in consecutive pieces of `frames` frames each, the last one shorter, in any PCM format.
    ///
    /// The audio is converted once and then sliced, rather than converted piece by piece, so a
    /// resampler's start-up never drops samples at each piece and shifts the words after it.
    static func pieces(of buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) throws -> [AVAudioPCMBuffer] {
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var pieces: [AVAudioPCMBuffer] = []
        var start: AVAudioFrameCount = 0
        while start < buffer.frameLength {
            let length = min(max(1, frames), buffer.frameLength - start)
            guard let piece = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: length) else {
                throw AudioKitError.conversionFailed("Couldn't allocate \(length) frames.")
            }
            piece.frameLength = length
            let destination = UnsafeMutableAudioBufferListPointer(piece.mutableAudioBufferList)
            for (from, to) in zip(source, destination) {
                guard let fromData = from.mData, let toData = to.mData else { continue }
                toData.copyMemory(from: fromData.advanced(by: Int(start) * bytesPerFrame), byteCount: Int(length) * bytesPerFrame)
            }
            pieces.append(piece)
            start += length
        }
        return pieces
    }

    /// The locale macOS can transcribe that's closest to a BCP 47 code, or to the Mac's own locale.
    static func locale(for language: String?) async throws -> Locale {
        let requested = Locale(identifier: language ?? Locale.current.identifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw AudioKitError.modelFailed("Apple SpeechAnalyzer", "macOS doesn't support transcribing \(requested.identifier).")
        }
        return locale
    }

    /// Analyzes the audio with the modules. Read each module's results concurrently, before calling this,
    /// or the analysis waits on them.
    static func analyze(_ audio: AudioSamples, with modules: [any SpeechModule]) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw AudioKitError.modelFailed("Apple SpeechAnalyzer", "No audio format suits these speech modules.")
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.prepareToAnalyze(in: format)
        // In short pieces, as a live source would deliver it: handed a long recording as one buffer, the
        // transcriber lost words (macOS 27.2).
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let converted = try audio.pcmBuffer(in: format)
        for piece in try pieces(of: converted, frames: AVAudioFrameCount(pieceDuration * format.sampleRate)) {
            continuation.yield(AnalyzerInput(buffer: piece))
        }
        continuation.finish()
        if let end = try await analyzer.analyzeSequence(input) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }
}
