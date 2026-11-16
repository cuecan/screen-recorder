import AppKit

/// An inline correction covers the original transcript while it is being edited. AppKit's multiline
/// field can ignore drawsBackground; paint the backing explicitly, resolving the current appearance.
final class TranscriptFixField: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        // AppKit can supply damage outside a child view's bounds when view clipping is disabled.
        dirtyRect.intersection(bounds).fill()
        super.draw(dirtyRect)
    }
}
