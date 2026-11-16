import ProjectKit

/// Mixed is distinct from the source's own microphone; no selected clip lends its value to the others.
enum ClipAudioChoice: Hashable {
    case mixed
    case own
    case track(ClipAudio)

    init(clips: [Clip]) {
        guard let first = clips.first, clips.allSatisfy({ $0.audio == first.audio }) else {
            self = .mixed
            return
        }
        self = first.audio.map(Self.track) ?? .own
    }
}
