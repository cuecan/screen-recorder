import ProjectKit
import RecorderKit
import SwiftUI

/// The setup element's strip (docs/ui.md, R10; docs/decisions.md, 49, 78 and 79): two rows under the live
/// preview. The top row asks where the recording will be posted and its layout (docs/ui.md, L1), both
/// remembered from the last setup, and ends in Start recording; the bottom row picks the screen (or No
/// screen, for the camera alone: R9), the camera, the mic with its level, and system audio. Cancel is in the
/// element's title bar.
struct SetupStripView: View {
    let recorder: RecorderModel

    var body: some View {
        VStack(spacing: 0) {
            topRow
                .frame(height: 60)
                .padding(.top, 4)
                .padding(.horizontal, 2)
            bottomRow
                .padding(.top, 5)
                .frame(height: 40, alignment: .top)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
            if let problem = recorder.setupProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(VideoFormat.Destination.allCases, id: \.self) { destination in
                    FormatButton(
                        title: destination.title,
                        icon: destination.icon,
                        width: 80,
                        isSelected: recorder.destination == destination,
                        hint: destination.hint
                    ) {
                        recorder.choose(destination)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Where will you post this?")

            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 38)

            LayoutButton(recorder: recorder)

            // No options menu: the panel's size on the panel and in the menu
            // bar's menu (docs/decisions.md, 78). Framing and Start recording take the room (79).
            Spacer(minLength: 0)

            FramingCircle(recorder: recorder)
            StartCircle(recorder: recorder)
                .padding(.trailing, 2)
        }
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: 4) {
            SourcePicker(
                icon: recorder.recordsScreen ? .symbol("display") : .noScreen,
                title: screenTitle,
                isOff: !recorder.recordsScreen,
                entries: screenMenu
            )
            .accessibilityLabel("Screen: \(screenTitle)")
            SourcePicker(
                icon: .symbol("video"),
                title: recorder.isCameraOn ? recorder.cameraName ?? "Camera" : (recorder.cameraAllowed ? "No camera" : "Camera not allowed"),
                isOff: !recorder.isCameraOn,
                entries: cameraMenu
            )
            .accessibilityLabel("Camera: \(recorder.cameraName ?? "none")")
            SourcePicker(
                icon: .symbol("mic"),
                title: recorder.isMicOn ? recorder.micName ?? "Mic" : (recorder.micAllowed ? "No microphone" : "Mic not allowed"),
                isOff: !recorder.isMicOn,
                level: recorder.isMicOn ? recorder.meterDecibels : nil,
                peak: recorder.meterPeakDecibels,
                entries: micMenu
            )
            .accessibilityLabel("Microphone: \(recorder.micName ?? "none")")
            // System audio comes with the screen recording, so No screen turns it off (R9).
            SourcePicker(
                icon: .symbol(recorder.capturesSystemAudio ? "speaker.wave.2" : "speaker.slash"),
                title: recorder.capturesSystemAudio ? "System audio" : "No system audio",
                isOff: !recorder.capturesSystemAudio,
                isEnabled: recorder.recordsScreen,
                hint: recorder.recordsScreen ? nil : "No screen: system audio is recorded with the screen.",
                entries: systemAudioMenu
            )
            .accessibilityLabel("System audio: \(recorder.capturesSystemAudio ? "on" : "off")")
        }
        .frame(height: 34)
    }

    private var screenTitle: String {
        guard recorder.recordsScreen else { return "No screen" }
        let area = recorder.area
        return area.displays.first { $0.id == area.selectedDisplayID }?.name ?? "Screen"
    }

    /// The displays, a divider, then No screen: the same pattern as the camera and the mic (R9).
    private func screenMenu() -> [MenuEntry] {
        let area = recorder.area
        area.refreshDisplays()
        // Matching monitors are told apart by their size.
        let names = area.displays.map(\.name)
        return SourceMenu.entries(area.displays, selected: recorder.recordsScreen ? area.selectedDisplayID : nil, noneTitle: "No screen") { display in
            names.filter { $0 == display.name }.count > 1 ? "\(display.name) · \(display.width) × \(display.height)" : display.name
        } choose: { recorder.chooseScreen($0) }
    }

    private func cameraMenu() -> [MenuEntry] {
        var entries = SourceMenu.entries(recorder.cameras, selected: recorder.cameraID, noneTitle: "No camera", title: { $0.name }) {
            recorder.chooseCamera($0)
        }
        if !recorder.cameraAllowed {
            entries.append(.separator)
            entries.append(.item("Allow the camera in System Settings…") { PrivacyPane.camera.open() })
        }
        return entries
    }

