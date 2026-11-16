import RecorderKit
import SwiftUI

/// The mic's level: green, and red when the held peak nears 0 dBFS (docs/decisions.md, 18 and 48). It's
/// driven by ``LevelBallistics``, so it rises with a peak and falls back smoothly instead of flickering
/// every 20 ms, and its held peak is drawn as a mark that stays a moment.
struct LevelMeterView: View {
    /// The meter's level in dBFS.
    let decibels: Float
    /// The held peak in dBFS, drawn as a mark, red with the bar when it nears 0 dBFS. Nil for none.
    var peak: Float?
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(isClipping ? Color.red : Color.green)
                    .frame(width: width * Self.fraction(decibels))
                    .animation(.linear(duration: 0.05), value: decibels)
                if let peak, peak > -60 {
                    Rectangle()
                        .fill(isClipping ? Color.red : .white.opacity(0.85))
                        .frame(width: 2)
                        .offset(x: max(0, width * Self.fraction(peak) - 2))
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Mic level")
        .accessibilityValue("\(Int(decibels)) dB")
    }

    private var isClipping: Bool {
        LevelZone(peakDecibels: max(decibels, peak ?? -120)) == .clipping
    }

    /// A level on a scale from −60 dBFS, so quiet speech still shows.
    private static func fraction(_ decibels: Float) -> CGFloat {
        CGFloat(max(0, min(1, (decibels + 60) / 60)))
    }
}
