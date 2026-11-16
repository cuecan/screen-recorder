import AVFoundation
import CoreImage
import Foundation
import ProjectKit

/// One stretch of the timeline for ``LayoutCompositor``: for each output panel, its background and the
/// pictures drawn on it, each from a composition track or a still image.
final class LayoutInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    /// One thing drawn: a picture from a composition track, or a still overlay by its key in ``stills``.
    enum Item {
        case track(Placement, CMPersistentTrackID)
        case image(Placement, String)

        var placement: Placement {
            switch self {
            case .track(let placement, _), .image(let placement, _): placement
            }
        }
    }

    /// One output in the composition: where it is in the frame, its plain background, and its pictures,
    /// back to front, placed in the panel's own coordinates.
    struct Panel {
        var rect: CGRect
        var background: (red: Double, green: Double, blue: Double)
        /// The base look behind the tiles: the plain colour, or a fixed look with its own motion
        /// (docs/decisions.md, 81).
        var backdrop: OutputLook.Backdrop = .plain
        /// What's added to it: shadows and a lit edge.
        var addOns: Set<OutputLook.AddOn> = []
        var items: [Item]
        /// The captions drawn over everything in this panel, when they're on (docs/decisions.md, 80).
        var captions: PanelCaptions? = nil
    }

    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let panels: [Panel]
    let renderSize: CGSize
    /// The still overlays' pictures, by key, shared by every instruction.
    let stills: [String: CIImage]

    init(timeRange: CMTimeRange, panels: [Panel], renderSize: CGSize, stills: [String: CIImage]) {
        self.timeRange = timeRange
        self.panels = panels
        self.renderSize = renderSize
        self.stills = stills
        var trackIDs = Set<CMPersistentTrackID>()
        for panel in panels {
            for case .track(_, let id) in panel.items { trackIDs.insert(id) }
        }
        requiredSourceTrackIDs = trackIDs.sorted().map { NSNumber(value: $0) }
        super.init()
    }

    /// The same drawing over another stretch of time.
    func covering(_ range: CMTimeRange) -> LayoutInstruction {
        LayoutInstruction(timeRange: range, panels: panels, renderSize: renderSize, stills: stills)
    }
}
