import Foundation
import Testing
@testable import ProjectKit

/// The two kinds of layout and what each format offers (docs/decisions.md, 89).
struct TakeLayoutTests {
    @Test func theSharedLayoutButtonDependsOnTheKindRatherThanEveryCardParameter() {
        #expect(LayoutChoice.shared(in: [.card(Card(position: .left)), .card(Card(position: .bottomRight, size: .large))]) == .card)
        #expect(LayoutChoice.shared(in: [.camera, .camera]) == .camera)
        #expect(LayoutChoice.shared(in: [.sideBySide, .sideBySide]) == .sideBySide)
        #expect(LayoutChoice.shared(in: [.card(.standard), .screen]) == nil)
        #expect(LayoutChoice.shared(in: []) == nil)
    }

    @Test func sideBySideOffersAQuarterAThirdAndAHalfAndBothOnlyTheShapesThatFitBothOutputs() {
        #expect(TakeLayout.shares(for: .landscape).map(\.rawValue) == ["4:3", "32:27", "8:9"])
        #expect(TakeLayout.shares(for: .vertical).map(\.rawValue) == ["3:4", "27:32", "9:8"])
        #expect(TakeLayout.shares(for: .both).map(\.rawValue) == ["9:8", "1:1"])
        #expect(TakeLayout.shares(for: .landscape).map { TakeLayout.shareLabel($0, for: .landscape) } == ["¼", "⅓", "½"])
        #expect(TakeLayout.shares(for: .both).map { TakeLayout.shareLabel($0, for: .both) } == ["Wide", "Square"])
    }

    @Test func aShareIsTheCamerasPartOfTheFrame() {
        // The screen fills the video's height, so the camera's share of the width is what's left.
        for (shape, share) in zip(TakeLayout.shares(for: .landscape), [0.25, 1.0 / 3, 0.5]) {
            #expect(abs(1 - shape.aspect * 9 / 16 - share) < 0.001)
        }
        // And a Short's width, so the camera's share of the height is what's left.
        for (shape, share) in zip(TakeLayout.shares(for: .vertical), [0.25, 1.0 / 3, 0.5]) {
            #expect(abs(1 - (9.0 / 16) / shape.aspect - share) < 0.001)
        }
        // Both's shapes keep the screen about half of each output or more.
        for shape in TakeLayout.shares(for: .both) {
            #expect(1 - shape.aspect * 9 / 16 <= 0.5 && 1 - (9.0 / 16) / shape.aspect <= 0.5)
        }
    }

    @Test func aCardRecordsTheWholeFrameAndBothHasNone() {
        #expect(TakeLayout.card(.standard).captureRatio(for: .landscape) == .sixteenByNine)
        #expect(TakeLayout.card(.bubble).captureRatio(for: .vertical) == .nineBySixteen)
        #expect(TakeLayout.sideBySide(.fourByThree).captureRatio(for: .landscape) == .fourByThree)
        #expect(!TakeLayout.card(.standard).isOffered(for: .both))
        #expect(TakeLayout.card(.standard).isOffered(for: .landscape))
        #expect(!TakeLayout.sideBySide(.fourByThree).isOffered(for: .vertical))
    }

    @Test func aShortsCardIsAlwaysOverTheWholeScreen() {
        #expect(!TakeLayout.card(Card(screen: .smaller)).isOffered(for: .vertical))
        #expect(Card(screen: .smaller).fitted(to: .vertical).screen == .full)
        #expect(Card(screen: .smaller).fitted(to: .landscape).screen == .smaller)
        #expect(TakeLayout.standard(for: .vertical).isOffered(for: .vertical))
    }

    @Test func aFormatFallsBackToItsStandardLayoutAndNamesIt() {
        #expect(VideoFormat(destination: .both, layout: .card(.standard)).layout == .sideBySide(.nineByEight))
        #expect(VideoFormat(destination: .landscape, layout: .sideBySide(.thirtyTwoByTwentySeven)).label == "16:9 · Side by side ⅓")
        #expect(VideoFormat(destination: .both).label == "16:9 & 9:16 · Side by side")
        #expect(VideoFormat(destination: .landscape).label == "16:9 · Card")
        #expect(VideoFormat(destination: .landscape).captureRatio == .sixteenByNine)
    }

    @Test func layoutsRoundTripFlatWithAKind() throws {
        let card = Card(position: .bottomRight, size: .small, shape: .square, screen: .full)
        let layouts: [Layout] = [.automatic, .sideBySide, .card(card), .camera, .screen]
        for layout in layouts {
            #expect(try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(layout)) == layout)
        }
        let json = try #require(String(data: try JSONEncoder().encode(Layout.card(card)), encoding: .utf8))
        #expect(json.contains(#""kind":"card""#) && json.contains(#""position":"bottomRight""#) && json.contains(#""roundness":0.3"#))
        for take in [TakeLayout.sideBySide(.fourByThree), .card(card)] {
            #expect(try JSONDecoder().decode(TakeLayout.self, from: JSONEncoder().encode(take)) == take)
        }
    }

