import ProjectKit

/// Every layout a format can be set up with, for tests that sweep them: each Side by side share, and a card
/// in every position, shape and screen at each size.
func takeLayouts(for destination: VideoFormat.Destination) -> [TakeLayout] {
    var layouts = TakeLayout.shares(for: destination).map(TakeLayout.sideBySide)
    guard TakeLayout.offersCard(destination) else { return layouts }
    for position in Card.Position.allCases {
        for shape in Card.Shape.allCases {
            for size in Card.Size.allCases {
                for screen in Card.Screen.allCases {
                    let card = Card(position: position, size: size, shape: shape, screen: screen).fitted(to: destination)
                    if !layouts.contains(.card(card)) { layouts.append(.card(card)) }
                }
            }
        }
    }
    return layouts
}
