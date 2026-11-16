import Foundation
import Synchronization
import Testing
@testable import TranscribeKit

/// Opt-in: really downloads the speech models, about 960 MB, into a temporary folder, to see that progress
/// arrives and rises. Run with CUECAN_MODELS_DOWNLOAD_CHECK=1.
struct SpeechModelsDownloadCheck {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CUECAN_MODELS_DOWNLOAD_CHECK"] != nil))
    func aRealDownloadReportsRisingProgressAndFinishes() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-models-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let seen = Mutex<[Double]>([])
        try await SpeechModels.download(to: folder) { fraction in seen.withLock { $0.append(fraction) } }
        let fractions = seen.withLock { $0 }
        #expect(fractions.first == 0 && fractions.last == 1)
        #expect(fractions == fractions.sorted() && Set(fractions).count == fractions.count, "The bar only moves forward.")
        #expect(fractions.count <= 101, "At most one update for each percent.")
        #expect(Set(fractions).count > 3, "Progress arrives during the download, not only at its ends: \(Set(fractions).count) values.")
        print("Speech models download check: \(fractions.count) updates, \(Set(fractions).count) distinct")
    }
}
