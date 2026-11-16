import ProjectKit
import SwiftUI

/// A passive two-picture loupe above the edge, leaving the output viewer and transport intact.
struct TrimLoupeView: View {
    let preview: TrimLoupeModel
    let frameDuration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(preview.plan?.edge == .start ? "Trim start" : "Trim end").fontWeight(.medium)
                Spacer()
                if preview.updating { ProgressView().controlSize(.mini) }
                if preview.updating { Text("Updating…").foregroundStyle(.secondary) }
            }
            .font(.caption)
            HStack(spacing: 6) {
                picture(preview.pictures?.outgoing, title: "Last kept")
                picture(preview.pictures?.incoming, title: "First kept")
            }
            HStack {
                if let plan = preview.plan {
                    let frames = plan.deltaFrames
                    Text("\(frames < 0 ? "−" : "+")\(abs(frames)) \(abs(frames) == 1 ? "frame" : "frames")").monospacedDigit()
                    Spacer()
                    if plan.atLimit { Text("Trim limit") }
                }
            }
            .font(.caption)
            if preview.problem != nil {
                Text("Picture unavailable").font(.caption2).foregroundStyle(.secondary).help(preview.problem ?? "")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trim preview")
    }

    private func picture(_ picture: TrimLoupeModel.Picture?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                Color.black
                if let picture { Image(nsImage: picture.image).resizable().scaledToFit() }
                else if !preview.updating { Text("No picture").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
            }
            .frame(height: 76)
            .clipShape(.rect(cornerRadius: 4))
            .accessibilityLabel(title)
            HStack {
                Text(title)
                Spacer(minLength: 2)
                if let picture { Text(Timecode(frameDuration: frameDuration).string(picture.time)).monospacedDigit() }
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }
}
