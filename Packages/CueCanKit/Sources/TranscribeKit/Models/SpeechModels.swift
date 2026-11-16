internal import FluidAudio
import Foundation
import ProjectKit
import Synchronization

/// The speech models a take's processing needs: Parakeet, which transcribes; the timing model, which says
/// when each of its words starts (``WordTimer``; docs/decisions.md, 95); and the smaller model that boosts a
/// project's vocabulary and times a fixed word (docs/design.md, "Audio and transcripts").
///
/// Until they ship inside the app (docs/decisions.md, 24) they're downloaded once, by the first take's
/// processing or ahead of it from the setup window (docs/decisions.md, 93).
public enum SpeechModels {
    /// Whether all three are on this Mac, whole: a download that was interrupted doesn't count.
    public static var areDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
            && CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: .ctc110m))
            && WordTimer.isInstalled
    }

    /// Downloads whichever is missing. `progress` gets the fraction done, from 0 to 1.
    ///
    /// - Parameter directory: Where to put them, for a test. Nil is where the app looks for them.
    public static func download(to directory: URL? = nil, progress: @escaping @Sendable (Double) -> Void) async throws {
        // The downloader reports thousands of times, from several threads and not always in order. What's
        // passed on is each new whole percent, so the bar only moves forward and a line is worth sending.
        let reported = Mutex(-1)
        let report: @Sendable (Double) -> Void = { fraction in
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded(.down))
            let isNew = reported.withLock { last in
                guard percent > last else { return false }
                last = percent
                return true
            }
            if isNew { progress(Double(percent) / 100) }
        }
        report(0)
        try await AsrModels.download(to: directory?.appending(path: "transcription"), version: .v3) { update in
            report(SpeechModelsProgress.overall(transcription: update.fractionCompleted))
        }
        report(SpeechModelsProgress.transcriptionShare)
        // This one reports no progress of its own, so the bar waits for it.
        try await CtcModels.download(to: directory?.appending(path: "vocabulary"), variant: .ctc110m)
        report(SpeechModelsProgress.beforeTiming)
        // Last, so a problem fetching or preparing it leaves the other two downloaded.
        try await TimingModelDownload.install(to: directory.map { $0.appending(path: WordTimer.folderName) } ?? WordTimer.directory) { fraction in
            report(SpeechModelsProgress.overall(timing: fraction))
        }
        report(1)
    }
}
