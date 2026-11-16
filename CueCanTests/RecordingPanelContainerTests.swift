import AppKit
import SwiftUI
import Testing
@testable import CueCan

@MainActor
struct RecordingPanelContainerTests {
    @Test func nativeHandlesAreSiblingsOfTheHostingViewAndLeaveTheContentClickable() {
        let content = NSHostingView(rootView: Color.clear.frame(width: 400, height: 300))
        content.sizingOptions = [.intrinsicContentSize]
        content.setFrameSize(content.fittingSize)
        let container = RecordingPanelContainer(content: content)
        #expect(container.subviews.count == 2)
        #expect(content.superview === container)
        #expect(container.handles.superview === container)
        #expect(container.handles.hitTest(CGPoint(x: 200, y: 150)) == nil)
        #expect(container.hitTest(CGPoint(x: 200, y: 150)) !== container.handles)
        for point in [CGPoint(x: 1, y: 150), CGPoint(x: 399, y: 150), CGPoint(x: 200, y: 1),
                      CGPoint(x: 200, y: 299), CGPoint(x: 1, y: 1), CGPoint(x: 399, y: 299)] {
            #expect(container.hitTest(point) === container.handles)
        }
    }

    @Test func theContainerUsesTheHostingViewsFittingSizeAndItsChildrenFollowResizing() {
        let content = NSHostingView(rootView: Color.clear.frame(width: 400, height: 300))
        content.sizingOptions = [.intrinsicContentSize]
        content.setFrameSize(content.fittingSize)
        let container = RecordingPanelContainer(content: content)
        #expect(container.fittingSize == CGSize(width: 400, height: 300))
        content.rootView = Color.clear.frame(width: 500, height: 250)
        content.layoutSubtreeIfNeeded()
        #expect(container.fittingSize == CGSize(width: 500, height: 250))
        container.setFrameSize(CGSize(width: 500, height: 250))
        #expect(content.frame == container.bounds)
        #expect(container.handles.frame == container.bounds)
    }
}