    private func micMenu() -> [MenuEntry] {
        var entries = SourceMenu.entries(recorder.microphones, selected: recorder.micID, noneTitle: "No microphone", title: { $0.name }) {
            recorder.chooseMic($0)
        }
        if !recorder.micAllowed {
            entries.append(.separator)
            entries.append(.item("Allow the mic in System Settings…") { PrivacyPane.microphone.open() })
        }
        return entries
    }

    private func systemAudioMenu() -> [MenuEntry] {
        [
            .item("Record system audio", checked: recorder.recordsSystemAudio) { recorder.recordsSystemAudio = true },
            .item("No system audio", checked: !recorder.recordsSystemAudio) { recorder.recordsSystemAudio = false },
        ]
    }
}

/// A large icon-and-label button in the bar's top row.
private struct FormatButton: View {
    let title: String
    let icon: FormatIcon.Kind
    let width: CGFloat
    let isSelected: Bool
    var isEnabled = true
    let hint: String
    let action: () -> Void

    var body: some View {
        // Not `.disabled`, so the reason still shows on hover.
        Button {
            if isEnabled { action() }
        } label: {
            VStack(spacing: 6) {
                FormatIcon(kind: icon)
                    .frame(width: 28, height: 20)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
            .frame(width: width, height: 54)
            .background(isSelected ? .white.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(hint)
    }
}

/// A compact picker in the bar's bottom row: an icon, a name cut short and a chevron, with the mic's thin
/// level line under its name.
private struct SourcePicker: View {
    enum Icon {
        case symbol(String)
        /// A display crossed out: there's no such SF Symbol.
        case noScreen
    }

    let icon: Icon
    let title: String
    var isOff = false
    var isEnabled = true
    /// Said on hover, such as why it's greyed out.
    var hint: String?
    var level: Float?
    /// The level's held peak, in dBFS.
    var peak: Float?
    let entries: () -> [MenuEntry]

    var body: some View {
        // Not `.disabled`, so the reason still shows on hover: a greyed-out picker opens nothing.
        PopUpMenuButton(entries: isEnabled ? entries : { [] }) {
            HStack(spacing: 8) {
                Group {
                    switch icon {
                    case .symbol(let name):
                        Image(systemName: name).font(.system(size: 13))
                    case .noScreen:
                        NoScreenIcon().frame(width: 17, height: 14)
                    }
                }
                .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(isOff ? .white.opacity(0.55) : .white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .overlay(alignment: .bottom) {
                // The mic's level under its name, 3 pt with the held peak, the only check while setting up
                // that the mic is live (docs/ui.md, R10; docs/decisions.md, 18).
                if let level {
                    LevelMeterView(decibels: level, peak: peak, height: 3)
                        .padding(.leading, 36)
                        .padding(.trailing, 27)
                        .padding(.bottom, 2)
                }
            }
            .contentShape(.rect)
        }
        .opacity(isEnabled ? 1 : 0.6)
        .help(hint ?? "")
        .frame(maxWidth: .infinity)
    }
}

/// A display with a line through it, from the mockup (docs/ui/mockups/RecBar.dc.html), on a 17 × 14 grid.
private struct NoScreenIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 17, size.height / 14)
            context.scaleBy(x: scale, y: scale)
            let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            context.stroke(Path(roundedRect: CGRect(x: 1, y: 1, width: 15, height: 9.5), cornerRadius: 1.5), with: .foreground, style: line)
            var path = Path()
            path.move(to: CGPoint(x: 6, y: 13))
            path.addLine(to: CGPoint(x: 11, y: 13))
            path.move(to: CGPoint(x: 8.5, y: 10.5))
            path.addLine(to: CGPoint(x: 8.5, y: 13))
            path.move(to: CGPoint(x: 1.5, y: 0.5))
            path.addLine(to: CGPoint(x: 15.5, y: 11.5))
            context.stroke(path, with: .foreground, style: line)
        }
        .accessibilityHidden(true)
    }
}

/// The top row's line drawings, from the mockup's shapes (docs/ui/mockups/RecBar.dc.html), on a 28 × 20 grid.
struct FormatIcon: View {
    enum Kind {
        case landscape, vertical, both
    }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 28, size.height / 20)
            context.scaleBy(x: scale, y: scale)
            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
                context.stroke(Path(CGRect(x: x, y: y, width: w, height: h)), with: .foreground, style: line)
            }
            switch kind {
            case .landscape:
                rect(2, 3, 24, 14)
            case .vertical:
                rect(8.5, 1, 11, 18)
            case .both:
                rect(1, 4, 17, 12)
                rect(19, 1, 8, 18)
            }
        }
        .accessibilityHidden(true)
    }
}

