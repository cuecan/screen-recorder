import Foundation

/// Where the creator is looking in the app's editor: the playhead, the selection and the marked range
/// (docs/decisions.md, 57). It's saved so `get_editor_state` lets "cut here" or "tighten what I selected"
/// work without the creator reading out timecodes.
///
/// It isn't part of the edit and isn't snapshotted: it's `editor-state.json` in the project folder,
/// rewritten as the creator moves around.
public struct EditorState: Codable, Equatable, Sendable {
    /// What's selected.
    public struct Selection: Codable, Equatable, Sendable {
        /// Main-track clips.
        public var clips: [ClipID]
        /// Overlays.
        public var overlays: [ClipID]
        /// A freeze's band.
        public var freezes: [FreezeID]
        /// A run of words in the words lane.
        public var words: ItemRange?

        public init(clips: [ClipID] = [], overlays: [ClipID] = [], freezes: [FreezeID] = [], words: ItemRange? = nil) {
            self.clips = clips
            self.overlays = overlays
            self.freezes = freezes
            self.words = words
        }

        public var isEmpty: Bool { clips.isEmpty && overlays.isEmpty && freezes.isEmpty && words == nil }
    }

    public static let fileName = "editor-state.json"

    /// The playhead, in seconds of the edited timeline.
    public var playhead: TimeInterval
    public var selection: Selection
    /// A range marked with I and O, on the edited timeline.
    public var markIn: TimeInterval?
    public var markOut: TimeInterval?
    /// Markers added with M, on the edited timeline.
    public var markers: [TimeInterval]
    /// Which shape the editor shows, for a take made for both: the 16:9 video or the 9:16 Short
    /// (docs/decisions.md, 77). Nil is the format's first. It's what the sidebar's thumbnail shows too.
    public var shape: OutputShape?
    /// Which edit the times are on: they shift when the edit changes.
    public var editRevision: Int
    public var updatedAt: Date

    public init(
        playhead: TimeInterval = 0,
        selection: Selection = Selection(),
        markIn: TimeInterval? = nil,
        markOut: TimeInterval? = nil,
        markers: [TimeInterval] = [],
        shape: OutputShape? = nil,
        editRevision: Int = 0,
        updatedAt: Date = .now
    ) {
        self.playhead = playhead
        self.selection = selection
        self.markIn = markIn
        self.markOut = markOut
        self.markers = markers
        self.shape = shape
        self.editRevision = editRevision
        self.updatedAt = updatedAt
    }

    /// The marked range, once both ends are set and in order.
    public var markedRange: TimeRange? {
        guard let markIn, let markOut, markOut > markIn else { return nil }
        return TimeRange(start: markIn, end: markOut)
    }
}

extension ProjectFolder {
    public var editorStateURL: URL { url.appending(path: EditorState.fileName) }

    /// What the app last saved of the editor's state, or nil if the project hasn't been open in the editor.
    public func loadEditorState() throws(ProjectFolderError) -> EditorState? {
        guard FileManager.default.fileExists(atPath: editorStateURL.path(percentEncoded: false)) else { return nil }
        return try read(editorStateURL)
    }

    /// Saves the editor's state. It's one file replaced in one step, with no history, so it needs no lock.
    public func saveEditorState(_ state: EditorState) throws(ProjectFolderError) {
        try write(state, to: editorStateURL)
    }
}
