import Foundation

/// Every tool, in the order they're listed.
enum ToolCatalog {
    static let all: [any EditorTool] = [
        ListProjectsTool(),
        GetTranscriptTool(),
        GetEditTool(),
        SetVocabularyTool(),
        AddClipTool(),
        CutTool(),
        KeepTool(),
        NudgeCutTool(),
        SplitClipTool(),
        RemoveSilencesTool(),
        PlaceBrollTool(),
        SetLayoutTool(),
        FreezeScreenTool(),
        SetSpeedTool(),
        SetClipSoundTool(),
        SetClipFramingTool(),
        SetCameraFramingTool(),
        SetLookTool(),
        SetCaptionsTool(),
        SetWordTextTool(),
        GetEditorStateTool(),
        GetScreenTimelineTool(),
        FindOnScreenTool(),
        PreviewFramesTool(),
        RenderTool(),
        ExportTimelineTool(),
        UndoTool(),
    ]

    static func tool(named name: String) -> (any EditorTool)? {
        all.first { $0.name == name }
    }
}
