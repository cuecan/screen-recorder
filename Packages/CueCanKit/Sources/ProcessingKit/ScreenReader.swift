import AVFoundation
import CoreGraphics
import Foundation
import ProjectKit
import Vision

/// Reads the screen track after recording (docs/decisions.md, 58): when the screen changes and when it goes
/// still, and, at each still moment, the text in the capture area, with Vision's text recognition on the Mac.
///
/// It looks at small grey thumbnails a few times a second and counts how many pixels changed. The
/// thresholds are starting values (TEST NEEDED on real recordings, as is how long reading text takes on a
/// long one).
public struct ScreenReader: Sendable {
    /// How often the screen is looked at, in frames a second.
    public var sampleRate: Double = 4
    /// The thumbnail's width in pixels.
    public var thumbnailWidth = 128
    /// A pixel counts as changed when its grey level moves by more than this, out of 255.
    public var pixelThreshold = 16
    /// The screen counts as changing when more than this fraction of the thumbnail changed. The pointer
    /// alone, drawn into the recording, is a few pixels, below it.
    public var changedFraction = 0.005
    /// A stretch with no change at least this long is a still moment.
    public var minimumStill: TimeInterval = 1.0

    public init() {}

    /// Analyses a source's screen track and returns what it found, without saving it.
    public func analyze(_ source: Source, in folder: ProjectFolder, readText: Bool, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ScreenAnalysis? {
        guard let track = source.track(.screen) else { return nil }
        let url = track.file.url(relativeTo: folder.url)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ProcessingError.missingFile(url) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return nil }

        let changed = try await changes(in: asset, duration: duration)
        let (changes, stills) = Self.runs(changed, step: 1 / sampleRate, duration: duration, minimumStill: minimumStill)
        var found = stills
        if readText, !found.isEmpty {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            for index in found.indices {
                try Task.checkCancellation()
                if index.isMultiple(of: 10) { progress("Reading the screen's text (\(index + 1) of \(found.count))") }
                let at = found[index].start + min(0.3, (found[index].end - found[index].start) / 2)
                guard let image = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image else { continue }
                found[index].text = try Self.text(in: image)
            }
        }
        let offset = track.startOffset
        return ScreenAnalysis(
            source: source.id,
            sampleRate: sampleRate,
            readText: readText,
            changes: changes.map { .init(start: $0.start + offset, end: $0.end + offset) },
            stills: found.map { .init(start: $0.start + offset, end: $0.end + offset, text: readText ? ($0.text ?? []) : nil) }
        )
    }

    /// For each sample, whether the screen changed since the one before.
    private func changes(in asset: AVURLAsset, duration: TimeInterval) async throws -> [Bool] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailWidth, height: thumbnailWidth)
        let tolerance = CMTime(seconds: 0.5 / sampleRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let count = max(1, Int(duration * sampleRate))
        let times = (0..<count).map { CMTime(seconds: Double($0) / sampleRate, preferredTimescale: 600) }
        var previous: [UInt8]?
        var changed: [Bool] = []
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            guard let image = try? result.image, let grey = Self.grey(image, width: thumbnailWidth) else {
                changed.append(false)
                continue
            }
            if let previous, previous.count == grey.count {
                let moved = zip(previous, grey).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > pixelThreshold ? 1 : 0) }
                changed.append(Double(moved) / Double(grey.count) > changedFraction)
            } else {
                changed.append(false)
            }
            previous = grey
        }
        return changed
    }

    /// Runs of change and of stillness from per-sample flags: changes, and stills at least `minimumStill`
    /// long, in the track's own time.
    static func runs(_ changed: [Bool], step: TimeInterval, duration: TimeInterval, minimumStill: TimeInterval) -> (changes: [TimeRange], stills: [(start: TimeInterval, end: TimeInterval, text: [ScreenAnalysis.TextLine]?)]) {
        var changes: [TimeRange] = []
        var stills: [(start: TimeInterval, end: TimeInterval, text: [ScreenAnalysis.TextLine]?)] = []
        var index = 0
        while index < changed.count {
            let state = changed[index]
            var end = index
            while end + 1 < changed.count, changed[end + 1] == state { end += 1 }
            // A change shows at the sample that differs from the one before, so it began a step earlier.
            let start = state ? max(0, Double(index - 1) * step) : Double(index) * step
            let stop = end + 1 >= changed.count ? duration : Double(end) * step
            if state {
                if let last = changes.last, start - last.end < step * 1.5 {
                    changes[changes.count - 1].end = stop
                } else {
                    changes.append(TimeRange(start: start, end: stop))
                }
            } else if stop - start >= minimumStill {
                stills.append((start, stop, nil))
            }
            index = end + 1
        }
        return (changes, stills)
    }

    /// An image as grey levels, `width` wide.
    static func grey(_ image: CGImage, width: Int) -> [UInt8]? {
        let height = max(1, Int((Double(width) * Double(image.height) / Double(max(image.width, 1))).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// The lines of text in an image, top to bottom, with where each is as fractions from the top left.
    static func text(in image: CGImage) throws -> [ScreenAnalysis.TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Screens show code, paths and names, which language correction "fixes".
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> ScreenAnalysis.TextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            func round(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
            return ScreenAnalysis.TextLine(
                text: candidate.string,
                box: [round(box.minX), round(1 - box.maxY), round(box.width), round(box.height)],
                confidence: (Double(candidate.confidence) * 100).rounded() / 100
            )
        }
        return lines.sorted { ($0.box[1], $0.box[0]) < ($1.box[1], $1.box[0]) }
    }
}
