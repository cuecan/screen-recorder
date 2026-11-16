import Testing
@testable import ProjectKit

struct PreviewSeekingTests {
    @Test func rapidScrubbingDisplaysAnInFlightFrameThenChasesTheLastTarget() throws {
        var seeking = PreviewSeeking()
        let started = seeking.request(1)
        let first = try #require(started)
        #expect(seeking.request(2) == nil)
        #expect(seeking.request(3) == nil)
        #expect(seeking.active == first)
        guard case .next(let last) = seeking.completed(first) else { Issue.record("The final pointer target must be sought."); return }
        #expect(last.time == 3)
        #expect(seeking.completed(last) == .settled)
        #expect(seeking.active == nil)
    }

    @Test func returningToTheInFlightTargetDoesNotSeekItAgain() throws {
        var seeking = PreviewSeeking()
        let started = seeking.request(1)
        let first = try #require(started)
        _ = seeking.request(2)
        _ = seeking.request(1)
        #expect(seeking.completed(first) == .settled)
    }

    @Test func anOldItemsCompletionCannotFinishOrConsumeItsReplacement() throws {
        var seeking = PreviewSeeking()
        let started = seeking.request(1)
        let old = try #require(started)
        _ = seeking.request(2)
        seeking.cancel()
        let restarted = seeking.request(4)
        let replacement = try #require(restarted)
        _ = seeking.request(5)
        #expect(seeking.completed(old) == .stale)
        #expect(seeking.active == replacement)
        guard case .next(let last) = seeking.completed(replacement) else { Issue.record("The replacement's target was lost."); return }
        #expect(last.time == 5)
        #expect(seeking.completed(replacement) == .stale)
        #expect(seeking.completed(last) == .settled)
    }

    @Test func invalidTargetsDoNotReplaceTheFinalValidTarget() throws {
        var seeking = PreviewSeeking()
        let started = seeking.request(0)
        let first = try #require(started)
        _ = seeking.request(2)
        #expect(seeking.request(.nan) == nil)
        #expect(seeking.request(.infinity) == nil)
        #expect(seeking.request(-1) == nil)
        guard case .next(let last) = seeking.completed(first) else { Issue.record("The valid target was lost."); return }
        #expect(last.time == 2)
    }
}
