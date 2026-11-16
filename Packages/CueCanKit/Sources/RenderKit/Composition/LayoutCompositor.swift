import AVFoundation
import CoreImage
import Foundation
import ProjectKit

/// The custom video compositor: draws each output panel's background and pictures where
/// ``LayoutInstruction`` places them, with rounded tiles, the camera bubble's outline and its border, with
/// Core Image (docs/decisions.md, 13 and 61), the base look and its add-ons behind and under them (81), then the
/// captions over them (80).
///
/// AVFoundation makes it and calls it from its own threads, so all its state is behind one serial queue.
final class LayoutCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    /// Sources can arrive in any format Core Image reads, so footage that doesn't decode straight to BGRA,
    /// such as 10-bit HEVC, still plays.
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
            kCVPixelFormatType_64RGBAHalf,
        ],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = LayoutCompositor.pixelFormat

    /// 10-bit footage, such as HEVC from a phone or another screen recorder, arrives only if the compositor says it
    /// takes it; otherwise AVFoundation hands over no frames at all.
    let supportsWideColorSourceFrames = true
    let supportsHDRSourceFrames = true

    // Core Image builds an Objective-C filter graph for every frame. Drain those temporary objects
    // after each request instead of inheriting the worker thread's potentially long-lived pool.
    private let queue = DispatchQueue(label: "CueCan.LayoutCompositor", autoreleaseFrequency: .workItem)
    // AVFoundation creates a compositor for each replacement item. Recreating CIContext also recreates
    // command queues and compiled-kernel caches, eventually exhausting GPU variants during repeated
    // preview rebuilds. CIContext is thread-safe; keep each compositor's mutable state on its own queue.
    private static let sharedContext = CIContext(options: [.cacheIntermediates: false])
    private var renderContext: AVVideoCompositionRenderContext?
    private var cancelled = false
    private var masks: [String: CIImage] = [:]
    private let captionDrawer = CaptionDrawer()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync { renderContext = newRenderContext }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            if cancelled {
                request.finishCancelledRequest()
                return
            }
            guard let renderContext, let buffer = renderContext.newPixelBuffer() else {
                request.finish(with: RenderError.exportFailed("The compositor had nowhere to draw."))
                return
            }
            guard let instruction = request.videoCompositionInstruction as? LayoutInstruction else {
                request.finish(with: RenderError.exportFailed("The compositor was given a stretch it doesn't know how to draw."))
                return
            }
            let image = compose(instruction, request: request)
            Self.sharedContext.render(image, to: buffer, bounds: CGRect(origin: .zero, size: instruction.renderSize), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            request.finish(withComposedVideoFrame: buffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        queue.sync { cancelled = true }
        queue.async { [self] in cancelled = false }
    }

    private func compose(_ instruction: LayoutInstruction, request: AVAsynchronousVideoCompositionRequest) -> CIImage {
        let size = instruction.renderSize
        let bounds = CGRect(origin: .zero, size: size)
        var image = CIImage(color: .black).cropped(to: bounds)

        for panel in instruction.panels {
            let rect = Self.flipped(panel.rect, in: size)
            let color = CIColor(red: panel.background.red, green: panel.background.green, blue: panel.background.blue)
            image = CIImage(color: color).cropped(to: rect).composited(over: image)
            func picture(of item: LayoutInstruction.Item) -> CIImage? {
                switch item {
                case .track(_, let trackID): request.sourceFrame(byTrackID: trackID).map { CIImage(cvPixelBuffer: $0) }
                case .image(_, let key): instruction.stills[key]
                }
            }
            let time = request.compositionTime.seconds
            let base = panel.backdrop, addOns = panel.addOns
            // Dark or light is read from what's really behind the tiles, so add-ons work on a plain colour too.
            let dark = 0.2126 * panel.background.red + 0.7152 * panel.background.green + 0.0722 * panel.background.blue <= 0.5
            let short = min(rect.width, rect.height)
            // Every picture placed first: the bloom is made from them before any is drawn.
            var tiles: [(picture: CIImage, placement: Placement, destination: CGRect)] = []
            for item in panel.items {
                guard let source = picture(of: item) else { continue }
                var placement = item.placement
                placement.frame = placement.frame.offsetBy(dx: panel.rect.minX, dy: panel.rect.minY)
                tiles.append((Self.place(source, placement, in: size), placement, Self.flipped(placement.frame, in: size)))
            }
            switch base {
            case .daylight:
                image = Self.daylightBand(at: time, filling: rect).composited(over: image)
            case .aura, .glow:
                // The bloom comes from the cameras, whose rooms and skin have more colour than most screens:
                // a white screen only blooms grey. With no camera, from whatever there is.
                let cameras = tiles.filter { $0.placement.cameraSlot != nil }
                image = Self.bloom(of: (cameras.isEmpty ? tiles : cameras).map(\.picture), on: color, dark: dark, at: time, filling: rect).composited(over: image)
            case .plain, .paper, .ink:
                break
            }
            for (picture, placement, destination) in tiles {
                let isFramed = destination.width < rect.width - 1 || destination.height < rect.height - 1
                if isFramed, addOns.contains(.shadows) {
                    let shade = TileShadow.color(dark: dark)
                    for layer in TileShadow.layers(dark: dark, moving: base == .daylight, at: time) {
                        let shadow = shadowMask(for: placement, size: destination.size, blur: layer.blur * short)
                            .transformed(by: CGAffineTransform(translationX: destination.minX + layer.x * short, y: destination.minY - layer.y * short))
                        // The mask is scaled by the layer's opacity, so the frame stays opaque under the shadow.
                        let strength = shadow.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector": CIVector(x: layer.opacity, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: layer.opacity, z: 0, w: 0),
                            "inputBVector": CIVector(x: 0, y: 0, z: layer.opacity, w: 0),
                        ])
                        let tint = CIImage(color: CIColor(red: shade.red, green: shade.green, blue: shade.blue)).cropped(to: shadow.extent)
                        image = tint.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: strength])
                            .cropped(to: bounds)
                    }
                }
                if !placement.outlineCorners.isSquare {
                    let mask = roundedMask(for: placement, size: destination.size)
                        .transformed(by: CGAffineTransform(translationX: destination.minX, y: destination.minY))
                    image = picture.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
                } else {
                    image = picture.composited(over: image)
                }
                if isFramed, addOns.contains(.litEdge) {
                    var edged = placement
                    edged.borderWidth = max(placement.borderWidth, (short / 720).rounded(), 1)
                    image = border(for: edged, at: destination, color: LitEdge.hairline(dark: dark)).composited(over: image)
                    // The top line: the same band in white, fading out down the tile.
                    let line = border(for: edged, at: destination, color: (1, LitEdge.highlight(dark: dark)))
                    let fade = CIFilter(name: "CILinearGradient", parameters: [
                        "inputPoint0": CIVector(x: 0, y: destination.maxY), "inputColor0": CIColor.white,
                        "inputPoint1": CIVector(x: 0, y: destination.maxY - destination.height * LitEdge.reach), "inputColor1": CIColor.black,
                    ])?.outputImage?.cropped(to: destination)
                    if let fade {
                        image = line.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: fade])
                            .cropped(to: destination).composited(over: image)
                    }
                } else if placement.borderWidth > 0 {
                    image = border(for: placement, at: destination, color: TileShape.hairline(on: panel.background)).composited(over: image)
                }
            }
            if let captions = panel.captions,
               let overlay = captionDrawer.overlay(captions, at: request.compositionTime.seconds,
                                                   frameDuration: renderContext?.videoComposition.frameDuration.seconds ?? 0,
                                                   panel: panel.rect, frame: size) {
                image = overlay.composited(over: image)
            }
        }
        return image.cropped(to: bounds)
    }

    /// The source picture cropped and scaled into its frame, in Core Image's coordinates (origin bottom left).
    static func place(_ source: CIImage, _ placement: Placement, in size: CGSize) -> CIImage {
        let extent = source.extent
        let crop = CGRect(
            x: extent.minX + placement.crop.minX * extent.width,
            y: extent.minY + (1 - placement.crop.maxY) * extent.height,
            width: placement.crop.width * extent.width,
            height: placement.crop.height * extent.height
        )
        let destination = flipped(placement.frame, in: size)
        // Mirror flips the picture left to right within its crop.
        let mirror = placement.mirrored
            ? CGAffineTransform(translationX: -crop.midX, y: 0).concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: crop.midX, y: 0))
            : .identity
        let transform = mirror.concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .concatenating(CGAffineTransform(scaleX: destination.width / max(crop.width, 1), y: destination.height / max(crop.height, 1)))
            .concatenating(CGAffineTransform(translationX: destination.minX, y: destination.minY))
        return source.cropped(to: crop).clampedToExtent().transformed(by: transform).cropped(to: destination)
    }

    /// Daylight's warm band at a moment: an upright bar of warm light, worked out small, blurred and scaled up
    /// to `rect` (``DaylightBand``). In Core Image's coordinates.
    static func daylightBand(at time: Double, filling rect: CGRect) -> CIImage {
        let small = Bloom.workingSize(for: rect.size)
        guard small.width > 0, small.height > 0, rect.width > 0, rect.height > 0 else { return CIImage.empty() }
        let working = CGRect(origin: .zero, size: small)
        let c = DaylightBand.color
        let bar = CGRect(x: (DaylightBand.center(at: time) - DaylightBand.width / 2) * small.width, y: -small.height,
                         width: DaylightBand.width * small.width, height: small.height * 3)
        return CIImage(color: CIColor(red: c.red, green: c.green, blue: c.blue, alpha: DaylightBand.opacity)).cropped(to: bar)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: DaylightBand.blur * small.width])
            .cropped(to: working)
            .transformed(by: CGAffineTransform(scaleX: rect.width / small.width, y: rect.height / small.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    /// Aura's and Glow's bloom at a moment: the placed pictures on the background's colour, shrunk, blurred
    /// until only their colours are left, then washed with the background so it stays pale on white and
    /// doesn't flood on near-black (``Bloom``). In Core Image's coordinates.
    static func bloom(of pictures: [CIImage], on background: CIColor, dark: Bool, at time: Double, filling rect: CGRect) -> CIImage {
        let small = Bloom.workingSize(for: rect.size)
        guard small.width > 0, small.height > 0, rect.width > 0, rect.height > 0 else { return CIImage.empty() }
        var flat = CIImage(color: background).cropped(to: rect)
        for picture in pictures { flat = picture.cropped(to: rect).composited(over: flat) }
        let working = CGRect(origin: .zero, size: small)
        // Blurred small and scaled up: the same softness for a fraction of the work, at any export size.
        let blurred = flat
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: small.width / rect.width, y: small.height / rect.height), highQualityDownsample: true)
            .cropped(to: working).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Bloom.blurFraction * min(small.width, small.height)])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: Bloom.saturation])
            .cropped(to: working)
        let wash = CIImage(color: CIColor(red: background.red, green: background.green, blue: background.blue, alpha: Bloom.wash(dark: dark, at: time)))
            .cropped(to: working)
        return wash.composited(over: blurred)
            .transformed(by: CGAffineTransform(scaleX: rect.width / small.width, y: rect.height / small.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    /// A top-left rectangle in Core Image's bottom-left coordinates.
    static func flipped(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A white mask of a tile's outline on clear, its size: continuous corners, as macOS draws them
    /// (``TileShape``).
    private func roundedMask(for placement: Placement, size: CGSize) -> CIImage {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let key = "\(width)x\(height)r\(Self.cornerKey(placement))"
        if let mask = masks[key] { return mask }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let mask = TileShape.mask(for: placement, size: size).map { CIImage(cgImage: $0) } ?? CIImage(color: .white).cropped(to: extent)
        masks[key] = mask
        return mask
    }

    /// A tile's hairline edge just inside its outline, in a colour that reads on what's behind it,
    /// placed at `destination` (bottom-left coordinates). Cached by shape, size and colour.
    private func border(for placement: Placement, at destination: CGRect, color: (gray: Double, alpha: Double)) -> CIImage {
        let width = placement.borderWidth
        let key = "edge \(Int(destination.width.rounded()))x\(Int(destination.height.rounded()))r\(Self.cornerKey(placement))w\(width)c\(color.gray)a\(color.alpha)"
        let band: CIImage
        if let cached = masks[key] {
            band = cached
        } else {
            let mask = TileShape.borderMask(for: placement, size: destination.size, width: width).map { CIImage(cgImage: $0) } ?? CIImage.empty()
            band = CIImage(color: CIColor(red: color.gray, green: color.gray, blue: color.gray, alpha: color.alpha)).cropped(to: mask.extent)
                .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
            masks[key] = band
        }
        return band.transformed(by: CGAffineTransform(translationX: destination.minX, y: destination.minY))
    }

    /// A tile's outline blurred into a shadow: white where the shadow is darkest, on black, with the tile's
    /// own origin at zero and room around it for the blur. Drawn once for each shape, size and softness.
    private func shadowMask(for placement: Placement, size: CGSize, blur: Double) -> CIImage {
        let radius = max(blur, 0.5)
        let key = "shadow \(Int(size.width.rounded()))x\(Int(size.height.rounded()))r\(Self.cornerKey(placement))b\(Int((radius * 10).rounded()))"
        if let mask = masks[key] { return mask }
        let room = (radius * 3).rounded(.up)
        let extent = CGRect(origin: .zero, size: size).insetBy(dx: -room, dy: -room).integral
        let soft = roundedMask(for: placement, size: size)
            .composited(over: CIImage(color: .black).cropped(to: extent)).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        // Kept as pixels, so the blur isn't worked out again on every frame.
        let mask = Self.sharedContext.createCGImage(soft, from: extent).map {
            CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        } ?? soft
        masks[key] = mask
        return mask
    }

    /// A placement's corners as a cache key.
    private static func cornerKey(_ placement: Placement) -> String {
        placement.outlineCorners.all.map { String(Int($0.rounded())) }.joined(separator: ",")
    }
}
