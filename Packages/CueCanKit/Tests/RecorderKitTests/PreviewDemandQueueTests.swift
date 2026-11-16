import CoreGraphics
import Testing
@testable import RecorderKit

struct PreviewDemandQueueTests {
    private func target(_ x: Double) -> PreviewTarget { PreviewTarget(displayID: 1, sourceRect: CGRect(x: x, y: 0, width: 640, height: 480)) }

    @Test func burstsAndTransientRemovalKeepOnlyTheFinalDemand() throws {
        var queue = PreviewDemandQueue()
        let initial = queue.request(target(0))
        let first = try #require(initial)
        for x in 1...50 { let started = queue.request(target(Double(x))); #expect(started == nil) }
        let removal = queue.request(nil)
        #expect(removal == nil)
        let replacement = queue.request(target(51))
        #expect(replacement == nil)
        let following = queue.completed(first)
        let next = try #require(following)
        #expect(next.target == target(51))
        let obsolete = queue.completed(first)
        #expect(obsolete == nil)
        let done = queue.completed(next)
        #expect(done == nil)
        let stop = queue.request(nil)
        #expect(stop != nil && stop?.target == nil)
    }

    @Test func aRepeatedDemandDuringAnUpdateCanRetryAFailedStep() throws {
        var queue = PreviewDemandQueue()
        let initial = queue.request(target(0))
        let first = try #require(initial)
        let started = queue.request(target(0))
        #expect(started == nil)
        let following = queue.completed(first)
        let retry = try #require(following)
        #expect(retry.id != first.id && retry.target == first.target)
        let done = queue.completed(retry)
        #expect(done == nil)
    }
}
