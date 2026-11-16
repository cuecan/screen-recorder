#if DEBUG
import ProjectKit
import SwiftUI

// Canvas interactions use their own edit, and a current-format take instead of a dated fixture that
// stops opening after a format change. The copy is private to the preview process, never a recent take.
private let previewProject: URL = {
    let destination = FileManager.default.temporaryDirectory.appending(path: "cuecan-editor-preview-\(UUID())")
    guard let summary = ProjectLibrary().projects().first,
          let folder = try? ProjectFolder(opening: summary.url),
          let copy = try? folder.duplicate(to: destination, title: "Editor preview") else { return destination }
    return copy.url
}()

#Preview("Clip inspector · dark · narrow", traits: .fixedLayout(width: 280, height: 760)) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview(selecting: (try? folder.loadEdit())?.main.first?.id)
        InspectorView(model: model)
            .environment(AppModel())
            .preferredColorScheme(.dark)
    } else {
        Text("Record a take to preview the inspector.")
    }
}

#Preview("Audio popover · dark", traits: .sizeThatFitsLayout) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview()
        ToolStrip(model: model).padding()
            .environment(AppModel())
            .preferredColorScheme(.dark)
    } else {
        Text("Record a take to preview the audio controls.")
    }
}

#Preview("Timeline and a clip", traits: .fixedLayout(width: 1440, height: 900)) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview(playhead: 3.2, selecting: ClipID(number: 1))
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    PreviewPanels(model: model).padding(20)
                }
                Divider()
                InspectorView(model: model).frame(width: 300)
            }
            Divider()
            TransportBar(model: model)
            Divider()
            TimelineView(model: model)
        }
        .environment(AppModel())
    } else {
        Text("No project at \(previewProject.path(percentEncoded: false))")
    }
}

#Preview("Words under the waveform", traits: .fixedLayout(width: 1440, height: 260)) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview(playhead: 3.6)
        let _ = model.zoom = 300
        TimelineView(model: model).environment(AppModel())
    } else {
        Text("No project at \(previewProject.path(percentEncoded: false))")
    }
}

#Preview("The look", traits: .fixedLayout(width: 300, height: 760)) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview()
        InspectorView(model: model).environment(AppModel())
    } else {
        Text("No project at \(previewProject.path(percentEncoded: false))")
    }
}

#Preview("Cleanup and Voice", traits: .sizeThatFitsLayout) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview()
        HStack(alignment: .top, spacing: 24) {
            ProjectAudioInspector(model: model).frame(width: 320)
            ProjectVideoInspector(model: model).frame(width: 320)
        }
        .padding()
        .environment(AppModel())
    } else {
        Text("No project at \(previewProject.path(percentEncoded: false))")
    }
}

#Preview("Editor", traits: .fixedLayout(width: 1440, height: 900)) {
    if let folder = try? ProjectFolder(opening: previewProject) {
        EditorView(folder: folder).environment(AppModel())
    } else {
        Text("No project at \(previewProject.path(percentEncoded: false))")
    }
}
#endif

#if DEBUG
/// Keeps the editor's model alive for as long as the preview shows its popover.
private struct FramingPreview: View {
    @State private var model: EditorModel?
    @State private var target = FramingTarget()

    var body: some View {
        if let model {
            CameraFramingView(source: model.framing(SourceID(number: 1)), target: target).padding()
        } else {
            Text("No project at \(previewProject.path(percentEncoded: false))")
                .onAppear(perform: load)
        }
    }

    private func load() {
        guard let folder = try? ProjectFolder(opening: previewProject) else { return }
        let loaded = EditorModel(folder: folder)
        loaded.loadForPreview()
        let source = loaded.framing(SourceID(number: 1))
        source.loadStillForPreview(at: 4)
        target.slot = source.usedSlots.first ?? .split
        target.tabs = source.usedSlots
        model = loaded
    }
}

#Preview("Framing the camera", traits: .sizeThatFitsLayout) {
    FramingPreview()
}
#endif

