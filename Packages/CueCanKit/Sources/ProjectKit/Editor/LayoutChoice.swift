import Foundation

/// One of the editor's layout buttons (docs/decisions.md, 89): Side by side, Card, Camera or Screen.
public enum LayoutChoice: Hashable, Sendable, CaseIterable {
    case sideBySide, card, camera, screen

    /// The layouts a clip can take, for the pictures its take has.
    ///
    /// - Parameters:
    ///   - hasRoom: Whether the take was recorded with room beside the screen. Without it Side by side isn't
    ///     offered: it would need bars around the screen, or cropping it.
    public static func offered(of destination: VideoFormat.Destination, hasScreen: Bool, hasCamera: Bool, hasRoom: Bool) -> [LayoutChoice] {
        var choices: [LayoutChoice] = []
        if hasScreen, hasCamera {
            if hasRoom { choices.append(.sideBySide) }
            // Both has no card: a clip has one layout for both shapes, and a card is a 16:9 or a 9:16 thing.
            if TakeLayout.offersCard(destination) { choices.append(.card) }
        }
        if hasCamera { choices.append(.camera) }
        if hasScreen { choices.append(.screen) }
        return choices
    }

    /// The layout a button picks. Card keeps the clip's own card, else the one the take was set up with, else
    /// the format's standard one.
    public func layout(current: Layout?, recorded: TakeLayout?, destination: VideoFormat.Destination) -> Layout {
        switch self {
        case .sideBySide: .sideBySide
        case .camera: .camera
        case .screen: .screen
        case .card: .card((current?.card ?? recorded?.card ?? Card.standard(for: destination)).fitted(to: destination))
        }
    }

    /// Whether a concrete layout is this button's.
    public func matches(_ layout: Layout?) -> Bool {
        switch (self, layout) {
        case (.sideBySide, .sideBySide), (.card, .card), (.camera, .camera), (.screen, .screen): true
        default: false
        }
    }

    /// The shared layout button even when its parameters differ, such as two cards in different places.
    public static func shared(in layouts: [Layout]) -> LayoutChoice? {
        guard !layouts.isEmpty else { return nil }
        return allCases.first { choice in layouts.allSatisfy { choice.matches($0) } }
    }

    public var name: String {
        switch self {
        case .sideBySide: "Side by side"
        case .card: "Card"
        case .camera: "Camera"
        case .screen: "Screen"
        }
    }
}
