import CoreGraphics
import Foundation

/// What the Full panel's preview stream should show: a crop of one display.
public struct PreviewTarget: Sendable, Equatable {
    public var displayID: CGDirectDisplayID
    /// The crop in the display's own points, from its top left.
    public var sourceRect: CGRect

    public init(displayID: CGDirectDisplayID, sourceRect: CGRect) {
        self.displayID = displayID
        self.sourceRect = sourceRect
    }
}

/// Brings ``AreaPreview`` to the crop that's wanted, one step at a time, remembering only what was really
/// applied. A failed step leaves the applied crop as it was, so asking for the same crop again retries it.
public struct PreviewReconciler: Sendable, Equatable {
    /// The next thing to do to the stream.
    public enum Step: Sendable, Equatable {
        /// It already shows what's wanted.
        case none
        /// Start a stream, stopping any on another display first.
        case start(PreviewTarget)
        /// Move the running stream's crop on the same display.
        case update(PreviewTarget)
        /// Nothing should show it.
        case stop
    }

    /// What the running stream shows, as last confirmed. Nil when no stream runs.
    public private(set) var applied: PreviewTarget?

    public init() {}

    public func step(toward wanted: PreviewTarget?) -> Step {
        guard let wanted else { return applied == nil ? .none : .stop }
        guard let applied else { return .start(wanted) }
        if applied == wanted { return .none }
        return applied.displayID == wanted.displayID ? .update(wanted) : .start(wanted)
    }

    /// A step succeeded: the stream shows `target` now, or nothing.
    public mutating func didApply(_ target: PreviewTarget?) {
        applied = target
    }
}
