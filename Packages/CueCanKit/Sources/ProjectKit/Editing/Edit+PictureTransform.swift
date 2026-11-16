import Foundation

extension Edit {
    /// Which recorded picture a clip's static zoom and pan change.
    public enum Picture: String, Codable, CaseIterable, Sendable { case screen, camera }

    /// Sets or resets one picture's framing for all the listed clips as a single edit operation.
    /// A split copies this framing; other clips from the same take are untouched.
    public mutating func setTransform(_ transform: PictureTransform?, picture: Picture, for clips: [ClipID]) throws(EditError) {
        let indices = try clips.map { id throws(EditError) -> Int in
            guard let index = main.firstIndex(where: { $0.id == id }) else { throw .unknownClip(id) }
            return index
        }
        for index in indices {
            switch picture {
            case .screen: main[index].screenTransform = transform == .identity ? nil : transform
            case .camera: main[index].cameraTransform = transform
            }
        }
    }
}
