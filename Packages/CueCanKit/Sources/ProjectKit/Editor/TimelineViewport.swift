import Foundation

/// The visible part of a timeline, in content points. Drawing and navigation share this geometry so
/// zooming keeps a visible playhead in place and keyboard navigation can reveal an offscreen edit.
public struct TimelineViewport: Equatable, Sendable {
    public let offset: Double
    public let width: Double

    public init(offset: Double = 0, width: Double) {
        self.offset = offset.isFinite ? max(0, offset) : 0
        self.width = width.isFinite ? max(1, width) : 1
    }

    /// Content points worth drawing, including a small margin for strokes crossing the viewport edge.
    public var drawingBounds: ClosedRange<Double> { max(0, offset - 16)...(offset + width + 16) }

    /// The source-independent time range covered by the drawing bounds.
    public func timeRange(zoom: Double) -> TimeRange {
        let zoom = TimelineZoom.clamped(zoom)
        return TimeRange(start: max(0, (drawingBounds.lowerBound - TimelineLane.leading) / zoom),
                         end: max(0, (drawingBounds.upperBound - TimelineLane.leading) / zoom))
    }

    /// A legal horizontal scroll offset for the edit and its trailing margin.
    public func clampedOffset(_ proposed: Double, duration: TimeInterval, zoom: Double) -> Double {
        guard proposed.isFinite, duration.isFinite, duration >= 0 else { return 0 }
        let contentWidth = max(width, duration * TimelineZoom.clamped(zoom) + TimelineZoom.horizontalPadding)
        return min(max(0, proposed), max(0, contentWidth - width))
    }

    /// Keeps the playhead at its current screen position when visible. When the user has scrolled away
    /// from it, zoom around the middle of what they are looking at instead of taking them elsewhere.
    public func offsetAfterZoom(from oldZoom: Double, to newZoom: Double, playhead: TimeInterval, duration: TimeInterval) -> Double {
        let oldZoom = TimelineZoom.clamped(oldZoom)
        let newZoom = TimelineZoom.clamped(newZoom)
        let playheadX = TimelineLane.leading + playhead * oldZoom
        let anchorX = playhead.isFinite && offset <= playheadX && playheadX <= offset + width ? playheadX : offset + width / 2
        let anchorTime = max(0, (anchorX - TimelineLane.leading) / oldZoom)
        return clampedOffset(TimelineLane.leading + anchorTime * newZoom - (anchorX - offset), duration: duration, zoom: newZoom)
    }

    /// Reveals an explicitly navigated-to time with some context on either side. Times already visible
    /// do not move the viewport. Playback pages forward only when it reaches the visible edge.
    public func offsetRevealing(_ time: TimeInterval, duration: TimeInterval, zoom: Double, playing: Bool = false) -> Double {
        guard time.isFinite else { return clampedOffset(offset, duration: duration, zoom: zoom) }
        let x = TimelineLane.leading + time * TimelineZoom.clamped(zoom)
        let margin = min(24, width / 8)
        let proposed: Double
        if x < offset + margin {
            proposed = x - width * (playing ? 0.8 : 0.25)
        } else if x > offset + width - margin {
            proposed = x - width * (playing ? 0.2 : 0.75)
        } else {
            proposed = offset
        }
        return clampedOffset(proposed, duration: duration, zoom: zoom)
    }

    /// Visible waveform bars stay on the clip's original grid while scrolling, so their peaks don't
    /// shimmer as the viewport moves. Work is bounded by the viewport, not the length of the recording.
    public func waveformBars(from left: Double, to right: Double, spacing: Double = 2.5) -> StrideTo<Double> {
        let spacing = spacing.isFinite && spacing > 0 ? spacing : 2.5
        let origin = left + 1
        let first = origin + max(0, floor((drawingBounds.lowerBound - origin) / spacing)) * spacing
        return stride(from: first, to: min(right - 1, drawingBounds.upperBound), by: spacing)
    }
}
