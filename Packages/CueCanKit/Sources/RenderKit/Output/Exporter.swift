import AVFoundation
import Foundation
import ProjectKit

/// Writes the edit as a video file through the hardware encoder, from the same composition the preview
/// plays, with its sound brought to the export loudness on the final mix (docs/decisions.md, 35).
public enum Exporter {
    /// Brings the final mono mix to the export loudness. The `cuecan` CLI and the app pass AudioKit's
    /// Loudness stage, so RenderKit doesn't depend on AudioKit.
    public typealias Mastering = @Sendable (_ samples: [Float], _ sampleRate: Double) async throws -> [Float]

    /// Exports one shape to `url` (an `.mp4`), replacing any file there. It's written beside it first and
    /// moved into place only when finished, so a stopped export leaves nothing half-written.
    ///
    /// - Parameter progress: Called now and then with how far it is, from 0 to 1.
    public static func export(
        _ inputs: RenderInputs,
        output: OutputShape,
        to url: URL,
        settings: ExportSettings = ExportSettings(),
        mastering: Mastering?,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        var built = try await CompositionBuilder.build(inputs, output: output, scale: settings.scale)
        let temporary = FileManager.default.temporaryDirectory.appending(path: "cuecan-mix-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }

        if let mastering, try await MasteredSound.writeMix(of: built, to: temporary, using: mastering) {
            built = try await MasteredSound.replacingSound(in: built, with: temporary)
        }

        try Task.checkCancellation()
        guard let session = AVAssetExportSession(asset: built.composition, presetName: preset(settings.codec)) else {
            throw RenderError.exportFailed("This Mac can't export \(settings.codec.displayName).")
        }
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        session.audioTimePitchAlgorithm = CompositionBuilder.pitchAlgorithm
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = url.deletingLastPathComponent().appending(path: ".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).partial.mp4")
        defer { try? FileManager.default.removeItem(at: partial) }
        // The session reports its own state; reading it from another task is what its states sequence is for.
        nonisolated(unsafe) let watched = session
        let watcher = progress.map { report in
            Task {
                for await state in watched.states(updateInterval: 0.25) {
                    if case .exporting(let progress) = state { report(progress.fractionCompleted) }
                }
            }
        }
        defer { watcher?.cancel() }
        do {
            try await session.export(to: partial, as: .mp4)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw RenderError.exportFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        _ = try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: partial, to: url)
        progress?(1)
    }

    /// Writes the SRT for the edit.
    public static func writeSRT(_ inputs: RenderInputs, to url: URL) throws {
        let timeline = EditTimeline(edit: inputs.edit, transcripts: inputs.transcripts)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SRTWriter.srt(inputs.srtCues(timeline: timeline)).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes the edit's words as plain text.
    public static func writeText(_ inputs: RenderInputs, to url: URL) throws {
        let timeline = EditTimeline(edit: inputs.edit, transcripts: inputs.transcripts)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TextTranscriptWriter.text(inputs.srtCues(timeline: timeline)).write(to: url, atomically: true, encoding: .utf8)
    }

    static func preset(_ codec: ExportSettings.Codec) -> String {
        // The highest-quality presets keep the video composition's render size, so a Short stays 1080 × 1920.
        codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    }

}
