import ProjectKit

/// Voice and system audio have independent waveform readers, even on the same take.
enum WaveformSource: Hashable {
    case voice(SourceID)
    case system(SourceID)
}
