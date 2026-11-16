import Foundation

/// A processing event for the app, with human wording independent of its stage identity.
public struct ProcessingProgress: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case transcribing, applyingVocabulary, cleaning, readingScreen
    }
    public let stage: Stage
    public let source: SourceID
    public let message: String
    public init(stage: Stage, source: SourceID, message: String) {
        self.stage = stage
        self.source = source
        self.message = message
    }
}
