import AVFoundation
import CoreImage.CIFilterBuiltins
import RecorderKit
import SwiftUI

/// Settings' Lip sync row (docs/ui.md, "Lip sync", S1): the number for the camera and mic the last setup
/// used, typed or stepped, and Calibrate… to measure it with a phone.
struct LipSyncSettingRow: View {
    @State private var model = SyncCalibrationModel()
    @State private var calibrating = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                MillisecondsField(label: "Lip sync", value: model.milliseconds) { model.set(milliseconds: $0) }
                Button("Calibrate…") { calibrating = true }
            }
            .disabled(!model.canCalibrate)
        } label: {
            Text("Lip sync")
            Text(devices)
        }
        .help("How far the camera runs behind the mic.")
        .onAppear { model.refresh() }
        .sheet(isPresented: $calibrating) { LipSyncCalibrationSheet(model: model) }
    }

    private var devices: String {
        guard let camera = model.camera, let mic = model.mic else { return "Needs a camera and a mic" }
        return "\(camera.name) · \(mic.name)"
    }
}

/// Measuring lip sync with the sync page (docs/ui.md, "Lip sync", S2 to S5): it listens from the moment
/// it opens, shows the camera so the phone can be held in view, and saves the result when five readings
/// agree.
struct LipSyncCalibrationSheet: View {
    let model: SyncCalibrationModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 8) {
                    QRCode(text: SyncSignal.pageAddress)
                        .frame(width: 132, height: 132)
                        .accessibilityLabel("QR code for \(address)")
                    Text(address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                VStack(spacing: 10) {
                    picture
                    signals.frame(height: 18)
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 468)
        .onAppear {
            model.refresh()
            model.start()
        }
        .onDisappear { model.cancel() }
    }

    private var address: String { SyncSignal.pageAddress.replacing("https://", with: "") }

    private var measurement: SyncMeasurement? {
        switch model.stage {
        case .listening(_, let measurement), .measured(let measurement): measurement
        default: nil
        }
    }

    /// The camera, with what's happening laid over it.
    private var picture: some View {
        ZStack {
            Color(white: 0.17)
            if let feed = model.preview { CameraPreview(feed: feed) }
            switch model.stage {
            case .ready, .starting:
                ProgressView().controlSize(.small)
            case .listening(_, let measurement):
                if measurement.flashes == 0 {
                    Text("Hold your phone up to the camera")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: .capsule)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                }
            case .measured:
                result
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
    }

    private var result: some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white, .green)
                .padding(.bottom, 4)
            Text("\(model.milliseconds) ms")
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
            Text("Saved for new recordings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
    }

    /// What's been seen and heard, and how many readings agree.
    @ViewBuilder private var signals: some View {
        if let measurement {
            HStack(spacing: 12) {
                if case .listening = model.stage {
                    signal("sun.max.fill", "Flash", count: measurement.flashes, missing: measurement.missing == .flash)
                    signal("speaker.wave.2.fill", "Beep", count: measurement.beeps, missing: measurement.missing == .beep)
                }
                Spacer(minLength: 0)
                switch measurement.missing {
                case .beep:
                    Text("No beep heard. Turn the phone up.").font(.caption).foregroundStyle(.orange)
                case .flash:
                    Text("No flash seen. Bring the phone closer.").font(.caption).foregroundStyle(.orange)
                case nil:
                    dots(min(measurement.agreeing.count, SyncSignal.readingsWanted))
                }
            }
        }
    }

    private func signal(_ symbol: String, _ name: String, count: Int, missing: Bool) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(missing ? AnyShapeStyle(.orange) : count > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .symbolEffect(.bounce, value: count)
            .accessibilityLabel(name)
            .accessibilityValue(missing ? "missing" : count > 0 ? "\(count)" : "none yet")
    }

    private func dots(_ filled: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<SyncSignal.readingsWanted, id: \.self) { index in
                Circle()
                    .strokeBorder(index < filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary), lineWidth: 1.5)
                    .background(Circle().fill(index < filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) of \(SyncSignal.readingsWanted) measured")
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            switch model.stage {
            case .measured:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            case .failed:
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { model.start() }.keyboardShortcut(.defaultAction)
            case .ready, .starting, .listening:
                Button("Cancel") {
                    model.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}

/// A number of milliseconds, typed or stepped 10 at a time, kept within ±500: lip sync's control in
/// Settings and in the editor's inspector. Each change is passed on once, when it's made.
struct MillisecondsField: View {
    let label: String
    let value: Int
    let set: (Int) -> Void
    @State private var draft = 0
    /// The last number passed on, so a step taken before the new value comes back isn't lost or sent twice.
    @State private var sent = 0

    static let limit = SyncCalibrations.Calibration.limitMilliseconds

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, value: $draft, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 48)
            Stepper(label, onIncrement: { commit(draft + 10) }, onDecrement: { commit(draft - 10) })
                .labelsHidden()
            Text("ms").foregroundStyle(.secondary)
        }
        .onChange(of: value, initial: true) { _, new in
            sent = new
            draft = new
        }
        // A typed number arrives when it's committed, with Return or by leaving the field.
        .onChange(of: draft) { _, new in commit(new) }
    }

    private func commit(_ milliseconds: Int) {
        let kept = min(Self.limit, max(-Self.limit, milliseconds))
        guard kept != sent else {
            if draft != kept { draft = kept }
            return
        }
        sent = kept
        draft = kept
        set(kept)
    }
}

/// A QR code for some text, drawn by Core Image, black on white with a quiet margin.
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(8)
                .background(.white, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        }
    }

    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

#Preview("Settings row") {
    Form { LipSyncSettingRow() }.formStyle(.grouped).frame(width: 560)
}
