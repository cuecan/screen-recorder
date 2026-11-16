import ProjectKit
import SwiftUI

/// Isolates playback-clock observation from the expensive timeline content. A manual scroll suspends
/// playback following; explicit navigation or starting playback restores it.
struct TimelineNavigation: ViewModifier {
    let model: EditorModel
    let viewport: TimelineViewport
    let dragging: Bool
    @Binding var position: ScrollPosition
    @State private var followsPlayback = true

    func body(content: Content) -> some View {
        content
            .onChange(of: model.zoom) { old, new in
                move(to: viewport.offsetAfterZoom(from: old, to: new, playhead: model.currentTime, duration: model.duration))
            }
            .onChange(of: model.seekRequest) {
                followsPlayback = true
                reveal(playing: false)
            }
            .onChange(of: model.duration) {
                move(to: viewport.clampedOffset(viewport.offset, duration: model.duration, zoom: model.zoom))
            }
            .onChange(of: model.isPlaying) { _, playing in
                if playing { followsPlayback = true; reveal(playing: false) }
            }
            .onChange(of: model.currentTime) {
                if model.isPlaying, followsPlayback, !dragging { reveal(playing: true) }
            }
            .onScrollPhaseChange { _, phase in
                if followsPlayback, phase == .tracking || phase == .interacting { followsPlayback = false }
            }
    }

    private func reveal(playing: Bool) {
        move(to: viewport.offsetRevealing(model.currentTime, duration: model.duration, zoom: model.zoom, playing: playing))
    }

    private func move(to offset: Double) {
        guard abs(offset - viewport.offset) > 0.5 else { return }
        position.scrollTo(x: offset)
    }
}
