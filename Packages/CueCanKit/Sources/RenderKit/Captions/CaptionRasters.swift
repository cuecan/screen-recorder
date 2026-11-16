import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ProjectKit

/// One word drawn once, with its outline and shadow baked in, on clear: a frame only moves, scales and
/// composites it (docs/decisions.md, 80).
struct RasterWord {
    var picture: CIImage
    /// The text's own width, at the size it was drawn.
    var advance: Double
    /// From the picture's left edge to where the text starts, and from its bottom edge to the baseline.
    var textLeft: Double
    var baseline: Double
    var capHeight: Double
}

/// The letters of a style at a size: what wrapping needs, without drawing.
struct CaptionFontMetrics {
    var capHeight: Double
}

/// Draws words and keeps them. Used from the compositor's queue only.
final class CaptionRasters {
    private struct Key: Hashable {
        var text: String
        var font: String
        /// In quarter pixels, so sizes that round alike share a picture.
        var size: Int
        var fill: String
        var stroke: String
        var shadow: String
    }

    private var rasters: [Key: RasterWord] = [:]
    private var fonts: [String: CTFont] = [:]
    /// How many words have been drawn, for the tests and the performance check.
    private(set) var drawn = 0
    /// More words than this and the cache starts again: a long edit's words aren't all kept.
    private let limit = 600

    /// A font by PostScript name at a size, or the system font's heaviest weight when macOS has no such font.
    func font(_ name: String, size: Double) -> CTFont {
        let key = "\(name)@\(size)"
        if let font = fonts[key] { return font }
        var font = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
        if (CTFontCopyPostScriptName(font) as String) != name {
            let traits = [kCTFontWeightTrait: 0.62] as CFDictionary
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
            font = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil).map { CTFontCreateCopyWithAttributes($0, CGFloat(size), nil, descriptor) } ?? font
        }
        if fonts.count > 64 { fonts.removeAll() }
        fonts[key] = font
        return font
    }

    /// A word's width at a size, without drawing it.
    func advance(_ text: String, style: CaptionStyle, size: Double) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font(style.lettering.font, size: size)]))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    func metrics(style: CaptionStyle, size: Double) -> CaptionFontMetrics {
        CaptionFontMetrics(capHeight: Double(CTFontGetCapHeight(font(style.lettering.font, size: size))))
    }

    /// A word drawn at `size` pixels in a fill colour, with the style's outline and shadow.
    func raster(_ text: String, style: CaptionStyle, size: Double, fill: String) -> RasterWord? {
        let lettering = style.lettering
        let stroke = lettering.stroke.map { "\($0.width)/\($0.color)" } ?? ""
        let shadow = lettering.shadow.map { "\($0.color)/\($0.opacity)/\($0.blur)/\($0.drop)" } ?? ""
        let key = Key(text: text, font: lettering.font, size: Int((size * 4).rounded()), fill: fill, stroke: stroke, shadow: shadow)
        if let raster = rasters[key] { return raster }
        guard let raster = draw(text, lettering: lettering, size: Double(key.size) / 4, fill: fill) else { return nil }
        if rasters.count >= limit { rasters.removeAll() }
        rasters[key] = raster
        drawn += 1
        return raster
    }

    private func draw(_ text: String, lettering: CaptionStyle.Lettering, size: Double, fill: String) -> RasterWord? {
        let ctFont = font(lettering.font, size: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: ctFont, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let advance = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let strokeWidth = (lettering.stroke?.width ?? 0) * size
        let blur = (lettering.shadow?.blur ?? 0) * size
        let drop = (lettering.shadow?.drop ?? 0) * size
        let padding = (strokeWidth + blur * 1.5 + drop + 2).rounded(.up)
        let width = Int((advance + 2 * padding).rounded(.up))
        let height = Int((Double(ascent + descent) + 2 * padding).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let baseline = padding + Double(descent)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setAllowsFontSmoothing(false)
        func shadowOn() {
            guard let shadow = lettering.shadow else { return }
            context.setShadow(offset: CGSize(width: 0, height: -drop), blur: CGFloat(blur), color: Self.color(shadow.color, alpha: shadow.opacity, space: space))
        }
        // The outline first, twice its width so half shows outside the letters, with the shadow under it;
        // then the fill over it, with no shadow of its own.
        if let stroke = lettering.stroke, strokeWidth > 0 {
            shadowOn()
            context.textPosition = CGPoint(x: padding, y: baseline)
            context.setTextDrawingMode(.fillStroke)
            context.setLineWidth(CGFloat(strokeWidth * 2))
            context.setStrokeColor(Self.color(stroke.color, alpha: 1, space: space))
            context.setFillColor(Self.color(stroke.color, alpha: 1, space: space))
            CTLineDraw(line, context)
            context.setShadow(offset: .zero, blur: 0, color: nil)
        } else {
            shadowOn()
        }
        // Drawing a line moves the text position along it, so the fill goes back to where the outline started.
        context.textPosition = CGPoint(x: padding, y: baseline)
        context.setTextDrawingMode(.fill)
        context.setFillColor(Self.color(fill, alpha: 1, space: space))
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        return RasterWord(picture: CIImage(cgImage: image), advance: advance, textLeft: padding, baseline: baseline,
                          capHeight: Double(CTFontGetCapHeight(ctFont)))
    }

    static func color(_ hex: String, alpha: Double, space: CGColorSpace) -> CGColor {
        let (red, green, blue) = components(hex)
        return CGColor(colorSpace: space, components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)]) ?? CGColor(gray: 0, alpha: alpha)
    }

    static func components(_ hex: String) -> (Double, Double, Double) {
        let value = Int((OutputLook.normalizedColor(hex) ?? "#000000").dropFirst(), radix: 16) ?? 0
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
