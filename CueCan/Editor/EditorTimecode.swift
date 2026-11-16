import ProjectKit
import SwiftUI

/// The transport's rapidly changing clock is isolated from its native pickers, switches and buttons.
/// Updating the playhead must not rebuild every control while video is playing.
struct EditorTimecode: View {
    let model: EditorModel

    var body: some View {
        let timecode = Timecode(frameDuration: model.frameDuration)
        Text("\(timecode.string(model.currentTime)) / \(timecode.string(model.duration))")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("Minutes, seconds and frames, at \(timecode.frameRate) frames a second")
            .accessibilityLabel("Playhead and duration")
            .accessibilityValue("\(timecode.string(model.currentTime)) of \(timecode.string(model.duration))")
    }
}
