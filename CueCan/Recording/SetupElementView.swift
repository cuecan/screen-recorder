import RecorderKit
import SwiftUI

/// Setting up as one element (docs/ui.md, R10; docs/decisions.md, 79): the title bar, the live preview of the
/// export in a dark well, the Layout menu when it's open, and the two-row strip. Dragged by its title bar,
/// the well or any background.
struct SetupElementView: View {
    let recorder: RecorderModel
    let element: SetupElementController

    var body: some View {
        let previewHeight = SetupElementLayout.previewHeight(for: recorder.destination, visibleHeight: element.visibleHeight)
        VStack(spacing: 0) {
            SetupTitleBar(recorder: recorder, element: element)
            VStack(spacing: 0) {
                well(previewHeight: previewHeight)
                SetupStripView(recorder: recorder)
                    .opacity(element.isLeaving ? 0 : 1)
                    .offset(y: element.isLeaving ? 12 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 7)
        }
        .frame(width: SetupElementLayout.width)
        .foregroundStyle(.white)
        .hudBackground(cornerRadius: 18, movesWindow: true)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { element.contentSizeChanged($0) }
    }

    /// The preview centred in a dark well as wide as the element, so a narrow preview reads as a picture on
    /// a monitor; or, in its place, the Layout choices or framing, so the element never
    /// changes size. The well's empty space drags the window.
    private func well(previewHeight: Double) -> some View {
        let covered: Bool = switch recorder.well {
        case .choices: recorder.recordsScreen && recorder.format != nil
        case .framing: recorder.framingBlocker == nil
        case .preview: false
        }
        return ZStack {
            WindowDragArea()
            // Keep its native camera layers and screen stream attached while choices or framing cover
            // the preview. Recreating them on every selection leaves a blank frame while they reconnect.
            ExportPreviewView(recorder: recorder, height: previewHeight, isFloating: true, plainLabels: true,
                              mainCameraFrame: { element.cameraFrameInWindow = $0 })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { element.previewFrameInWindow = $0 }
                .opacity(covered ? 0 : 1)
                .allowsHitTesting(!covered)
                .accessibilityHidden(covered)
            switch recorder.well {
            case .choices where recorder.recordsScreen && recorder.format != nil:
                LayoutMenuContent(recorder: recorder, previewHeight: previewHeight) { recorder.toggleLayoutChoices() }
            case .framing(let slot) where recorder.framingBlocker == nil:
                WellFramingView(recorder: recorder, slot: slot, previewHeight: previewHeight)
            default:
                EmptyView()
            }
        }
        .frame(height: previewHeight + SetupElementLayout.wellPadding * 2)
        .background(.black.opacity(0.42), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

/// The element's title bar (R10): the dot, "Ready" and the format, or the reason it can't start yet, then
/// Settings and Cancel at its right.
///
/// The entire bar but its two buttons is a drag target: the whole bar is a
/// ``WindowDragArea`` with only the two buttons above it, and the dot and the labels are plain text that
/// takes no clicks. AppKit's drag by background doesn't reach through SwiftUI's hosting view.
private struct SetupTitleBar: View {
    let recorder: RecorderModel
    let element: SetupElementController

    var body: some View {
        // Claude's proposal, AUTHOR'S TAKE NEEDED: a grey dot and the reason, in place of "Ready".
        let reason = recorder.startConditions.headline
        ZStack {
            WindowDragArea()
            HStack(spacing: 7) {
                Circle()
                    .fill(reason == nil ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if let reason {
                    Text(reason).fontWeight(.semibold).lineLimit(1)
                } else {
                    Text("Ready").fontWeight(.semibold)
                    Text(recorder.formatLabel)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .padding(.trailing, 60)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                TitleBarButton(systemImage: "slider.horizontal.3", size: 9.5, label: "Settings", help: "Settings (⌘,)") {
                    recorder.openRecordingSettings()
                }
                TitleBarButton(systemImage: "xmark", size: 8, label: "Cancel", help: "Cancel (Esc)") {
                    recorder.closeSetup()
                }
            }
            .padding(.trailing, 9)
        }
        .font(.system(size: 12))
        .frame(height: SetupElementLayout.headerHeight)
        // In front of the text and its hosting view, not behind it. Only the two buttons' 55 pt strip
        // remains above the drag surface, so pressing a label, dot or empty space has the same behavior.
        .overlay {
            WindowDragArea()
                .padding(.trailing, 55)
        }
    }
}

/// One of the title bar's two 18 pt circles.
private struct TitleBarButton: View {
    let systemImage: String
    let size: CGFloat
    let label: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.8))
                .frame(width: 18, height: 18)
                .background(.white.opacity(isHovered ? 0.24 : 0.14), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}
