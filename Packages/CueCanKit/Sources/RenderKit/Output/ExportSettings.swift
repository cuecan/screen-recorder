import Foundation
import ProjectKit

/// How an export is encoded.
public struct ExportSettings: Codable, Sendable, Equatable {
    public enum Codec: String, Sendable, CaseIterable, Codable {
        case hevc, h264

        public var displayName: String { self == .hevc ? "HEVC" : "H.264" }
    }

    public var codec: Codec
    /// 1 for 1080p, 2 for 4K.
    public var scale: Double

    public init(codec: Codec = .hevc, scale: Double = 1) {
        self.codec = codec
        self.scale = scale
    }
}
