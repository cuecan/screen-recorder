import Foundation
import Testing
@testable import ProjectKit

struct WaveformScaleTests {
    @Test func gainIsAppliedBeforeDisplayCompression() {
        let peak = pow(10, -20.0 / 20)
        #expect(abs(WaveformScale.height(peak: peak, gain: 0) - 0.6) < 1e-9)
        #expect(abs(WaveformScale.height(peak: peak, gain: -12) - 0.36) < 1e-9)
        #expect(abs(WaveformScale.height(peak: peak, gain: 6) - 0.72) < 1e-9)
        let quiet = pow(10, -56.0 / 20)
        #expect(WaveformScale.height(peak: quiet, gain: 0) == 0)
        #expect(WaveformScale.height(peak: quiet, gain: 12) > 0)
    }

    @Test func offSilenceAndFullScaleStayWithinTheBand() {
        #expect(WaveformScale.height(peak: 1, gain: -60) == 0)
        #expect(WaveformScale.height(peak: 0, gain: 12) == 0)
        #expect(WaveformScale.height(peak: 1, gain: 12) == 1)
        #expect(WaveformScale.height(peak: .nan, gain: 0) == 0)
    }
}
