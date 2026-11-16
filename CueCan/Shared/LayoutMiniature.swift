import ProjectKit
import RenderKit
import SwiftUI

/// One output of a layout, drawn small from ``LayoutGeometry``, in a look (docs/decisions.md, 66; docs/ui.md,
/// L1): the screen as a little white window with a title bar and lines, the camera as a dark tile with
/// `person.fill`, on the look's background. No colour coding. The setup bar's Layout menu draws presets
/// with it; the editor's inspector draws each layout for the clip's own take, so a layout the take wasn't
/// recorded for shows its screen on the background.
struct LayoutMiniature: View {
    let layout: ProjectKit.Layout
    let output: OutputShape
    let pictures: ClipPictures
    let look: OutputLook
    let height: CGFloat

    var body: some View {
        let frame = LayoutGeometry.frame(for: layout, in: output, pictures: pictures, look: look)
        let scale = height / frame.size.height
        let background = look.backgroundComponents
        ZStack(alignment: .topLeading) {
            Color(red: background.red, green: background.green, blue: background.blue)
            ForEach(Array(frame.placements.enumerated()), id: \.offset) { _, placement in
                let rect = placement.frame
                let corners = placement.outlineCorners
                let shape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                    topLeading: corners.topLeft * scale, bottomLeading: corners.bottomLeft * scale,
                    bottomTrailing: corners.bottomRight * scale, topTrailing: corners.topRight * scale), style: .continuous)
                Group {
                    if placement.role == .screen {
                        MiniWindow()
                    } else {
                        ZStack {
                            Color(white: 0.23)
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white.opacity(0.78))
                                .padding(min(rect.width, rect.height) * scale * 0.24)
                        }
                    }
                }
                .frame(width: rect.width * scale, height: rect.height * scale)
                .clipShape(shape)
                .offset(x: rect.minX * scale, y: rect.minY * scale)
            }
        }
        .frame(width: frame.size.width * scale, height: height)
        .clipShape(.rect(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

/// The screen drawn as a little window: white, a title bar, and lines of text.
private struct MiniWindow: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let bar = max(1.5, size.height * 0.09)
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: bar)), with: .color(Color(white: 0.94)))
            let line = max(1, size.height * 0.035), period = max(3, size.height * 0.1)
            var y = max(3, size.height * 0.2)
            while y + line < size.height * 0.88 {
                context.fill(Path(CGRect(x: size.width * 0.1, y: y, width: size.width * 0.64, height: line)), with: .color(Color(white: 0.86)))
                y += period
            }
        }
    }
}
