/// The same two deliberate choices in the panel's HUD and the status item's menu.
enum DiscardAction: CaseIterable {
    case startOver, discard

    var title: String { self == .startOver ? "Start over" : "Discard" }
    var systemImage: String { self == .startOver ? "arrow.counterclockwise" : "trash" }
    var isDestructive: Bool { self == .discard }

    func perform(in recorder: RecorderModel) {
        Task {
            switch self {
            case .startOver: await recorder.startOver()
            case .discard: await recorder.discard()
            }
        }
    }
}
