import AVFoundation
import ProjectKit
import RecorderKit
import RenderKit
import SwiftUI

/// The live preview of the export, in the setup element and the Recording Panel, laid out as it will be (docs/ui.md, R6): the
/// same ``LayoutGeometry`` the render uses, with the camera's framing, and the live screen and camera in
/// their slots. Both shows the 16:9 video and the 9:16 Short side by side. With no screen, the camera fills
/// each output, as framed (docs/ui.md, R9).
struct ExportPreviewView: View {
    let recorder: RecorderModel
    /// The tiles' height. Each tile is as wide as its shape needs.
    var height: CGFloat = 200
    /// Floating: the preview drags the panel. Framing is opened from the setup strip.
    var isFloating = false
    /// The setup element's labels, the plain ratios ("16:9", "9:16"); the Recording Panel keeps "Video ·
    /// 16:9" (docs/ui.md, R10).
    var plainLabels = false
    /// Camera only keeps these native views alive but does not need the screen-preview stream.
    var screenIsVisible = true
    @State private var screenViewerActive = false
    /// Reports where the main camera slot's tile is, in the window's coordinates (top left origin): the
    /// setup element's hand-over sends it into Camera only's square (docs/ui.md, R10).
    var mainCameraFrame: ((CGRect) -> Void)? = nil

    var body: some View {
        HStack(spacing: RecordingPanelLayout.previewSpacing) {
            if let format = recorder.format {
                // Each output keeps its own camera framing; the setup strip opens the framing controls.
                ForEach(format.outputs, id: \.self) { output in
                    OutputTile(recorder: recorder, output: output, height: height, isFloating: isFloating, plainLabels: plainLabels,
                               mainCameraFrame: output == format.outputs.first ? mainCameraFrame : nil)
                }
            } else {
                // No format yet, so no layout to preview, and no slot to frame: the camera, filling a
                // Landscape-sized tile, as a full-screen camera would show it.
                let width = RecordingPanelLayout.previewTileWidth(.landscape, height: height)
                let crop = LayoutGeometry.framedCrop(source: recorder.cameraPictureSize, into: CGSize(width: width, height: height),
                                                     framing: recorder.shownFraming(.fullScreen))
                ZStack {
                    if recorder.isCameraOn {
                        CameraPreview(feed: recorder.cameraPreview, crop: crop)
                        CameraWaiting(recorder: recorder)
                    } else {
                        OffTile(title: "Camera off", systemImage: "video.slash", cornerRadius: 0)
                    }
                    if isFloating { WindowDragArea() }
                }
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.1)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A live preview of the export, laid out as it will be: \(recorder.formatLabel)")
        .onAppear { setScreenViewer(screenIsVisible) }
        .onDisappear { setScreenViewer(false) }
        .onChange(of: screenIsVisible) { _, visible in setScreenViewer(visible) }
    }

    private func setScreenViewer(_ active: Bool) {
        guard active != screenViewerActive else { return }
        screenViewerActive = active
        if active { recorder.preview.viewerAppeared() } else { recorder.preview.viewerDisappeared() }
    }
}

/// One output shape, such as "Video · 16:9".
private struct OutputTile: View {
    let recorder: RecorderModel
    let output: OutputShape
    let height: CGFloat
    let isFloating: Bool
    let plainLabels: Bool
    let mainCameraFrame: ((CGRect) -> Void)?

    var body: some View {
        let scale = height / CGFloat(output.height)
        let width = RecordingPanelLayout.previewTileWidth(output, height: height)
        // The chosen preset in the look the take will start with (docs/decisions.md, 66).
        let frame = recorder.previewFrame(in: output)
        let background = recorder.look.backgroundComponents
        let slots = frame.placements.map { placement in
            (placement, CGRect(x: placement.frame.minX * scale, y: placement.frame.minY * scale,
                               width: placement.frame.width * scale, height: placement.frame.height * scale))
        }
        ZStack(alignment: .topLeading) {
            Color(red: background.red, green: background.green, blue: background.blue)
            ForEach(slots, id: \.0.role.rawValue) { item in
                picture(item.0, slot: item.1)
                    .clipShape(Self.outline(item.0, scale: scale))
                    .offset(x: item.1.minX, y: item.1.minY)
            }
            Text(plainLabels ? output.ratioName : output.previewLabel)
                .font(.system(size: 9.5))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(height: 14)
                .background(.black.opacity(0.6), in: .rect(cornerRadius: 3))
                .padding(.leading, 5)
                .padding(.top, 5)
                .allowsHitTesting(false)
            // The picture remains a continuous window-drag target.
            if isFloating { WindowDragArea() }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// A placement's outline at the tile's scale.
    static func outline(_ placement: Placement, scale: CGFloat) -> UnevenRoundedRectangle {
        let corners = placement.outlineCorners
        return UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: corners.topLeft * scale, bottomLeading: corners.bottomLeft * scale,
            bottomTrailing: corners.bottomRight * scale, topTrailing: corners.topRight * scale), style: .continuous)
    }

    @ViewBuilder
    private func picture(_ placement: Placement, slot: CGRect) -> some View {
        switch placement.role {
        case .screen, .broll, .video:
            Cropped(crop: placement.crop, size: slot.size) {
                ZStack {
                    ScreenPreviewView(feed: recorder.preview)
                    if !recorder.preview.hasPicture {
                        // Before Screen Recording access, the layout with an empty screen, so picking a layout
                        // still shows what changes (docs/ui.md, R10; Claude's proposal, AUTHOR'S TAKE NEEDED).
                        VStack(spacing: 6) {
                            Image(systemName: "display")
                                .font(.system(size: min(18, min(slot.width, slot.height) * 0.18)))
                            if recorder.preview.needsPermission, slot.width >= 120 {
                                Text("Needs Screen Recording access")
                                    .font(.system(size: 10.5))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .help(recorder.preview.needsPermission ? "Needs Screen Recording access." : "")
                    }
                }
            }
            .frame(width: slot.width, height: slot.height)
        case .camera:
            if recorder.isCameraOn {
                CameraPreview(feed: recorder.cameraPreview, crop: placement.crop)
                    .scaleEffect(x: placement.mirrored ? -1 : 1, y: 1)
                    .frame(width: slot.width, height: slot.height)
                    .overlay { CameraWaiting(recorder: recorder) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        if let mainCameraFrame, placement.cameraSlot == recorder.formatCameraSlots.first { mainCameraFrame(frame) }
                    }
            } else {
                OffTile(title: "Camera off", systemImage: "video.slash", cornerRadius: 0)
                    .frame(width: slot.width, height: slot.height)
            }
        }
    }
}

/// A spinner in the camera's place while it's on but hasn't sent a picture yet (docs/ui.md, R10).
private struct CameraWaiting: View {
    let recorder: RecorderModel

    var body: some View {
        if recorder.phase == .settingUp, !recorder.cameraHasPicture {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Waiting for the camera’s picture")
        }
    }
}

/// Shows the part of a picture `crop` picks out (fractions of its width and height, from the top left),
/// filling `size`. The whole picture is stretched to the size that makes the crop fill the slot, then
/// clipped, so it keeps its own shape.
private struct Cropped<Content: View>: View {
    let crop: CGRect
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        let width = size.width / max(crop.width, 0.0001)
        let height = size.height / max(crop.height, 0.0001)
        content()
            .frame(width: width, height: height)
            .offset(x: -crop.minX * width, y: -crop.minY * height)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }
}
