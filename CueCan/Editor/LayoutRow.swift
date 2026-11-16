import ProjectKit
import RenderKit
import SwiftUI

/// The clip's layout as a row of four tiles (docs/decisions.md, 89; docs/ui/mockups/LayoutsTwoKinds.html, E-A
/// to E-E): Side by side, Card, Camera and Screen, each drawn for the clip's own take in the shape shown. One
/// the take can't show is dimmed and says why, so the row is always the same four.
struct LayoutTiles: View {
    /// The shape the editor shows, which the pictures are drawn in.
    let output: OutputShape
    let destination: VideoFormat.Destination
    let pictures: ClipPictures
    let look: OutputLook
    /// A resolved layout representing the shared button; nil when the selected layout kinds differ.
    let current: ProjectKit.Layout?
    let pick: (LayoutChoice) -> Void

    private var hasRoom: Bool {
        pictures.screen.map { ProjectKit.Layout.hasRoom(besideScreen: $0.width / max($0.height, 1), in: output) } ?? false
    }
    private var offered: [LayoutChoice] {
        LayoutChoice.offered(of: destination, hasScreen: pictures.screen != nil, hasCamera: pictures.person != nil, hasRoom: hasRoom)
    }
    /// All four for a take with a screen and a camera; otherwise only what it has.
    private var shown: [LayoutChoice] {
        pictures.screen != nil && pictures.person != nil ? LayoutChoice.allCases : offered
    }
    private var height: CGFloat { output == .landscape ? 30 : 46 }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(shown, id: \.self) { choice in
                let isOffered = offered.contains(choice)
                let layout = choice.layout(current: current, recorded: pictures.recordedLayout, destination: destination)
                LayoutTile(name: choice.name, isOn: choice.matches(current), isOffered: isOffered, help: hint(choice, isOffered: isOffered)) {
                    LayoutMiniature(layout: layout, output: output, pictures: isOffered ? pictures : stand(in: choice), look: look, height: height)
                } action: {
                    guard !choice.matches(current) else { return }
                    pick(choice)
                }
            }
        }
    }

    /// A take the dimmed tile can be drawn for: Side by side needs a screen with room beside it.
    private func stand(in choice: LayoutChoice) -> ClipPictures {
        var pictures = pictures
        if choice == .sideBySide {
            let shape = TakeLayout.shares(for: output == .landscape ? .landscape : .vertical)[1]
            pictures.screen = CGSize(width: 1000 * shape.aspect, height: 1000)
            pictures.recordedLayout = .sideBySide(shape)
        }
        return pictures
    }

    private func hint(_ choice: LayoutChoice, isOffered: Bool) -> String {
        switch choice {
        case .sideBySide:
            isOffered ? "The camera \(output == .landscape ? "beside" : "above or below") the screen, at the share it was recorded with"
                : "This take has no room beside the screen"
        case .card: isOffered ? "The camera as a card over the screen" : "A take made for both a video and a Short has no card"
        case .camera: "The camera alone, filling the frame"
        case .screen: "The screen alone"
        }
    }
}

private struct LayoutTile<Picture: View>: View {
    let name: String
    let isOn: Bool
    let isOffered: Bool
    let help: String
    @ViewBuilder let picture: () -> Picture
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                picture()
                Text(name).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isOn ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
            .opacity(isOffered ? 1 : 0.35)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isOffered)
        .help(help)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A card's settings in the clip's Layout section: the same five as the setup's Layout choices
/// (docs/decisions.md, 89), so nothing is free-form and a take starts as set up. A value the selected clips
/// don't share shows nothing chosen until one is picked for all.
struct CardControls: View {
    let cards: [Card]
    /// Whether the screen can be smaller: only in a 16:9 video.
    let offersScreen: Bool
    let change: (_ reason: String, _ body: @escaping (inout Card) -> Void) -> Void

    private func shared<Value: Equatable>(_ value: (Card) -> Value) -> Value? {
        guard let first = cards.first.map(value), cards.allSatisfy({ value($0) == first }) else { return nil }
        return first
    }

    var body: some View {
        if offersScreen {
            InspectorRow("Screen") {
                Picker("Screen", selection: Binding(get: { shared(\.screen) }, set: { value in
                    if let value { change("Card’s screen \(value.label.lowercased())") { $0.screen = value } }
                })) {
                    ForEach(Card.Screen.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .help("Smaller shrinks the screen so the card hangs off its edge.")
            }
        }
        Divider().padding(.vertical, 4)
        Text("Card").font(.callout.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
        // Not an InspectorRow: that lines its title up with a control's first line of text, and the grid has none.
        HStack(spacing: 10) {
            Text("Position").foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            CardPositionGrid(position: shared(\.position), height: 58) { place in change("Card to the \(place.label.lowercased())") { $0.position = place } }
        }
        .font(.callout)
        InspectorRow("Size") {
            Picker("Size", selection: Binding(get: { shared(\.size) }, set: { value in
                if let value { change("Card size \(value.label)") { $0.size = value } }
            })) {
                ForEach(Card.Size.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        InspectorRow("Shape") {
            Picker("Shape", selection: Binding(get: { shared(\.shape) }, set: { value in
                if let value { change("Card shape \(value.label.lowercased())") { $0 = $0.shaped(value) } }
            })) {
                ForEach(Card.Shape.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
        InspectorSlider(title: "Roundness", value: shared(\.roundness).map { ($0 * 100).rounded() }, range: 0...50, unit: "%") { value in
            change("Card roundness \(Int(value))%") { $0.roundness = value / 100 }
        }
    }
}
