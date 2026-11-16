import ProjectKit
import RecorderKit
import SwiftUI

/// Framing in the setup element's well, in the preview's place (docs/ui.md, R10): the whole
/// camera frame with the chosen slot's crop outlined, the rest dimmed and the framing point marked (the
/// popover's ``FramingFrame``: drag to move, pinch or scroll to zoom), with the slot tabs, the zoom slider,
/// Reset and Done. The well keeps its size: stacked where it's tall enough, as in Vertical; otherwise the
/// frame at the preview's height between a column of tabs and one of zoom, Reset and Done.
struct WellFramingView: View {
    let recorder: RecorderModel
    let slot: CameraSlot
    /// The preview's height, which the well is sized around.
    let previewHeight: Double

    var body: some View {
        let tabs = recorder.formatCameraSlots
        let layout = SetupWellLayout.framing(previewHeight: previewHeight, hasTabs: tabs.count > 1)
        let frame = frameSize(in: layout.frame)
        let picture = FramingFrame(source: recorder, slot: slot, size: frame)
            .frame(width: frame.width, height: frame.height)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
        Group {
            if layout.isStacked {
                VStack(spacing: 8) {
                    if tabs.count > 1 {
                        SlotTabs(recorder: recorder, tabs: tabs, chosen: slot, isColumn: false)
                            .frame(width: layout.frame.width)
                    }
                    picture
                    HStack(spacing: 10) {
                        ZoomSlider(recorder: recorder, slot: slot)
                        ResetButton(recorder: recorder, slot: slot, height: 24)
                            .fixedSize()
                        DoneButton(recorder: recorder, height: 24)
                            .fixedSize()
                    }
                    .frame(width: layout.frame.width, height: 26)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        if tabs.count > 1 {
                            SlotTabs(recorder: recorder, tabs: tabs, chosen: slot, isColumn: true)
                        }
                    }
                    .frame(width: SetupWellLayout.framingColumn)
                    picture
                    VStack(spacing: 8) {
                        ZoomSlider(recorder: recorder, slot: slot)
                            .frame(height: 22)
                        ResetButton(recorder: recorder, slot: slot, height: 26)
                        DoneButton(recorder: recorder, height: 26)
                    }
                    .frame(width: SetupWellLayout.framingColumn)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
    }

    /// The whole camera picture at its own shape, as large as the layout's 16:9 frame allows.
    private func frameSize(in bounds: CGSize) -> CGSize {
        let picture = recorder.cameraPictureSize
        let aspect = picture.width / max(picture.height, 1)
        let width = min(bounds.width, bounds.height * aspect)
        return CGSize(width: width.rounded(), height: (width / aspect).rounded())
    }
}

/// The slots the format uses, named by the output each is in ("16:9", "9:16"), as the preview's tiles are,
/// or by the slot when it's in both.
private struct SlotTabs: View {
    let recorder: RecorderModel
    let tabs: [CameraSlot]
    let chosen: CameraSlot
    let isColumn: Bool

    var body: some View {
        let layout = isColumn ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(tabs, id: \.self) { slot in
                let isOn = slot == chosen
                Button {
                    recorder.framingEnded(slot: chosen)
                    recorder.toggleFraming(slot)
                } label: {
                    Text(name(of: slot))
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: isColumn ? .leading : .center)
                        .frame(height: isColumn ? 26 : 22)
                        .background(isOn ? .white.opacity(0.2) : .clear, in: .rect(cornerRadius: isColumn ? 7 : 6))
                        .contentShape(.rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isOn)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(isColumn ? 0 : 2)
        .background(isColumn ? .clear : .white.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Which camera slot")
    }

    private func name(of slot: CameraSlot) -> String {
        let outputs = Set(recorder.cameraPlacements(in: slot).map(\.output))
        return outputs.count == 1 ? (outputs.first?.ratioName ?? slot.label) : slot.label
    }
}

private struct ZoomSlider: View {
    let recorder: RecorderModel
    let slot: CameraSlot

    var body: some View {
        let framing = recorder.shownFraming(slot)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: Binding(
                get: { framing.zoom },
                set: { recorder.setFraming(framing.zoomed(to: $0), slot: slot) }
            ), in: CameraFraming.zoomRange) { editing in
                if !editing { recorder.framingEnded(slot: slot) }
            }
            .controlSize(.small)
            .accessibilityLabel("Zoom")
        }
    }
}

/// Back to the face, or the middle with no face, not zoomed.
private struct ResetButton: View {
    let recorder: RecorderModel
    let slot: CameraSlot
    let height: CGFloat

    var body: some View {
        // Reset forgets the slot's framing by hand (docs/ui.md, R8), so it does nothing without one.
        let isReset = !recorder.isFramedByHand(slot)
        Button {
            recorder.resetFraming(slot: slot)
            recorder.framingEnded(slot: slot)
        } label: {
            Text("Reset")
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(isReset ? 0.45 : 1)
        .disabled(isReset)
        .help("Back to where it started")
    }
}

/// Back to the preview, which then shows the new framing.
private struct DoneButton: View {
    let recorder: RecorderModel
    let height: CGFloat

    var body: some View {
        Button {
            recorder.toggleMainFraming()
        } label: {
            Text("Done")
                .fontWeight(.semibold)
                .foregroundStyle(Color(white: 0.11))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color(white: 0.96), in: .rect(cornerRadius: 7))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Done (Esc)")
    }
}
