import ProjectKit

/// Opening a take produces either its folder or an actionable failure, never both.
enum ProjectOpenState {
    case opening
    case opened(ProjectFolder)
    case failed(String)
}
