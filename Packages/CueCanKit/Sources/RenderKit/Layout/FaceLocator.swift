import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// Finds the creator's face in the camera's file, for framing the camera around it (docs/decisions.md, 52),
/// with Apple's Vision face detection, on the Mac.
///
/// It looks at a few frames spread over the recording and takes the middle of the largest face in each,
/// then the median, so a frame where the creator looked away or leaned out doesn't decide it.
public enum FaceLocator {
    /// A face, as fractions of the picture, from its top left.
    public struct Face: Sendable, Equatable {
        /// The face's bounding box.
        public var box: CGRect
        public var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }

        public init(box: CGRect) {
            self.box = box
        }
    }

    /// How many frames are looked at.
    public static let sampleCount = 5

    /// The face across a video file's frames, or nil if none of them has one.
    public static func face(in url: URL, samples: Int = sampleCount) async throws -> Face? {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var faces: [Face] = []
        for index in 0..<max(1, samples) {
            let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(max(1, samples)), preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image, let face = try largestFace(in: image) else { continue }
            faces.append(face)
        }
        return median(of: faces)
    }

    /// The largest face in a picture.
    public static func largestFace(in image: CGImage) throws -> Face? {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return nil
        }
        // Vision's boxes are from the bottom left.
        let box = observation.boundingBox
        return Face(box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
    }

    /// The face whose middle is the median of all the faces' middles, sized like the median face.
    public static func median(of faces: [Face]) -> Face? {
        guard !faces.isEmpty else { return nil }
        func middle(_ values: [CGFloat]) -> CGFloat {
            let sorted = values.sorted()
            let half = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[half] : (sorted[half - 1] + sorted[half]) / 2
        }
        let x = middle(faces.map { $0.center.x })
        let y = middle(faces.map { $0.center.y })
        let width = middle(faces.map { $0.box.width })
        let height = middle(faces.map { $0.box.height })
        return Face(box: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height))
    }
}