    @Test func aCardsRoundnessStaysInRangeAndFollowsItsShapeAtFirst() {
        #expect(Card(shape: .square).roundness == 0.3)
        #expect(Card(shape: .tall).roundness == 0.12)
        #expect(Card(roundness: 0.9).roundness == 0.5)
        #expect(Card(roundness: -1).roundness == 0)
        var card = Card()
        card.roundness = 0.257
        #expect(card.roundness == 0.26)
        #expect(Card(roundness: 0.4).shaped(.square).roundness == 0.3)
    }

    @Test func aCardsPositionIsAThreeByThreeGrid() {
        #expect(Card.Position.allCases.count == 9)
        #expect(Card.Position.topRight.column == 2 && Card.Position.topRight.row == 0)
        #expect(Card.Position.bottom.column == 1 && Card.Position.bottom.row == 2)
        #expect(Card.Position.center.column == 1 && Card.Position.center.row == 1)
    }

    // MARK: - The editor's buttons

    @Test func aTakeWithNoRoomBesideTheScreenIsNotOfferedSideBySide() {
        #expect(LayoutChoice.offered(of: .landscape, hasScreen: true, hasCamera: true, hasRoom: false) == [.card, .camera, .screen])
        #expect(LayoutChoice.offered(of: .landscape, hasScreen: true, hasCamera: true, hasRoom: true) == [.sideBySide, .card, .camera, .screen])
        #expect(LayoutChoice.offered(of: .both, hasScreen: true, hasCamera: true, hasRoom: true) == [.sideBySide, .camera, .screen])
        #expect(LayoutChoice.offered(of: .landscape, hasScreen: false, hasCamera: true, hasRoom: false) == [.camera])
        #expect(LayoutChoice.offered(of: .landscape, hasScreen: true, hasCamera: false, hasRoom: false) == [.screen])
    }

    @Test func roomBesideTheScreenIsJudgedByItsShape() {
        #expect(!Layout.hasRoom(besideScreen: 16.0 / 9, in: .landscape))
        #expect(Layout.hasRoom(besideScreen: 4.0 / 3, in: .landscape))
        #expect(!Layout.hasRoom(besideScreen: 9.0 / 16, in: .vertical))
        #expect(Layout.hasRoom(besideScreen: 3.0 / 4, in: .vertical))
        #expect(Layout.hasRoom(besideScreen: 9.0 / 8, in: .landscape) && Layout.hasRoom(besideScreen: 9.0 / 8, in: .vertical))
    }

    @Test func theCardButtonKeepsTheClipsCardThenTheTakesThenTheStandardOne() {
        let own = Card(position: .topLeft, size: .large, shape: .wide, screen: .full)
        let takes = Card(position: .bottomRight, size: .small, shape: .square, screen: .full)
        #expect(LayoutChoice.card.layout(current: .card(own), recorded: .card(takes), destination: .landscape) == .card(own))
        #expect(LayoutChoice.card.layout(current: .camera, recorded: .card(takes), destination: .landscape) == .card(takes))
        #expect(LayoutChoice.card.layout(current: .sideBySide, recorded: .sideBySide(.fourByThree), destination: .landscape) == .card(.standard))
        #expect(LayoutChoice.card.layout(current: nil, recorded: nil, destination: .vertical) == .card(.bubble))
        #expect(LayoutChoice.sideBySide.matches(.sideBySide) && LayoutChoice.card.matches(.card(own)) && !LayoutChoice.card.matches(.camera))
    }

    @Test func settingATakesOwnLayoutStoresAutomatic() throws {
        var edit = Edit(main: [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 5)])
        try edit.setLayout(.card(.standard), for: ClipID(number: 1), recorded: .card(.standard))
        #expect(edit.main[0].layout == .automatic)
        try edit.setLayout(.card(.bubble), for: ClipID(number: 1), recorded: .card(.standard))
        #expect(edit.main[0].layout == .card(.bubble))
        try edit.setLayout(.sideBySide, for: ClipID(number: 1), recorded: .sideBySide(.fourByThree))
        #expect(edit.main[0].layout == .automatic)
    }

    @Test func theCamerasSideIsNamedAsEachShapeShowsIt() {
        #expect(OutputLook.CameraSide.standard.label(in: .landscape) == "Right")
        #expect(OutputLook.CameraSide.flipped.label(in: .vertical) == "Below")
        #expect(OutputLook.CameraSide(name: "above", in: .vertical) == .standard)
        #expect(OutputLook.CameraSide(name: "left", in: .landscape) == .flipped)
        #expect(OutputLook.CameraSide(name: "sideways", in: .landscape) == nil)
    }
}
