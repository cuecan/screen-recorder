import AppKit
import AVFoundation
import CoreImage
import ProjectKit
import SwiftUI

/// The preview on top of the editor: one shape at a time (docs/decisions.md, 77). A take made for both has a
/// toggle under it, where the shape's label would be, flipping between the 16:9 video and the 9:16 Short.
/// It's the only control in the editor that knows about shape.
struct PreviewPanels: View {
    let model: EditorModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let spacing = 16.0
            let labels = model.outputs.count > 1 ? 30.0 : 22.0
            let panels = model.panels.isEmpty ? [(model.shape, Self.placeholderRect(model.shape))] : model.panels
            let aspects = panels.map { $0.1.width / max($0.1.height, 1) }
            let available = CGSize(width: geometry.size.width - spacing * Double(max(0, panels.count - 1)), height: geometry.size.height - labels)
            let height = max(40, min(available.height, available.width / max(aspects.reduce(0, +), 0.1)))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(panels.enumerated()), id: \.offset) { index, panel in
                    VStack(spacing: 6) {
                        ZStack {
                            if model.timeline != nil {
                                PanelPlayer(player: model.player, hold: model.frameHold,
                                            displayReadyItem: model.displayReadyItem,
                                            poster: model.poster, panel: panel.1, composition: model.renderSize)
                            } else {
                                Rectangle().fill(.black.opacity(0.85))
                            }
                        }
                        .frame(width: height * aspects[index], height: height)
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                        if model.outputs.count > 1 {
                            ShapeToggle(model: model)
                        } else {
                            Text(panel.0.previewLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: height * displayScale, initial: true) { _, pixels in model.previewHeightChanged(toPixels: pixels) }
        }
    }

    private static func placeholderRect(_ output: OutputShape) -> CGRect {
        CGRect(x: 0, y: 0, width: output.width, height: output.height)
    }
}

/// The toggle between the 16:9 video and the 9:16 Short, for a take made for both. Flipping it redraws the
/// same cut and the same settings for the other shape.
private struct ShapeToggle: View {
    let model: EditorModel

    var body: some View {
        Picker("Shape shown", selection: Binding(get: { model.shape }, set: { model.show($0) })) {
            ForEach(model.outputs, id: \.self) { shape in
                Label(shape.previewLabel, systemImage: shape == .landscape ? "rectangle" : "rectangle.portrait").tag(shape)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .fixedSize()
        .help("Show the video or the Short.")
    }
}

/// One output's part of the preview composition: a player layer as big as the whole composition, moved so
/// only this output shows.
private struct PanelPlayer: NSViewRepresentable {
    let player: AVPlayer
    let hold: FrameHold
    let displayReadyItem: AVPlayerItem?
    let poster: NSImage?
    let panel: CGRect
    let composition: CGSize

    func makeNSView(context: Context) -> PanelPlayerView { PanelPlayerView() }

    func updateNSView(_ view: PanelPlayerView, context: Context) {
        view.hold = hold
        view.player = player
        view.displayReadyItem = displayReadyItem
        view.show(poster)
        view.panel = panel
        view.composition = composition
        view.needsLayout = true
    }

    static func dismantleNSView(_ view: PanelPlayerView, coordinator: ()) {
        view.player = nil
    }
}

final class PanelPlayerView: NSView {
    let playerLayer = AVPlayerLayer()
    let posterLayer = CALayer()
    var panel = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    var composition = CGSize(width: 1920, height: 1080)
    private var readiness: NSKeyValueObservation?
    private var itemChange: NSKeyValueObservation?
    private var shownPoster: NSImage?
    var displayReadyItem: AVPlayerItem? { didSet { updateVisibility() } }
    private var changingItem = false
    /// The frame the model took from the playing item just before a swap, for when the layer has none.
    var hold: FrameHold?
    private static let frameContext = CIContext()

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard newValue !== playerLayer.player else { return }
            playerLayer.player = newValue
            // Each edit swaps in a new player item, which has no picture until it decodes one. Hold the
            // frame on screen until then, so the preview never flashes black.
            itemChange = newValue?.observe(\.currentItem, options: [.prior, .new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if change.isPrior { self.holdDisplayedFrame() }
                    self.changingItem = change.isPrior
                    self.updateVisibility()
                }
            }
        }
    }

    /// The model's poster, when it changes. A held frame stays until a newer poster arrives.
    func show(_ poster: NSImage?) {
        guard poster !== shownPoster else { return }
        shownPoster = poster
        var imageBounds = CGRect(origin: .zero, size: poster?.size ?? .zero)
        posterLayer.contents = poster?.cgImage(forProposedRect: &imageBounds, context: nil, hints: nil)
    }

    /// Copies the frame the player layer shows into the poster layer. While playing the layer doesn't hand
    /// out its frame, so the frame the model took from the item's video output stands in.
    private func holdDisplayedFrame() {
        // While the player is hidden, what's on screen is the poster: an audio-only swap keeps it.
        if playerLayer.isHidden, posterLayer.contents != nil { return }
        var frame: CGImage?
        if playerLayer.isReadyForDisplay, let buffer = playerLayer.displayedPixelBuffer() {
            let image = CIImage(cvPixelBuffer: buffer)
            frame = Self.frameContext.createCGImage(image, from: image.extent)
        }
        guard let frame = frame ?? hold?.image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        posterLayer.contents = frame
        CATransaction.commit()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resize
        posterLayer.contentsGravity = .resize
        layer?.addSublayer(posterLayer)
        layer?.addSublayer(playerLayer)
        readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateVisibility()
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    private func updateVisibility() {
        let usesPlayer = !changingItem && displayReadyItem != nil
            && displayReadyItem === playerLayer.player?.currentItem
            && playerLayer.isReadyForDisplay
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.isHidden = !usesPlayer
        posterLayer.isHidden = usesPlayer
        CATransaction.commit()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        // SwiftUI and AppKit can round the fitted width and height independently at a backing-pixel
        // boundary. Scaling from height alone left a sliver of this view's black backing on the right.
        // Map each panel edge to the actual view bounds, including fractional display sizes.
        let scaleX = bounds.width / max(panel.width, 1)
        let scaleY = bounds.height / max(panel.height, 1)
        let frame = CGRect(x: -panel.minX * scaleX, y: -panel.minY * scaleY,
                           width: composition.width * scaleX, height: composition.height * scaleY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = frame
        posterLayer.frame = frame
        CATransaction.commit()
    }
}
