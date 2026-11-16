import ProjectKit
import SwiftUI

/// The shape of the screen a take records, as the recorder and the editor both write it: a display and
/// "Screen 16:9". Callers set the font and colour.
struct ScreenRatioLabel: View {
    let ratio: CaptureArea.Ratio
    /// The display symbol's size, a little under the text's.
    var iconSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "display").font(.system(size: iconSize))
            Text("Screen \(ratio.rawValue)").monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
