import Foundation

/// Which picture a placement shows. Each role is its own lane of video in the composition.
public enum PictureRole: String, Codable, Sendable, CaseIterable {
    /// A screen recording.
    case screen
    /// The camera the app recorded beside the screen.
    case camera
    /// An imported video: a phone or camera clip.
    case video
    /// A B-roll source over the main track.
    case broll
}
