import AppKit
import ProjectKit
import RecorderKit
import RenderKit
import SwiftUI

/// The Layout choices (docs/decisions.md, 89; docs/ui/mockups/LayoutsTwoKinds.html, S-A to S-F), in the setup
/// element's well in place of the preview, so the element never changes size. The kind,
/// Side by side or Card, is at the top; under it a picture of what the take will be, with the screen it
/// records, and the kind's settings beside it. Side by side sets the camera's share, which is the shape of the
/// screen recorded, and the camera's side. Card sets its position, size, shape, how the screen sits and its
/// roundness, the same five as the editor's Card section, so the area shades exactly what the card will cover
/// and a take starts as set up. The Layout card again, × or Esc returns to the preview.
struct LayoutMenuContent: View {
    let recorder: RecorderModel
    /// The preview's height, which the well is sized around.
    let previewHeight: Double
    let close: () -> Void

    var body: some View {
        if let format = recorder.format {
            LayoutChoices(format: format, look: recorder.look, screenPointHeight: recorder.screenPointHeight(for: format.captureRatio),
                          previewHeight: previewHeight,
                          chooseKind: { isCard in if isCard { recorder.chooseCard() } else { recorder.chooseSideBySide() } },
                          choose: { recorder.choose($0) },
                          chooseSide: { recorder.chooseSide($0) },
                          close: close)
        }
    }
}

/// The choices themselves, for a format: what ``LayoutMenuContent`` shows for the recorder.
struct LayoutChoices: View {
    let format: VideoFormat
    let look: OutputLook
    var screenPointHeight: Double?
    let previewHeight: Double
    /// Switches to Card (true) or Side by side, each as it was last set up.
    let chooseKind: (Bool) -> Void
    let choose: (TakeLayout) -> Void
    let chooseSide: (OutputLook.CameraSide) -> Void
    let close: () -> Void

    var body: some View {
        let destination = format.destination
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if TakeLayout.offersCard(destination) {
                    HUDSegmented(items: [(false, "Side by side"), (true, "Card")], selection: format.layout.isCard, pick: chooseKind)
                        .frame(width: 190)
                        // A label here would replace each segment's own name, so the group is only named.
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Layout")
                } else {
                    Text("Side by side").font(.system(size: 12.5, weight: .semibold))
                }
                Text(format.outputTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 12)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.1), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
            .frame(height: SetupWellLayout.choicesTitleRow)

            HStack(spacing: SetupWellLayout.choicesGap) {
                VStack(spacing: 6) {
                    TakePicture(layout: format.layout, destination: destination, look: look, screenPointHeight: screenPointHeight,
                                height: SetupWellLayout.choicePictureHeight(previewHeight: previewHeight, destination: destination))
                    ScreenRatioLabel(ratio: format.captureRatio)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .help("The shape of the screen area you record")
                }
                VStack(spacing: 6) {
                    if let card = format.layout.card {
                        CardSettings(card: card, destination: destination) { choose(.card($0)) }
                    } else if case .sideBySide(let shape) = format.layout {
                        SideBySideSettings(shape: shape, side: look.cameraSide, destination: destination, choose: choose, chooseSide: chooseSide)
                    }
                }
                .frame(width: SetupWellLayout.choicesControlsWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: previewHeight)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Side by side's settings: the camera's share, which sets the screen recorded, and its side.
private struct SideBySideSettings: View {
    let shape: CaptureArea.Ratio
    let side: OutputLook.CameraSide
    let destination: VideoFormat.Destination
    let choose: (TakeLayout) -> Void
    let chooseSide: (OutputLook.CameraSide) -> Void

    var body: some View {
        // Both's one recording gives each output a different share, so its choices are named by the screen.
        ChoiceRow(destination == .both ? "Screen" : "Camera share") {
            HUDSegmented(items: TakeLayout.shares(for: destination).map { ($0, TakeLayout.shareLabel($0, for: destination)) }, selection: shape) {
                choose(.sideBySide($0))
            }
            .help(destination == .both ? "The shape of the screen recorded. It can’t change afterwards."
                : "How much of the \(destination == .vertical ? "Short’s height" : "video’s width") the camera gets. It can’t change afterwards.")
        }
        // One side for the take, the same in both shapes (docs/decisions.md, 77), named as the format's first
        // shape draws it.
        let output: OutputShape = destination == .vertical ? .vertical : .landscape
        ChoiceRow("Camera") {
            // Left then Right, Above then Below, as they sit in the frame.
            let sides: [OutputLook.CameraSide] = output == .landscape ? [.flipped, .standard] : [.standard, .flipped]
            HUDSegmented(items: sides.map { ($0, $0.label(in: output)) }, selection: side, pick: chooseSide)
        }
    }
}

/// A card's settings, the editor's five (docs/decisions.md, 89). A Short has no Screen row: its screen is
/// always full.
private struct CardSettings: View {
    let card: Card
    let destination: VideoFormat.Destination
    let set: (Card) -> Void

    private func change(_ body: (inout Card) -> Void) {
        var changed = card
        body(&changed)
        set(changed)
    }

    var body: some View {
        ChoiceRow("Position") {
            CardPositionGrid(position: card.position, tint: HUDSegmented<Bool>.blue) { place in change { $0.position = place } }
        }
        ChoiceRow("Size") {
            HUDSegmented(items: Card.Size.allCases.map { ($0, $0.label) }, selection: card.size) { size in change { $0.size = size } }
        }
        ChoiceRow("Shape") {
            HUDSegmented(items: Card.Shape.allCases.map { ($0, $0.label) }, selection: card.shape) { shape in change { $0 = $0.shaped(shape) } }
        }
        if destination != .vertical {
            ChoiceRow("Screen") {
                HUDSegmented(items: Card.Screen.allCases.map { ($0, $0.label) }, selection: card.screen) { screen in change { $0.screen = screen } }
                    .help("Smaller shrinks the screen so the card hangs off its edge.")
            }
        }
        ChoiceRow("Roundness") {
            Slider(value: Binding(get: { card.roundness }, set: { value in change { $0.roundness = value } }), in: Card.roundnessRange)
                .controlSize(.small)
                .tint(HUDSegmented<Bool>.blue)
                .accessibilityLabel("Roundness")
            Text("\(Int((card.roundness * 100).rounded()))%")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// A setting in the choices: its name on the left, its control filling the rest.
private struct ChoiceRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.control = control
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 84, alignment: .leading)
            control()
        }
    }
}

/// A segmented control in the HUD's own style: one of a few choices, the chosen one lit. It works like radio
/// buttons without looking like them.
struct HUDSegmented<Value: Hashable>: View {
    /// The HUD's blue, as the area's frame and the choices' marks use it.
    static var blue: Color { Color(red: 0.04, green: 0.52, blue: 1) }

