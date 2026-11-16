import RecorderKit
import RenderKit
import SwiftUI

/// The area's move handle, alone in its dark capsule in the middle of the area (docs/ui.md, R10): Start
/// recording is at the right end of the setup element's strip, and Return still starts (docs/decisions.md,
/// 79).
struct AreaCapsuleView: View {
    let controller: CaptureAreaController

    var body: some View {
        ZStack {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .allowsHitTesting(false)
            AreaMoveHandle(controller: controller)
        }
        .frame(width: 38, height: 38)
        .background(.white.opacity(0.1), in: .circle)
        .help("Drag to move the area")
        .accessibilityLabel("Drag to move the area")
        .padding(5)
        .hudBackground(cornerRadius: 24)
        .fixedSize()
    }
}

/// Where the camera will cover the screen, shaded in green hatching (docs/ui.md, L1): a corner for Bubble,
/// an edge for Card. It stays while recording, fainter, so the creator keeps what matters out of it
/// (docs/decisions.md, 66). Never recorded: the panel isn't shareable, and the app is left out of the capture.
struct CameraCoverView: View {
    /// The covered part's corners, as fractions of the screen's height.
    let corners: Corners
    /// The area's height in points, which the corners are fractions of.
    let scale: CGFloat
    let size: CGSize
    /// Recording: drawn fainter, like the area's quieter frame.
    var isQuiet = false

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: corners.topLeft * scale, bottomLeading: corners.bottomLeft * scale,
            bottomTrailing: corners.bottomRight * scale, topTrailing: corners.topRight * scale), style: .continuous)
        Canvas { context, size in
            var lines = Path()
            let step: CGFloat = 9
            var x = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(lines, with: .color(.green.opacity(isQuiet ? 0.22 : 0.55)), lineWidth: isQuiet ? 1 : 1.5)
        }
        .background(Color.green.opacity(isQuiet ? 0.05 : 0.14))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.green.opacity(isQuiet ? 0.45 : 0.85), lineWidth: isQuiet ? 1 : 1.5))
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

/// The label above the frame: its size, then how to resize it.
struct AreaLabelView: View {
    let title: String

    var body: some View {
        Text(title)
            .fontWeight(.semibold)
            .monospacedDigit()
            .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.6), in: .capsule)
        .fixedSize()
    }
}

/// What the area says while a window is dragged over it (docs/ui.md, R3).
struct ReleaseToSnapView: View {
    let appName: String

    var body: some View {
        Text("Release to snap \(appName) in")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .hudBackground(cornerRadius: 22)
            .fixedSize()
    }
}

/// The line under the area while a window is dragged over it.
struct WillFillView: View {
    let area: CGSize

    var body: some View {
        Text("It will fill the area")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: .capsule)
            .fixedSize()
    }
}

/// The notice at the frame when a dropped window can't fit, or can't be moved (docs/ui.md, R4).
struct SnapNoticeView: View {
    let notice: CaptureAreaController.SnapNotice
    let controller: CaptureAreaController
    /// Whether the area may change: only while setting up, never during a recording.
    let canResizeArea: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(notice.message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)
            switch notice {
            case .needsAccess:
                Button("Open \(CaptureAreaController.windowAccessPaneName) Settings") { controller.openAccessibilitySettings() }
                Button("OK") { controller.dismissNotice() }
                    .keyboardShortcut(.cancelAction)
            case .cannotMove:
                Button("OK") { controller.dismissNotice() }
                    .keyboardShortcut(.cancelAction)
            case .doesNotFit(_, _, _, let bigger):
                if notice.offersBiggerArea, canResizeArea {
                    Button("Use a bigger area") { controller.useBiggerArea() }
                        .disabled(bigger == nil)
                        .help(bigger == nil ? "No area of this shape fits this display at that size" : "Make the area big enough for this window")
                }
                Button("OK") { controller.dismissNotice() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.callout)
        .controlSize(.small)
        .foregroundStyle(.white)
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .hudBackground(cornerRadius: 10)
        .fixedSize()
    }
}
