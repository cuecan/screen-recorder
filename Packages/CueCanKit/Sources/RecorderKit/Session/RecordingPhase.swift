/// The recording lifecycle as presented by both the floating panel and the menu bar.
/// Resource ownership stays with the recorder's associated-value state.
public enum RecordingPhase: Equatable, Sendable, CaseIterable {
    case idle, settingUp, starting, recording, paused, saving, discarding

    public var isRecording: Bool { self == .recording || self == .paused }
    public var showsElapsed: Bool { isRecording }

    /// A fast start can already be recording when the panel's animation is ready.
    public var allowsPanelHandOver: Bool { self == .starting || isRecording }

    /// A distinct label for every operation that can be in progress.
    public var statusTitle: String {
        switch self {
        case .idle, .settingUp: "Ready"
        case .starting: "Starting"
        case .recording: "Recording"
        case .paused: "Paused"
        case .saving: "Saving…"
        case .discarding: "Discarding…"
        }
    }
}
