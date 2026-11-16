import Foundation

/// Kinds of inspector controls stay in a fixed place as the project or selection changes.
enum InspectorTab: String, CaseIterable, Identifiable {
    case video, audio, transcript, info

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .transcript: "text.alignleft"
        case .info: "info.circle"
        }
    }
}
