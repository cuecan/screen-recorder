import Foundation
import ProjectKit
import Testing
@testable import RecorderKit

/// A setup opens on what was used last (docs/decisions.md, 78).
@Suite struct SetupMemoryTests {
    @Test func theFirstSetupEverHasNoFormat() {
        let memory = SetupMemory()
        #expect(memory.format == nil)
        #expect(memory.layout(for: .landscape) == TakeLayout.standard(for: .landscape))
    }

    @Test func aSetupOpensOnTheLastFormatWithItsLayout() throws {
        var memory = SetupMemory()
        let card = TakeLayout.card(Card(position: .topLeft, size: .large, shape: .wide, screen: .full))
        memory.use(card, for: .landscape)
        memory.use(.vertical)
        memory.use(.landscape)
        #expect(memory.format == VideoFormat(destination: .landscape, layout: card))

        let data = try JSONEncoder().encode(memory)
        let read = try JSONDecoder().decode(SetupMemory.self, from: data)
        #expect(read == memory)
        #expect(read.format?.layout == card)
        #expect(read.layout(for: .vertical) == TakeLayout.standard(for: .vertical), "A format with no layout picked starts on its standard one.")
    }

    @Test func switchingKindsBringsBackWhatEachWasSetTo() {
        var memory = SetupMemory()
        let card = Card(position: .bottomLeft, size: .small, shape: .square, screen: .full)
        memory.use(.card(card), for: .landscape)
        memory.use(.sideBySide(.eightByNine), for: .landscape)
        #expect(memory.layout(for: .landscape) == .sideBySide(.eightByNine))
        #expect(memory.card(for: .landscape) == card)
        #expect(memory.sideBySide(for: .landscape) == .sideBySide(.eightByNine))
        #expect(memory.sideBySide(for: .vertical) == .sideBySide(.twentySevenByThirtyTwo), "A third, until one is picked.")
        #expect(memory.card(for: .vertical) == .bubble)
    }

    @Test func aLayoutTheFormatDoesntOfferIsIgnored() {
        var memory = SetupMemory()
        memory.use(.card(.standard), for: .both)
        #expect(memory.layouts.isEmpty && memory.cards.isEmpty)
        let fromElsewhere = SetupMemory(destination: .both, layouts: [.both: .card(.standard)])
        #expect(fromElsewhere.layouts.isEmpty)
        #expect(fromElsewhere.format?.layout == TakeLayout.standard(for: .both))
    }

    @Test func anUnknownFormatDoesntRead() {
        let json = Data(#"{"destination":"square","layouts":{},"cards":{},"shares":{}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SetupMemory.self, from: json) }
    }
}