#if DEBUG
/// A small project made on the spot for the transcript's preview: placeholder words, silences short and long,
/// and a screen log with two apps and a window change, but no media. The words are filler for checking the
/// layout, not anything a creator said.
private func sampleTranscriptProject() -> ProjectFolder? {
    let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-transcript-preview-\(UUID().uuidString)")
    guard let folder = try? ProjectFolder.create(at: url, title: "Transcript preview") else { return nil }
    let duration = 40.0
    var pieces: [TranscriptDraft.DraftItem] = []
    var time = 0.6
    func say(_ sentence: String) {
        for word in sentence.split(separator: " ") {
            pieces.append(.word(.init(text: String(word), start: time, end: time + 0.28)))
            time += 0.32
        }
    }
    func pause(_ length: Double) {
        pieces.append(.silence(start: time, end: time + length))
        time += length
    }
    pause(0.5)
    say("This is placeholder text for checking how the transcript lays out in the inspector.")
    pause(1.4)
    say("A second sentence follows a pause long enough to show a chip after it.")
    pause(0.3)
    say("Here the window changes while the same app stays in front.")
    pause(6.2)
    say("After a long silence the words start a new paragraph.")
    pause(0.4)
    say("Then another app comes to the front and the rail shows its icon.")
    pause(max(0.1, duration - time))
    let draft = TranscriptDraft(engine: "preview", silenceDetector: "preview", language: "en", audioDuration: duration, items: pieces)
    do {
        try folder.updateProject { project in
            var source = project.addSource(name: "Screen recording", origin: .recorded, tracks: [
                SourceTrack(kind: .microphone, file: .inProject("recordings/none.wav"),
                            media: MediaInfo(duration: duration, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
            ])
            source.screenLog = "preview"
            project.sources[project.sources.count - 1] = source
        }
        _ = try folder.addTranscript(draft, for: SourceID(number: 1))
        var events: [ScreenLog.Event] = []
        func front(_ t: Double, _ type: ScreenLog.EventType, _ app: String?, _ bundleID: String?, _ window: String) {
            var event = ScreenLog.Event(t: t, type: type)
            event.app = app
            event.bundleID = bundleID
            event.window = window
            events.append(event)
        }
        front(0, .app, "Xcode", "com.apple.dt.Xcode", "EditorView.swift")
        front(9.5, .window, nil, nil, "TranscriptTextView.swift")
        front(28, .app, "Safari", "com.apple.Safari", "Documentation")
        try FileManager.default.createDirectory(at: folder.url(for: .screen), withIntermediateDirectories: true)
        var data = Data()
        for event in events { data.append(try ScreenLog.line(event)) }
        try data.write(to: ScreenLog.eventsURL("preview", in: folder.url))
        let project = try folder.loadProject()
        try folder.updateEdit(author: .system("Preview"), reason: "Whole take") { edit in
            if let source = project.sources.first { _ = edit.addWholeSource(source) }
        }
        return folder
    } catch {
        return nil
    }
}

#Preview("The transcript", traits: .fixedLayout(width: 300, height: 760)) {
    if let folder = sampleTranscriptProject() {
        let model = EditorModel(folder: folder)
        let _ = model.loadForPreview(playhead: 2)
        InspectorView(model: model).environment(AppModel())
    } else {
        Text("Couldn't make the sample project")
    }
}
#endif

#if DEBUG
/// A project made on the spot for the Layout section's previews: a screen and a camera track with no media
/// behind them, set up with a layout, as one whole clip.
private func sampleLayoutProject(_ layout: TakeLayout, destination: VideoFormat.Destination = .landscape) -> (folder: ProjectFolder, clip: ClipID)? {
    let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-layout-preview-\(UUID().uuidString)")
    guard let folder = try? ProjectFolder.create(at: url, title: "Layout preview") else { return nil }
    let shape = layout.captureRatio(for: destination)
    do {
        let project = try folder.updateProject { project in
            project.format = VideoFormat(destination: destination, layout: layout)
            project.addSource(name: "Screen recording", origin: .recorded, tracks: [
                SourceTrack(kind: .screen, file: .inProject("recordings/none-screen.mov"),
                            media: MediaInfo(duration: 20, video: .init(width: Int(2160 * shape.aspect), height: 2160, frameRate: 60, captureRate: 60, codec: "hvc1"))),
                SourceTrack(kind: .camera, file: .inProject("recordings/none-camera.mov"),
                            media: MediaInfo(duration: 20, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
            ], layout: layout)
        }
        var clip: ClipID?
        try folder.updateEdit(author: .system("Preview"), reason: "Whole take") { edit in
            if let source = project.sources.first { clip = edit.addWholeSource(source)?.id }
        }
        return clip.map { (folder, $0) }
    } catch {
        return nil
    }
}

private struct LayoutSectionPreview: View {
    let layout: TakeLayout
    var destination = VideoFormat.Destination.landscape

    var body: some View {
        if let sample = sampleLayoutProject(layout, destination: destination) {
            let model = EditorModel(folder: sample.folder)
            let _ = model.loadForPreview(selecting: sample.clip)
            InspectorView(model: model).environment(AppModel()).preferredColorScheme(.dark)
        } else {
            Text("Couldn't make the sample project")
        }
    }
}

#Preview("Layout · card, smaller", traits: .fixedLayout(width: 300, height: 560)) { LayoutSectionPreview(layout: .card(.standard)) }
#Preview("Layout · card, full, bubble", traits: .fixedLayout(width: 300, height: 560)) { LayoutSectionPreview(layout: .card(.bubble)) }
#Preview("Layout · side by side", traits: .fixedLayout(width: 300, height: 560)) { LayoutSectionPreview(layout: .sideBySide(.thirtyTwoByTwentySeven)) }
#Preview("Layout · a Short's card", traits: .fixedLayout(width: 300, height: 600)) { LayoutSectionPreview(layout: .card(.bubble), destination: .vertical) }
#endif
