import CoreGraphics
import Foundation
import ProjectKit

/// Where each picture goes in the 16:9 video and the 9:16 Short (docs/decisions.md, 89;
/// docs/ui/mockups/LayoutsTwoKinds.html, whose generator is the reference for every rect and rule here).
///
/// A screen is never squashed or cut: it keeps its recorded shape, fitted into the space its layout gives it.
/// The camera, cropped from a larger picture anyway, takes what's left beside the screen (Side by side) or
/// sits over it as a card. The project's inset frames the screen and nothing else: the camera alone always
/// fills the frame, and so does the screen under a card set to Full.
///
/// Sizes are in output pixels: 1920 × 1080 for the video and 1080 × 1920 for the Short at 1080p, twice that
/// at 4K. `S` is the short side.
public enum LayoutGeometry {
    // MARK: - Sizes

    /// A macOS window's corner radius in points: 16 pt, a continuous corner, on macOS 27.2 for every standard
    /// window (plain, any toolbar style, full-size content, a sidebar). AppKit reports it as the window's
    /// `_cornerRadius`, and a window's own capture fits a 16 to 16.5 pt continuous corner (measured;
    /// docs/decisions.md, 67). The screen's corners use it in the recording's own scale, so a
    /// window snapped into the area keeps its corners and the screen never cuts them.
    public static let windowCornerRadius = 16.0

    /// A card's width as a fraction of the short side: 324, 432 and 540 px at 1080p. A tall card is that wide
    /// and 3:4; a wide one is a third wider and 16:9.
    static func cardWidth(_ size: Card.Size) -> Double {
        switch size {
        case .small: 0.3
        case .medium: 0.4
        case .large: 0.5
        }
    }

    /// A Short's wide card is sized by the frame's width: 55% and 75% of it, and nil for Large, which runs
    /// edge to edge inside the inset.
    static func shortWideWidth(_ size: Card.Size) -> Double? {
        switch size {
        case .small: 0.55
        case .medium: 0.75
        case .large: nil
        }
    }

    /// How much of a card sits over a Smaller screen: two-thirds, so a third of it hangs off the screen's edge
    /// (after trying half).
    static let cardOverScreen = 2.0 / 3

    /// A card's size in a frame, given the margin it keeps from the frame's edge.
    static func cardSize(_ card: Card, isVideo: Bool, frame: CGSize, margin: Double) -> CGSize {
        let S = min(frame.width, frame.height), w = cardWidth(card.size) * S
        switch card.shape {
        case .square: return CGSize(width: w, height: w)
        case .tall: return CGSize(width: w, height: w * 4 / 3)
        case .wide:
            guard isVideo else {
                let width = shortWideWidth(card.size).map { $0 * frame.width } ?? frame.width - 2 * margin
                return CGSize(width: width, height: width * 9 / 16)
            }
            return CGSize(width: w * 4 / 3, height: w * 3 / 4)
        }
    }

    // MARK: - Choosing a layout

    /// A clip's layout, made concrete: ``Layout/automatic`` becomes the layout the take was set up with, and a
    /// layout needing a picture the take doesn't have becomes the camera or the screen alone.
    public static func resolved(_ layout: Layout, pictures: ClipPictures) -> Layout {
        let hasScreen = pictures.screen != nil, hasCamera = pictures.person != nil
        switch layout {
        case .automatic:
            guard hasScreen else { return .camera }
            guard hasCamera else { return .screen }
            return pictures.recordedLayout?.layout ?? standardLayout(forScreen: pictures.screen)
        case .sideBySide, .card:
            return !hasScreen ? .camera : !hasCamera ? .screen : layout
        case .camera:
            return hasCamera ? .camera : .screen
        case .screen:
            return hasScreen ? .screen : .camera
        }
    }

    /// A clip's layout as one shape draws it, for rendering, editor controls and still descriptions alike.
    /// Side by side needs room beside the screen; a take recorded without it shows its card instead.
    public static func resolved(_ layout: Layout, in output: OutputShape, pictures: ClipPictures) -> Layout {
        let resolved = resolved(layout, pictures: pictures)
        guard resolved == .sideBySide, let screen = pictures.screen, !Layout.hasRoom(besideScreen: screen.width / max(screen.height, 1), in: output)
        else { return resolved }
        return .card(pictures.recordedLayout?.card ?? .standard)
    }

    /// The layout a screen of this shape is most likely recorded for, when a take doesn't say: Side by side
    /// if it leaves room beside it in the video, else a card.
    static func standardLayout(forScreen screen: CGSize?) -> Layout {
        let aspect = (screen?.width ?? 16) / max(screen?.height ?? 9, 1)
        return Layout.hasRoom(besideScreen: aspect, in: .landscape) ? .sideBySide : .card(.standard)
    }

