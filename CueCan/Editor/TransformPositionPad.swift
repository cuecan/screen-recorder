import SwiftUI

/// A direct spatial control for a static crop centre. The axes stay in recorded-image coordinates,
/// irrespective of the camera's mirror setting; the point commits once on release.
struct TransformPositionPad: View {
    let x: Double?
    let y: Double?
    var preview: ((Double, Double) -> Void)? = nil
    let set: (Double, Double) -> Void
    @State private var pending: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let point = pending ?? CGPoint(x: x ?? 0.5, y: y ?? 0.5)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4))
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Image(systemName: "scope")
                    .foregroundStyle(x == nil || y == nil ? Color.secondary : Color.accentColor)
                    .position(x: 6 + point.x * max(0, geometry.size.width - 12), y: 6 + point.y * max(0, geometry.size.height - 12))
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    let point = bounded(event.location, in: geometry.size)
                    pending = point
                    preview?(point.x, point.y)
                }
                .onEnded { event in
                    let point = bounded(event.location, in: geometry.size)
                    pending = nil
                    set(point.x, point.y)
                })
        }
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel("Framing center")
        .accessibilityValue(x.flatMap { x in y.map { "X \(Int((x * 100).rounded()))%, Y \(Int(($0 * 100).rounded()))%" } } ?? "Mixed")
        .accessibilityHint("Use the Center X and Y fields for precise values.")
        .help("Click or drag to set the centre.")
    }

    private func bounded(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, (point.x - 6) / max(1, size.width - 12))),
                y: min(1, max(0, (point.y - 6) / max(1, size.height - 12))))
    }
}