    let items: [(value: Value, label: String)]
    let selection: Value
    let pick: (Value) -> Void

    init(items: [(Value, String)], selection: Value, pick: @escaping (Value) -> Void) {
        self.items = items.map { (value: $0.0, label: $0.1) }
        self.selection = selection
        self.pick = pick
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                let isOn = item.value == selection
                Button { pick(item.value) } label: {
                    Text(item.label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(isOn ? 1 : 0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(.white.opacity(isOn ? 0.22 : 0), in: .rect(cornerRadius: 5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 7))
    }
}

/// A take's layout drawn as what it makes, in the current look (docs/decisions.md, 89): each output the format
/// includes, the screen as a little white window with a title bar and lines, the camera as a dark tile with
/// `person.fill`. No colour coding.
struct TakePicture: View {
    let layout: TakeLayout
    let destination: VideoFormat.Destination
    let look: OutputLook
    /// The height in points of the area the layout would record, which sets the screen's corners
    /// (docs/decisions.md, 67).
    var screenPointHeight: Double?
    let height: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(VideoFormat(destination: destination, layout: layout).outputs, id: \.self) { output in
                LayoutMiniature(layout: layout.layout, output: output,
                                pictures: Self.pictures(layout, destination: destination, screenPointHeight: screenPointHeight), look: look, height: height)
            }
        }
        .accessibilityHidden(true)
    }

    /// A take recorded for the layout: its screen is the shape the layout records.
    static func pictures(_ layout: TakeLayout, destination: VideoFormat.Destination, screenPointHeight: Double? = nil) -> ClipPictures {
        ClipPictures(screen: CGSize(width: 1000 * layout.captureRatio(for: destination).aspect, height: 1000), camera: CGSize(width: 1920, height: 1080),
                     recordedLayout: layout, screenPointHeight: screenPointHeight)
    }
}

#if DEBUG
/// The choices in a well like the setup element's, with their own state, so every setting can be tried.
private struct LayoutChoicesPreview: View {
    @State var format: VideoFormat
    @State private var look = OutputLook.plain
    @State private var memory = SetupMemory()
    var previewHeight = 200.0

    var body: some View {
        LayoutChoices(format: format, look: look, previewHeight: previewHeight,
                      chooseKind: { isCard in pick(isCard ? .card(memory.card(for: format.destination)) : memory.sideBySide(for: format.destination)) },
                      choose: pick, chooseSide: { look.cameraSide = $0 }, close: {})
            .frame(width: 640)
            .padding(.vertical, 12)
            .background(Color(white: 0.06), in: .rect(cornerRadius: 11))
            .padding(8)
            .background(Color(white: 0.16))
    }

    private func pick(_ layout: TakeLayout) {
        memory.use(layout, for: format.destination)
        format = VideoFormat(destination: format.destination, layout: layout)
    }
}

#Preview("Side by side") { LayoutChoicesPreview(format: VideoFormat(destination: .landscape, layout: .sideBySide(.thirtyTwoByTwentySeven))) }
#Preview("Card, smaller") { LayoutChoicesPreview(format: VideoFormat(destination: .landscape, layout: .card(.standard))) }
#Preview("Card, full, bubble") { LayoutChoicesPreview(format: VideoFormat(destination: .landscape, layout: .card(.bubble))) }
#Preview("Both") { LayoutChoicesPreview(format: VideoFormat(destination: .both)) }
#Preview("Vertical card") { LayoutChoicesPreview(format: VideoFormat(destination: .vertical, layout: .card(.bubble)), previewHeight: 400) }
#Preview("Vertical side by side") { LayoutChoicesPreview(format: VideoFormat(destination: .vertical, layout: .sideBySide(.twentySevenByThirtyTwo)), previewHeight: 400) }
#endif