    // MARK: - The frame

    /// The camera's hairline edge, this many pixels wide in the 1080p frame, scaled with the frame and never
    /// under a pixel. Its colour follows the look's background (``TileShape/hairline(on:)``).
    public static let hairlineWidth = 1.0

    /// The hairline's width in a frame of this size, in pixels.
    static func hairline(frame size: CGSize) -> Double {
        max(1, hairlineWidth * min(size.width, size.height) / 1080)
    }

    /// The frame for a clip's layout in one shape, in the clip's look (docs/decisions.md, 61, 77 and 89).
    ///
    /// - Parameter scale: 1 for 1080p, 2 for 4K.
    public static func frame(
        for layout: Layout,
        in output: OutputShape,
        pictures: ClipPictures,
        scale: Double = 1,
        look: OutputLook = .plain,
        screenTransform: PictureTransform? = nil,
        cameraTransform: PictureTransform? = nil
    ) -> FrameLayout {
        let size = CGSize(width: Double(output.width) * scale, height: Double(output.height) * scale)
        let layout = resolved(layout, in: output, pictures: pictures)
        let placements = place(layout, in: output, size: size, pictures: pictures, look: look).map { original in
            var placement = original
            switch placement.role {
            case .screen:
                if let transform = screenTransform, let source = pictures.screen {
                    placement.crop = framedCrop(source: source, into: placement.frame.size, framing: transform.framing)
                }
            case .camera:
                if let transform = cameraTransform, let source = pictures.camera {
                    placement.crop = framedCrop(source: source, into: placement.frame.size, framing: transform.framing)
                }
            default: break
            }
            return placement
        }
        return FrameLayout(output: output, size: size, placements: placements, background: look.shownBackground)
    }

    /// The pictures of a concrete layout in a frame of `size`.
    static func place(_ layout: Layout, in output: OutputShape, size: CGSize, pictures: ClipPictures, look: OutputLook) -> [Placement] {
        let kind: Kind
        switch layout {
        case .automatic:
            return place(resolved(layout, in: output, pictures: pictures), in: output, size: size, pictures: pictures, look: look)
        case .camera: kind = .camera
        case .screen: kind = .screen
        case .sideBySide: kind = .sideBySide
        case .card(let card): kind = .card(card)
        }
        let screenAspect = pictures.screen.map { $0.width / max($0.height, 1) } ?? Double(output.width) / Double(output.height)
        let boxes = Self.boxes(kind, in: output, size: size, screen: screenAspect, look: look, screenPointHeight: pictures.screenPointHeight)
        return boxes.compactMap { box in
            switch box.role {
            case .screen:
                guard pictures.screen != nil else { return nil }
                return Placement(role: .screen, crop: CGRect(x: 0, y: 0, width: 1, height: 1), frame: box.rect, corners: box.corners)
            case .camera:
                guard let person = pictures.person else { return nil }
                let slot = box.slot ?? .fullScreen
                let isCamera = person.role == .camera
                let crop = isCamera
                    ? framedCrop(source: person.size, into: box.rect.size, framing: pictures.cameraFraming(slot))
                    : fillCrop(source: person.size, into: box.rect.size)
                return Placement(role: person.role, crop: crop, frame: box.rect, corners: box.corners, mirrored: isCamera && look.mirror,
                                 cameraSlot: isCamera ? slot : nil, borderWidth: kind == .camera ? 0 : hairline(frame: size))
            default:
                return nil
            }
        }
    }

    // MARK: - The rectangles

    /// What a layout draws.
    enum Kind: Equatable {
        case sideBySide, card(Card), camera, screen
    }

    /// One rectangle of a layout: the screen's or the camera's, with its corners.
    struct Box: Equatable {
        var role: PictureRole
        var rect: CGRect
        var corners: Corners = .square
        /// For a card, its own corner radius; tiles get theirs from the rules.
        var radius: Double?
        var slot: CameraSlot?
    }

