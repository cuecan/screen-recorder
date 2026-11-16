import Foundation

/// What a track's file holds, as probed when it was recorded or imported.
public struct MediaInfo: Codable, Equatable, Sendable {
    /// The video stream of a file.
    public struct Video: Codable, Equatable, Sendable {
        public var width: Int
        public var height: Int
        /// The nominal frame rate. For variable-frame-rate footage, the average.
        public var frameRate: Double
        /// The frames a second capture was set to: 60 for the screen, the camera's own rate. The screen sends
        /// a frame only when something on it changes, so its measured ``frameRate`` says how busy it was, not
        /// its clock. The edit's frame clock follows this (docs/design.md, "Frame clock").
        public var captureRate: Int
        public var isVariableFrameRate: Bool
        /// The codec's four-character code or name, such as `hvc1` or `apcn`.
        public var codec: String
        /// The color primaries and transfer function as probed, such as `ITU_R_2020` / `ITU_R_2100_HLG`.
        public var colorPrimaries: String?
        public var transferFunction: String?
        public var isHDR: Bool
        public var bitDepth: Int?

        public init(
            width: Int,
            height: Int,
            frameRate: Double,
            captureRate: Int,
            isVariableFrameRate: Bool = false,
            codec: String,
            colorPrimaries: String? = nil,
            transferFunction: String? = nil,
            isHDR: Bool = false,
            bitDepth: Int? = nil
        ) {
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.captureRate = captureRate
            self.isVariableFrameRate = isVariableFrameRate
            self.codec = codec
            self.colorPrimaries = colorPrimaries
            self.transferFunction = transferFunction
            self.isHDR = isHDR
            self.bitDepth = bitDepth
        }
    }

    /// The audio stream of a file.
    public struct Audio: Codable, Equatable, Sendable {
        public var sampleRate: Double
        public var channels: Int
        public var codec: String

        public init(sampleRate: Double, channels: Int, codec: String) {
            self.sampleRate = sampleRate
            self.channels = channels
            self.codec = codec
        }
    }

    public var duration: TimeInterval
    public var video: Video?
    public var audio: Audio?
    /// The start timecode, when the file carries one, as `HH:MM:SS:FF`.
    public var timecode: String?

    public init(duration: TimeInterval, video: Video? = nil, audio: Audio? = nil, timecode: String? = nil) {
        self.duration = duration
        self.video = video
        self.audio = audio
        self.timecode = timecode
    }
}
