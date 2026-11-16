import ProjectKit
import SwiftUI

/// The card's nine places as a three by three grid of dots, the chosen one filled (docs/decisions.md, 89;
/// docs/ui/mockups/LayoutsTwoKinds.html). The setup's Layout choices and the editor's Card section share it.
struct CardPositionGrid: View {
    /// Nil when the selected clips differ: no dot is filled.
    let position: Card.Position?
    var height: CGFloat = 50
    /// The chosen dot's ring. The HUD passes its own blue: a panel that never becomes key would grey the accent.
    var tint = Color.accentColor
    let pick: (Card.Position) -> Void

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let place = Card.Position.allCases[row * 3 + column]
                        Dot(place: place, isOn: place == position, tint: tint, alignment: column == 0 ? .leading : column == 2 ? .trailing : .center) { pick(place) }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: height)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card position")
    }

    private struct Dot: View {
        let place: Card.Position
        let isOn: Bool
        let tint: Color
        let alignment: Alignment
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(isOn ? Color.white : Color.primary.opacity(isHovered ? 0.45 : 0.22))
                    .frame(width: isOn ? 8 : 10, height: isOn ? 8 : 10)
                    .padding(isOn ? 3 : 2)
                    .background(isOn ? tint : .clear, in: .circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(place.label)
            .accessibilityLabel(place.label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}