    /// The rectangles of a layout: in pixels of a frame of `size`, from the top left, back to front.
    ///
    /// - Parameters:
    ///   - screen: The screen's width over its height.
    ///   - screenPointHeight: The recorded area's height in points. With it, the screen's corners are a
    ///     macOS window's (``windowCornerRadius``) in the recording's own scale, and so are those of the
    ///     camera's tile in Side by side, so the two match. Without it, every tile's are
    ///     four-fifths of the inset. A card keeps its own roundness either way.
    static func boxes(_ kind: Kind, in output: OutputShape, size frame: CGSize, screen r: Double, look: OutputLook,
                      screenPointHeight: Double? = nil) -> [Box] {
        let W = frame.width, H = frame.height, S = min(W, H)
        let g = (look.inset.fraction * S).rounded()
        let isVideo = output == .landscape
        var boxes: [Box]
        var isCard = false
        switch kind {
        case .camera:
            // The camera alone always fills the frame: the inset frames the screen, never this.
            boxes = [Box(role: .camera, rect: CGRect(x: 0, y: 0, width: W, height: H), slot: .fullScreen)]
        case .screen:
            boxes = [Box(role: .screen, rect: fit(r, CGRect(x: g, y: g, width: W - 2 * g, height: H - 2 * g)))]
        case .sideBySide where isVideo:
            // The screen fills the height at its recorded shape and the camera takes what's left.
            let sh = H - 2 * g, sw = r * sh, cw = max(W - 3 * g - sw, 0)
            boxes = [Box(role: .screen, rect: CGRect(x: g, y: g, width: sw, height: sh)),
                     Box(role: .camera, rect: CGRect(x: 2 * g + sw, y: g, width: cw, height: sh), slot: .split)]
        case .sideBySide:
            let sw = W - 2 * g, sh = sw / r, ch = max(H - 3 * g - sh, 0)
            boxes = [Box(role: .camera, rect: CGRect(x: g, y: g, width: sw, height: ch), slot: .split),
                     Box(role: .screen, rect: CGRect(x: g, y: 2 * g + ch, width: sw, height: sh))]
        case .card(let card):
            isCard = true
            let column = Double(card.position.column), row = Double(card.position.row)
            // A Short's screen is always full, and so is one under a card in the centre, which has no edge
            // to hang off.
            let isFull = card.screen == .full || !isVideo || card.position == .center
            // The card's margin is the project's inset, over a full screen as beside a smaller one: with none it
            // sits flush against the frame, square where it meets it.
            let m = g
            let c = cardSize(card, isVideo: isVideo, frame: frame, margin: m)
            let camera = CGRect(x: m + column / 2 * (W - 2 * m - c.width), y: m + row / 2 * (H - 2 * m - c.height), width: c.width, height: c.height)
            let s: CGRect
            if isFull {
                // Against the side away from the card, where the screen is narrower or shorter than the frame.
                s = fit(r, CGRect(x: 0, y: 0, width: W, height: H), x: 1 - column / 2, y: 1 - row / 2)
            } else if card.position.column != 1 {
                // Smaller: the screen's side edge runs down the card two-thirds of the way in, so a third of
                // the card hangs off it. With the card in a corner, the screen goes to the opposite corner.
                let over = c.width * cardOverScreen, away = 1 - row / 2
                s = card.position.column == 2
                    ? fit(r, CGRect(x: g, y: g, width: camera.minX + over - g, height: H - 2 * g), x: 0, y: away)
                    : fit(r, CGRect(x: camera.maxX - over, y: g, width: W - g - camera.maxX + over, height: H - 2 * g), x: 1, y: away)
            } else {
                // Smaller, top or bottom: its top or bottom edge runs across the card two-thirds of the way in.
                let over = c.height * cardOverScreen
                s = card.position.row == 2
                    ? fit(r, CGRect(x: g, y: g, width: W - 2 * g, height: camera.minY + over - g), x: 0.5, y: 0)
                    : fit(r, CGRect(x: g, y: camera.maxY - over, width: W - 2 * g, height: H - g - camera.maxY + over), x: 0.5, y: 1)
            }
            boxes = [Box(role: .screen, rect: s),
                     Box(role: .camera, rect: camera, radius: card.roundness * min(c.width, c.height), slot: .card)]
        }
        boxes = boxes.map { box in
            var box = box
            box.rect = rounded(box.rect)
            return box
        }
        let tileRadius = !look.rounded ? 0 : g > 0 ? 0.8 * g : 0.8 * S / 18
        // The screen's corners are a window's, scaled as the recording is.
        let screenRadius: Double? = screenPointHeight.flatMap { points in
            guard look.rounded, points > 0, let screen = boxes.first(where: { $0.role == .screen })?.rect else { return nil }
            return windowCornerRadius * screen.height / points
        }
        boxes = cornered(boxes, frame: frame, tileRadius: tileRadius, screenRadius: screenRadius, squareAtFrame: isCard)
        // Side by side's side: left and right in the video, above and below in the Short. A card has its own
        // position.
        if kind == .sideBySide, look.cameraSide == .flipped {
            boxes = boxes.map { box in
                var box = box
                if isVideo {
                    box.rect.origin.x = W - box.rect.maxX
                    box.corners = box.corners.mirroredAcross
                } else {
                    box.rect.origin.y = H - box.rect.maxY
                    box.corners = box.corners.mirroredDown
                }
                return box
            }
        }
        return boxes
    }

