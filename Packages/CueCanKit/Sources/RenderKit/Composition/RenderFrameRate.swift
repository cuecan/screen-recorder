import Foundation
import ProjectKit

/// The one frame clock for the preview, the finished video and the editor handoff (docs/design.md, "Frame
/// clock"): the fastest rate any picture the edit plays was captured at, as a standard editing rate (24, 25,
/// 30, 50 or 60, the next one up). It follows the rate capture was set to, not the measured one: the screen
/// sends a frame only when something on it changes, so its average says how busy it was, and a quiet take
/// measured at 31 would otherwise get a 50 fps clock that neither a 60 fps screen nor a 30 fps camera fits.
public enum RenderFrameRate {
    /// The clock for an edit that plays these sources' pictures. 30 when none has a picture.
    public static func standard(for project: Project, playing sources: some Sequence<SourceID>) -> Int {
        let playing = Set(sources)
        let rates = project.sources.filter { playing.contains($0.id) }.flatMap(\.tracks).compactMap(\.media.video?.captureRate)
        return standard(forCaptureRates: rates)
    }

    static func standard(forCaptureRates rates: [Int]) -> Int {
        guard let fastest = rates.filter({ $0 > 0 }).max() else { return 30 }
        return [24, 25, 30, 50, 60].first { $0 >= fastest } ?? 60
    }
}
