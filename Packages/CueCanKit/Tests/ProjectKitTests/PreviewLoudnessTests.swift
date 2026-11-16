import Testing
@testable import ProjectKit

struct PreviewLoudnessTests {
    @Test func onlyTheCurrentMixCanBecomeReadyOrFail() {
        var preview = PreviewLoudness()
        #expect(!preview.isEnabled)
        let old = preview.begin()
        let current = preview.begin()
        preview.finish(old, hasAudio: true)
        #expect(preview.isPreparing)
        preview.fail(old, message: "Old failure")
        #expect(preview.state == .preparing(current))
        preview.finish(current, hasAudio: false)
        #expect(preview.state == .ready(current, hasAudio: false))
        preview.disable()
        preview.finish(current, hasAudio: true)
        #expect(preview.state == .off)
    }
}