    /// Corners. A tile rounds by the screen's radius when there is one, so Side by side's two tiles match, or
    /// else by the tile radius, except where both edges of a corner meet the frame's edge or another tile. A
    /// card rounds by its own radius. With `squareAtFrame`, as under and for a card, a corner is square
    /// wherever either of its edges meets the frame's edge, so nothing rounds away from an edge it sits flush
    /// against.
    private static func cornered(_ boxes: [Box], frame: CGSize, tileRadius: Double, screenRadius: Double? = nil, squareAtFrame: Bool) -> [Box] {
        let tiles = boxes.filter { $0.radius == nil }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1 }
        func atFrame(_ rect: CGRect, _ edge: CGRectEdge) -> Bool {
            switch edge {
            case .minXEdge: near(rect.minX, 0)
            case .maxXEdge: near(rect.maxX, frame.width)
            case .minYEdge: near(rect.minY, 0)
            case .maxYEdge: near(rect.maxY, frame.height)
            }
        }
        func meets(_ rect: CGRect, _ edge: CGRectEdge) -> Bool {
            if atFrame(rect, edge) { return true }
            let others = tiles.map(\.rect).filter { $0 != rect }
            switch edge {
            case .minXEdge: return others.contains { near($0.maxX, rect.minX) }
            case .maxXEdge: return others.contains { near($0.minX, rect.maxX) }
            case .minYEdge: return others.contains { near($0.maxY, rect.minY) }
            case .maxYEdge: return others.contains { near($0.minY, rect.maxY) }
            }
        }
        return boxes.map { box in
            var box = box
            let radius = box.radius ?? screenRadius ?? tileRadius
            func corner(_ a: CGRectEdge, _ b: CGRectEdge) -> Double {
                if squareAtFrame || box.radius != nil { return atFrame(box.rect, a) || atFrame(box.rect, b) ? 0 : radius }
                return meets(box.rect, a) && meets(box.rect, b) ? 0 : radius
            }
            box.corners = Corners(topLeft: corner(.minYEdge, .minXEdge), topRight: corner(.minYEdge, .maxXEdge),
                                  bottomRight: corner(.maxYEdge, .maxXEdge), bottomLeft: corner(.maxYEdge, .minXEdge))
            return box
        }
    }

    // MARK: - Shading while setting up

    /// Where the camera will cover the screen: what the area shades while setting up and recording, the safe
    /// area's opposite (docs/decisions.md, 89).
    public struct Cover: Equatable, Sendable {
        /// The covered part, as fractions of the screen's width and height from its top left.
        public var rect: CGRect
        /// Its corners, as fractions of the screen's height: the camera's own where they're inside the screen,
        /// square where the screen's edge cuts it.
        public var corners: Corners
    }

    /// Where a take's camera covers the screen in one output, in a look. Nil when it sits beside the screen,
    /// as Side by side's does.
    ///
    /// - Parameter shape: The shape of the screen recorded.
    public static func cover(_ layout: TakeLayout, shape: CaptureArea.Ratio, in output: OutputShape, look: OutputLook) -> Cover? {
        guard case .card(let card) = layout else { return nil }
        let size = CGSize(width: output.width, height: output.height)
        let boxes = boxes(.card(card), in: output, size: size, screen: shape.aspect, look: look)
        guard let screen = boxes.first(where: { $0.role == .screen })?.rect,
            let camera = boxes.first(where: { $0.role == .camera }),
            screen.width > 0, screen.height > 0
        else { return nil }
        let covered = screen.intersection(camera.rect)
        guard !covered.isNull, covered.width > 0.5, covered.height > 0.5 else { return nil }
        // A corner of the covered part is the camera's own only where the camera's corner is inside the screen;
        // elsewhere the screen's edge cuts it straight.
        let tile = camera.rect, scale = 1 / screen.height
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1 }
        func corner(_ coveredPoint: CGPoint, _ cameraPoint: CGPoint, _ radius: Double) -> Double {
            near(coveredPoint, cameraPoint) ? radius * scale : 0
        }
        return Cover(
            rect: CGRect(x: (covered.minX - screen.minX) / screen.width, y: (covered.minY - screen.minY) / screen.height,
                         width: covered.width / screen.width, height: covered.height / screen.height),
            corners: Corners(
                topLeft: corner(CGPoint(x: covered.minX, y: covered.minY), CGPoint(x: tile.minX, y: tile.minY), camera.corners.topLeft),
                topRight: corner(CGPoint(x: covered.maxX, y: covered.minY), CGPoint(x: tile.maxX, y: tile.minY), camera.corners.topRight),
                bottomRight: corner(CGPoint(x: covered.maxX, y: covered.maxY), CGPoint(x: tile.maxX, y: tile.maxY), camera.corners.bottomRight),
                bottomLeft: corner(CGPoint(x: covered.minX, y: covered.maxY), CGPoint(x: tile.minX, y: tile.maxY), camera.corners.bottomLeft))
        )
    }

    // MARK: - Pictures in slots

    /// The effective static framing shown by a clip's inspector or agent tool. With no override, a camera
    /// follows its take's framing for the actual layout slot; a screen shows its whole recorded area.
    public static func transform(of picture: Edit.Picture, clip: Clip, source: Source, edit: Edit, in output: OutputShape) -> PictureTransform {
        if picture == .screen { return clip.screenTransform ?? .identity }
        if let transform = clip.cameraTransform { return transform }
        let pictures = ClipPictures(source: source, cameraFramings: edit.framings(for: source.id))
        let layout = frame(for: clip.layout, in: output, pictures: pictures, look: edit.look(of: clip))
        let slot = layout.placement(.camera)?.cameraSlot ?? .fullScreen
        return PictureTransform(edit.framings(for: source.id).framing(for: slot))
    }

    /// A B-roll or overlay picture filling a slot: a video is cropped to fill it, a still fitted inside it,
    /// so a screenshot is never cut.
    public static func overlay(size picture: CGSize, into slot: CGRect, isStill: Bool, corners: Corners = .square) -> Placement {
        if isStill {
            var placement = fit(.broll, picture, into: slot)
            placement.corners = corners
            return placement
        }
        return Placement(role: .broll, crop: fillCrop(source: picture, into: slot.size), frame: slot, corners: corners)
    }

    /// A B-roll picture filling the whole frame.
    public static func broll(size picture: CGSize, in frame: CGSize) -> Placement {
        overlay(size: picture, into: CGRect(origin: .zero, size: frame), isStill: false)
    }

    /// The part of the camera that fills a slot of this shape, framed around the framing's point and
    /// zoomed in (docs/decisions.md, 52). At zoom 1 it's as much of the camera as the slot's shape allows;
    /// zooming in shrinks it around the point. It's always kept inside the picture, so the point is as
    /// close to the slot's middle as the edges allow.
    public static func framedCrop(source: CGSize, into slot: CGSize, framing: CameraFraming) -> CGRect {
        let whole = fillCrop(source: source, into: slot)
        let width = whole.width / framing.zoom
        let height = whole.height / framing.zoom
        let x = min(max(framing.centerX - width / 2, 0), 1 - width)
        let y = min(max(framing.centerY - height / 2, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The whole source inside the slot, centered, with the background around it if the shapes differ.
    static func fit(_ role: PictureRole, _ source: CGSize, into slot: CGRect) -> Placement {
        let frame = rounded(fit(source.width / max(source.height, 1), slot))
        return Placement(role: role, crop: CGRect(x: 0, y: 0, width: 1, height: 1), frame: frame)
    }

    /// The part of a source, as fractions of its size, that fills a slot of this shape, centered.
    static func fillCrop(source: CGSize, into slot: CGSize) -> CGRect {
        let sourceAspect = source.width / max(source.height, 1)
        let slotAspect = slot.width / max(slot.height, 1)
        if sourceAspect > slotAspect {
            let width = slotAspect / sourceAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            let height = sourceAspect / slotAspect
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }

    // MARK: - Helpers

    /// The largest rectangle of shape `aspect` inside `slot`, placed by fractions of the space left over:
    /// 0.5 is centred, 0 against the left or top edge, 1 against the right or bottom.
    static func fit(_ aspect: Double, _ slot: CGRect, x: Double = 0.5, y: Double = 0.5) -> CGRect {
        var width = slot.width, height = slot.width / aspect
        if height > slot.height {
            height = slot.height
            width = slot.height * aspect
        }
        return CGRect(x: slot.minX + (slot.width - width) * x, y: slot.minY + (slot.height - height) * y, width: width, height: height)
    }

    /// A rectangle with its edges on whole pixels.
    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }
}
