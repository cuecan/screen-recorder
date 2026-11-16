import AppKit

/// Hosts SwiftUI content and native resize handles as siblings. NSHostingView owns its own subviews.
final class RecordingPanelContainer: NSView {
    let content: NSView
    let handles: PanelResizeHandles

    init(content: NSView, controller: RecordingPanelController? = nil) {
        self.content = content
        handles = PanelResizeHandles(frame: content.bounds)
        handles.controller = controller
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        handles.frame = bounds
        handles.autoresizingMask = [.width, .height]
        addSubview(content)
        addSubview(handles)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize { content.fittingSize }
    override var intrinsicContentSize: NSSize { content.intrinsicContentSize }
}
