import AppKit
import ProjectKit
import SwiftUI

/// The sidebar beside the editor (docs/ui.md, P1 and P2; docs/decisions.md, 63): a column of thumbnails,
/// each with only the time it was recorded, under Today, Yesterday and dates.
struct ProjectSidebar: View {
    let takes: [ProjectSummary]
    @Binding var selection: URL?
    /// The take asking whether to move it to the Trash.
    @Binding var confirming: URL?
    let thumbnails: TakeThumbnails
    let moveToTrash: (URL) -> Void
    let duplicate: (URL) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.day) { index, group in
                        Text(Self.title(of: group.day))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                            .padding(.top, index == 0 ? 2 : 10)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.takes, id: \.url) { take in
                            TakeRow(
                                take: take,
                                image: thumbnails.images[take.url],
                                isSelected: selection == take.url,
                                activity: app.processing.activity[take.url] ?? app.exports.activity(for: take.url),
                                problem: app.processing.problems[take.url],
                                isConfirming: Binding(get: { confirming == take.url }, set: { confirming = $0 ? take.url : nil }),
                                select: { selection = take.url },
                                moveToTrash: { moveToTrash(take.url) },
                                duplicate: { duplicate(take.url) }
                            )
                            .id(take.url)
                            .task(id: take.thumbnailVersion) { thumbnails.request(take) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            // The column is exactly as wide as a thumbnail and its margins, so a scroller would cover them.
            .scrollIndicators(.never)
            .onChange(of: confirming) { _, url in
                if let url { withAnimation { scroller.scrollTo(url) } }
            }
        }
        .overlay {
            if takes.isEmpty {
                ContentUnavailableView {
                    Label("No recordings yet", systemImage: "video")
                } actions: {
                    Button("New recording") { app.recorder.openSetup() }
                }
            }
        }
    }

    /// The takes by the day they were recorded, newest first.
    private var days: [(day: Date, takes: [ProjectSummary])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: takes) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted(by: Self.comesFirst))
        }
    }

    /// Newest first. A copy has its original's time, so it's listed right under it (docs/decisions.md, 77).
    static func comesFirst(_ one: ProjectSummary, _ other: ProjectSummary) -> Bool {
        if one.createdAt != other.createdAt { return one.createdAt > other.createdAt }
        if (one.copyOf == nil) != (other.copyOf == nil) { return one.copyOf == nil }
        return one.title.localizedStandardCompare(other.title) == .orderedAscending
    }

    /// "Today", "Yesterday", or "Thursday, Nov 5".
    static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// One take: its thumbnail and the time it was recorded.
private struct TakeRow: View {
    let take: ProjectSummary
    let image: NSImage?
    let isSelected: Bool
    let activity: String?
    let problem: String?
    @Binding var isConfirming: Bool
    let select: () -> Void
    let moveToTrash: () -> Void
    let duplicate: () -> Void
    @State private var isHovered = false

    private static let size = TakeThumbnails.size
    private static let corner = 7.0

    /// The shape the take's editor shows, which its thumbnail shows too.
    private var isVertical: Bool { take.shape == .vertical }

    /// The time it was recorded; a copy says so, since it has its original's time.
    private var time: String {
        let time = take.createdAt.formatted(.dateTime.hour().minute())
        return take.copyOf == nil ? time : "\(time) · copy"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            thumbnail
            Text(time)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.leading, 2)
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 5, trailing: 6))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.10 : isHovered ? 0.05 : 0))
        )
        .padding(.horizontal, -6)
        .padding(.bottom, 6)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .help(problem ?? activity ?? (take.copyOf == nil ? "" : "A copy: its own edit, the same recordings"))
        .contextMenu {
            Button("Duplicate", action: duplicate)
                .help("A copy with its own edit, using the same recordings")
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([take.url]) }
            Divider()
            Button("Move to Trash…") { isConfirming = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(take.title), recorded \(take.createdAt.formatted(date: .abbreviated, time: .shortened))"))
        .accessibilityIdentifier(take.url.path(percentEncoded: false))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "Move to the Trash") { isConfirming = true }
        .accessibilityAction(named: "Duplicate", duplicate)
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        return ZStack {
            // Vertical takes sit in a faint 16:9 slot, so every row is the same height.
            shape.fill(Color.primary.opacity(isVertical ? 0.05 : 0.08))
            picture
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay {
            if isSelected {
                shape.inset(by: -1.25).stroke(Color.accentColor, lineWidth: 2.5)
            } else {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .overlay(alignment: .topLeading) {
            if problem != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .yellow)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.72), in: .circle)
                    .padding(6)
                    .accessibilityLabel(problem ?? "")
            }
        }
        .overlay(alignment: .topTrailing) { trashButton }
    }

    /// The picture, in its output's shape, with the progress bar along its bottom while it's working.
    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        let width = isVertical ? Self.size.height * 9 / 16 : Self.size.width
        return ZStack(alignment: .bottom) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
            if activity != nil { WorkingBar() }
        }
        .frame(width: width, height: Self.size.height)
        .clipShape(shape)
    }

    /// Shown on hover, or while it asks; the confirmation hangs from it.
    private var trashButton: some View {
        Button(action: { isConfirming = true }) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(isConfirming ? Color.red : Color.black.opacity(0.72), in: .circle)
        }
        .buttonStyle(.plain)
        .help("Move to the Trash (⌘⌫)")
        .accessibilityLabel("Move to the Trash")
        .accessibilityHidden(true)
        .padding(6)
        .opacity(isHovered || isConfirming ? 1 : 0)
        .allowsHitTesting(isHovered || isConfirming)
        .popover(isPresented: $isConfirming, arrowEdge: .bottom) {
            TrashConfirmation(isWorking: activity != nil, cancel: { isConfirming = false }, confirm: {
                isConfirming = false
                moveToTrash()
            })
        }
    }
}

/// A thin bar along the thumbnail's bottom while the take is being processed. Processing reports its steps,
/// not how far along it is, so the bar sweeps rather than fills.
private struct WorkingBar: View {
    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            GeometryReader { geometry in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let segment = geometry.size.width * 0.42
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: segment)
                    .offset(x: -segment + (geometry.size.width + segment) * phase)
            }
        }
        .frame(height: 3)
        .background(.black.opacity(0.45))
        .accessibilityHidden(true)
    }
}

/// "Move this recording to the Trash?" (docs/ui.md, P2).
private struct TrashConfirmation: View {
    let isWorking: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move this recording to the Trash?")
                    .font(.system(size: 12.5, weight: .semibold))
                // The question is enough: people know what the Trash is. Only the reason it
                // can't go yet needs saying.
                if isWorking {
                    Text("A background task is still using it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isWorking)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 228)
    }
}

#if DEBUG
/// The sidebar on the takes in `~/Movies/CueCan`, for checking it in Xcode's canvas.
private struct SidebarPreview: View {
    @State private var app = AppModel()
    @State private var thumbnails = TakeThumbnails()
    @State private var selection: URL?
    @State private var confirming: URL?

    var body: some View {
        let takes = app.library.projects()
        let _ = thumbnails.loadCachedForPreview(takes)
        ProjectSidebar(takes: takes, selection: $selection, confirming: $confirming, thumbnails: thumbnails, moveToTrash: { _ in }, duplicate: { _ in })
            .environment(app)
            .frame(width: 260, height: 900)
            .onAppear { selection = takes.sorted(by: ProjectSidebar.comesFirst).dropFirst().first?.url }
    }
}

#Preview("Sidebar", traits: .fixedLayout(width: 260, height: 900)) {
    SidebarPreview()
}
#endif
