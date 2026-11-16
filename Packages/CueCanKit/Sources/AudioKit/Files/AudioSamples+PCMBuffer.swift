import AVFoundation
import Foundation

extension AudioSamples {
    /// The audio as one buffer in another format, converted with `AVAudioConverter`: for frameworks that
    /// want a particular rate and sample type, such as Apple's speech analysis.
    public func pcmBuffer(in format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard sampleRate.isFinite, sampleRate > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw AudioKitError.conversionFailed("Sample rates must be finite and greater than zero.")
        }
        guard let source = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(1, samples.count)))
        else {
            throw AudioKitError.conversionFailed("Couldn't describe the audio as \(sampleRate) Hz mono.")
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { input.floatChannelData?[0].update(from: base, count: values.count) }
        }
        guard let converter = AVAudioConverter(from: source, to: format) else {
            throw AudioKitError.conversionFailed("Couldn't convert to \(format).")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let capacity = AVAudioFrameCount((Double(samples.count) * format.sampleRate / sampleRate).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioKitError.conversionFailed("Couldn't allocate \(capacity) frames.")
        }
        nonisolated(unsafe) var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw AudioKitError.conversionFailed(conversionError?.localizedDescription ?? "Conversion failed.")
        }
        return output
    }
}
