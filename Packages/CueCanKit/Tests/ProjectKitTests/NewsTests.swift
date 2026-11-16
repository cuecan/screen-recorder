import Foundation
import Testing
@testable import ProjectKit

@Suite struct NewsTests {
    private func answer(_ json: String) -> Data { Data(json.utf8) }
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func readsAMessage() throws {
        let item = try #require(NewsItem(answer: answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com/x"}"#)))
        #expect(item.id == "a1")
        #expect(item.text == "Something new")
        #expect(item.link.absoluteString == "https://cuecan.com/x")
    }

    @Test func putsTheTextOnOneLine() throws {
        let item = try #require(NewsItem(answer: answer(#"{"id":"a1","text":"  Two\n lines\t here ","link":"https://cuecan.com"}"#)))
        #expect(item.text == "Two lines here")
    }

    @Test(arguments: [
        "{}",
        "",
        "not json",
        "[]",
        #"{"id":"a1","text":"No link"}"#,
        #"{"id":"","text":"No id","link":"https://cuecan.com"}"#,
        #"{"id":"a1","text":"   ","link":"https://cuecan.com"}"#,
        #"{"id":"a1","text":"Plain http","link":"http://cuecan.com"}"#,
        #"{"id":"a1","text":"A file","link":"file:///etc/hosts"}"#,
        #"{"id":"a1","text":"No host","link":"https://"}"#,
    ])
    func holdsNoMessage(json: String) {
        #expect(NewsItem(answer: answer(json)) == nil)
    }

    @Test func refusesTextThatIsTooLong() {
        let fits = String(repeating: "a", count: NewsItem.longestText)
        #expect(NewsItem(answer: answer(#"{"id":"a1","text":"\#(fits)","link":"https://cuecan.com"}"#)) != nil)
        #expect(NewsItem(answer: answer(#"{"id":"a1","text":"\#(fits)a","link":"https://cuecan.com"}"#)) == nil)
    }

    @Test func asksOnceADay() {
        var state = NewsState()
        #expect(state.isDue(at: now))
        state.answered(nil, at: now)
        #expect(!state.isDue(at: now.addingTimeInterval(NewsState.interval - 1)))
        #expect(state.isDue(at: now.addingTimeInterval(NewsState.interval)))
    }

    @Test func asksAgainWhenTheClockWentBack() {
        var state = NewsState()
        state.answered(nil, at: now)
        #expect(state.isDue(at: now.addingTimeInterval(-60)))
    }

    @Test func showsAMessageUntilItIsDismissed() {
        var state = NewsState()
        state.answered(answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com"}"#), at: now)
        #expect(state.visible?.id == "a1")
        state.dismiss()
        #expect(state.visible == nil)
        // The same message again stays gone; a new one shows.
        state.answered(answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com"}"#), at: now)
        #expect(state.visible == nil)
        state.answered(answer(#"{"id":"a2","text":"Something else","link":"https://cuecan.com"}"#), at: now)
        #expect(state.visible?.id == "a2")
    }

    @Test func anEmptyAnswerTakesTheMessageDown() {
        var state = NewsState()
        state.answered(answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com"}"#), at: now)
        state.answered(answer("{}"), at: now)
        #expect(state.visible == nil)
        state.answered(answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com"}"#), at: now)
        state.answered(nil, at: now)
        #expect(state.visible == nil)
    }

    @Test func survivesBeingSaved() throws {
        var state = NewsState()
        state.answered(answer(#"{"id":"a1","text":"Something new","link":"https://cuecan.com"}"#), at: now)
        state.dismiss()
        let saved = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(NewsState.self, from: saved) == state)
    }
}