extension VideoFormat.Destination {
    var title: String {
        switch self {
        // Named by shape.
        case .landscape: "16:9"
        case .vertical: "9:16"
        case .both: "16:9 & 9:16"
        }
    }

    var hint: String {
        switch self {
        case .landscape: "YouTube videos"
        case .vertical: "Shorts, Reels and TikTok"
        case .both: "A video and a Short from one recording"
        }
    }

    var icon: FormatIcon.Kind {
        switch self {
        case .landscape: .landscape
        case .vertical: .vertical
        case .both: .both
        }
    }
}

/// The Layout button, in place of the camera size (docs/ui.md, L1): the chosen preset drawn as what it makes,
/// its name, and "Screen" with the shape of the area it records. It turns the element's well into the Layout
/// choices, and back (R10).
private struct LayoutButton: View {
    let recorder: RecorderModel

    var body: some View {
        let format = recorder.recordsScreen ? recorder.format : nil
        let hint = !recorder.recordsScreen ? "No screen: your camera fills the frame."
            : format == nil ? "Pick where you’ll post it first." : "Layout: \(format?.layoutName ?? "")"
        Button {
            guard format != nil else { return }
            recorder.toggleLayoutChoices()
        } label: {
            HStack(spacing: 10) {
                if let format {
                    TakePicture(layout: format.layout, destination: format.destination, look: recorder.look,
                                  screenPointHeight: recorder.screenPointHeight(for: format.captureRatio),
                                  height: format.destination == .vertical ? 44 : 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(format?.layoutName ?? "Layout")
                        .font(.system(size: 12.5, weight: .semibold))
                    if let format {
                        ScreenRatioLabel(ratio: format.captureRatio, iconSize: 10)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .help("The shape of the screen area you record")
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .rotationEffect(.degrees(recorder.isChoosingLayout ? 180 : 0))
            }
            .foregroundStyle(.white)
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .frame(height: 54)
            .background(.white.opacity(recorder.isChoosingLayout ? 0.15 : 0.07), in: .rect(cornerRadius: 10))
            .opacity(format == nil ? 0.4 : 1)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel("Layout: \(format?.layoutName ?? "none")")
    }
}

/// Framing, just left of Start recording (docs/ui.md, R10): a 40 pt circle with SF Symbols'
/// `viewfinder` and no word. It turns the well into framing the main camera's slot, so framing is offered
/// rather than found by hovering; filled while framing is open; dimmed, with the reason on hover, when there's
/// no camera to frame.
private struct FramingCircle: View {
    let recorder: RecorderModel

    var body: some View {
        let blocker = recorder.framingBlocker
        let isOpen = recorder.framingSlot != nil
        // Not `.disabled`, so the reason still shows on hover.
        Button {
            if blocker == nil { recorder.toggleMainFraming() }
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOpen ? Color(white: 0.11) : .white.opacity(0.9))
                .frame(width: 40, height: 40)
                .background(isOpen ? Color(white: 0.96) : .white.opacity(0.12), in: .circle)
                .opacity(blocker == nil ? 1 : 0.38)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(blocker ?? (isOpen ? "Back to the preview (Esc)" : "Frame the camera"))
        .accessibilityLabel("Frame the camera")
        .accessibilityHint(blocker ?? "")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

/// Start recording at the right end of the strip's top row (docs/ui.md, R10):
/// a red dot in a 3 pt white ring, 40 pt across, dimmed until recording can start, with the reason
/// on hover. Return starts too.
private struct StartCircle: View {
    let recorder: RecorderModel

    var body: some View {
        let conditions = recorder.startConditions
        // Not `.disabled`, so the reason still shows on hover.
        Button {
            if conditions.canStart { recorder.startRecording() }
        } label: {
            Circle()
                .fill(Color.recordingRed)
                .frame(width: 26, height: 26)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(.white.opacity(0.92), lineWidth: 3))
                .opacity(conditions.canStart ? 1 : 0.4)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(conditions.blocker ?? "Start recording (Return)")
        .accessibilityLabel("Start recording")
        .accessibilityHint(conditions.blocker ?? "")
    }
}
