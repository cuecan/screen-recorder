import AVFoundation
import Foundation
import ProjectKit

/// Cuts a recorded file down to part of itself, without encoding it again.
///
/// The samples are copied as they are. A movie that starts partway through a frame gets an edit list, so
/// it opens on the frame that was showing at that moment; a WAV is cut to the sample.
enum TrackTrimmer {
    /// Writes the kept part of `url` beside it and returns where. The original is left as it was.
    static func trimmedCopy(of url: URL, keeping range: TimeRange) async throws -> URL {
        let copy = url.deletingLastPathComponent().appending(path: "trimming-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: copy)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw RecorderError.couldNotWrite(copy, "it couldn't be cut to the take's length")
        }
        export.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600_000),
                                       end: CMTime(seconds: range.end, preferredTimescale: 600_000))
        do {
            try await export.export(to: copy, as: fileType(of: url))
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw RecorderError.couldNotWrite(copy, error.localizedDescription)
        }
        return copy
    }

    /// Cuts every file, or none: each is written beside its original first, and the originals are replaced
    /// only once all of them are. A take is never left with some tracks cut and others not.
    static func trim(_ cuts: [(url: URL, keep: TimeRange)]) async throws {
        var copies: [(original: URL, copy: URL)] = []
        do {
            for cut in cuts {
                copies.append((cut.url, try await trimmedCopy(of: cut.url, keeping: cut.keep)))
            }
        } catch {
            for made in copies { try? FileManager.default.removeItem(at: made.copy) }
            throw error
        }
        try TrackTrimPublication.replace(copies)
    }

    private static func fileType(of url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "wav": .wav
        case "m4a": .m4a
        default: .mov
        }
    }
}
