import Foundation
import ProjectKit
import RenderKit
import Testing
@testable import CueCan

@MainActor
struct TrimLoupeTests {
    @Test func decoderCancellationWithoutGestureCancellationLeavesAnActionableState() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-loupe-error-\(UUID())"), title: "Loupe cancellation fixture")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = TrimLoupeModel { _ in throw CancellationError() }
        model.show(request(6), folder: folder)
        try await wait { !model.updating }
        #expect(model.visible && model.problem != nil)
        guard case .failed = model.state else { Issue.record("A cancelled decoder must not leave a permanent spinner."); return }
        model.end()
        guard case .hidden = model.state else { Issue.record("Ending a gesture hides all feedback."); return }
    }

    @Test func burstsKeepOnlyTheNewestTargetAndCancelledWorkCannotOverlapTheNextGesture() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-loupe-\(UUID())"), title: "Loupe queue fixture")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let gate = LoupeGate()
        let model = TrimLoupeModel { plan in await gate.render(plan.cut) }
        model.show(request(6), folder: folder)
        try await wait { gate.times.count == 1 }
        for frame in 1...60 { model.show(request(6 + Double(frame) / 60), folder: folder) }
        #expect(gate.times == [6])
        gate.release()
        try await wait { gate.times.count == 2 }
        #expect(gate.times == [6, 7])
        gate.release()
        try await wait { !model.updating }
        model.show(request(8), folder: folder)
        try await wait { gate.times.count == 3 }
        model.end()
        #expect(!model.visible && model.pictures == nil)
        model.show(request(7.5), folder: folder)
        #expect(gate.times.count == 3)
        gate.release()
        try await wait { gate.times.count == 4 }
        #expect(gate.times.last == 7.5)
        gate.release()
        try await wait { !model.updating }
        #expect(model.visible && model.plan?.cut == 7.5)
        model.end()
    }

    @Test func returningToACachedFrameDoesNotDecodeItAgain() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-loupe-cache-\(UUID())"), title: "Loupe cache fixture")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let counter = LoupeCounter()
        let model = TrimLoupeModel { _ in await counter.frame() }
        model.show(request(6), folder: folder)
        try await wait { !model.updating }
        model.show(request(7), folder: folder)
        try await wait { !model.updating }
        model.show(request(6), folder: folder)
        #expect(!model.updating && counter.count == 2)
        model.end()
    }

    @Test func keyboardFeedbackRemainsVisibleUntilAColdDecoderReturns() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-loupe-cold-\(UUID())"), title: "Cold loupe fixture")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let gate = LoupeGate()
        let model = TrimLoupeModel { plan in await gate.render(plan.cut) }
        model.show(request(6), folder: folder, briefly: true)
        try await wait { gate.times.count == 1 }
        try await Task.sleep(for: .milliseconds(1650))
        #expect(model.visible && model.updating)
        gate.release()
        try await wait { !model.updating }
        #expect(model.visible)
        model.end()
    }

    private func request(_ time: Double) -> TrimLoupeRequest {
        let source = SourceID(number: 1)
        let edit = Edit(main: [Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 5),
                               Clip(id: ClipID(number: 2), source: source, sourceIn: 5, sourceOut: 10)])
        // A join rolled with the Trim tool: the first clip's end moves out, and the second's start with it.
        return TrimLoupeRequest(edit: edit, clip: ClipID(number: 1), edge: .end, sourceTime: time,
                                sourceDuration: 10, frameDuration: 1.0 / 60, rolling: true)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while !condition() {
            guard clock.now < deadline else { throw NSError(domain: "LoupeTests", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor private final class LoupeGate {
    private(set) var times: [Double] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func render(_ time: Double) async -> TrimPreviewFrames {
        times.append(time)
        await withCheckedContinuation { waiting.append($0) }
        return TrimPreviewFrames(outgoing: nil, incoming: nil)
    }
    func release() { waiting.removeFirst().resume() }
}

@MainActor private final class LoupeCounter {
    private(set) var count = 0
    func frame() -> TrimPreviewFrames {
        count += 1
        return TrimPreviewFrames(outgoing: nil, incoming: nil)
    }
}
