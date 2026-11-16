import Foundation
import Testing
@testable import ProjectKit

@Suite struct IdentifierTests {
    @Test func formatsWithPrefix() {
        #expect(WordID(number: 104).description == "w_104")
        #expect(SilenceID(number: 12).description == "s_12")
        #expect(SourceID(number: 2).description == "src_2")
        #expect(ClipID(number: 3).description == "c_3")
    }

    @Test(arguments: ["w_0", "w_1", "w_104", "w_999999"])
    func parsesValidWordIDs(text: String) throws {
        let id = try #require(WordID(text))
        #expect(id.description == text)
    }

    @Test(arguments: ["", "w", "w_", "w_-1", "w_01", "w_1a", "W_1", "s_1", " w_1", "w_1 ", "src_1"])
    func rejectsInvalidWordIDs(text: String) {
        #expect(WordID(text) == nil)
    }

    @Test func itemIDsParseEitherKind() {
        #expect(TranscriptItemID("w_5") == .word(WordID(number: 5)))
        #expect(TranscriptItemID("s_5") == .silence(SilenceID(number: 5)))
        #expect(TranscriptItemID("src_5") == nil)
        #expect(TranscriptItemID("c_5") == nil)
    }

    @Test func idsEncodeAsStrings() throws {
        let ids = [w(1), s(2)]
        let json = try String(decoding: JSONEncoder().encode(ids), as: UTF8.self)
        #expect(json == #"["w_1","s_2"]"#)
        #expect(try JSONDecoder().decode([TranscriptItemID].self, from: Data(json.utf8)) == ids)
    }

    @Test func decodingAnInvalidIDFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WordID.self, from: Data(#""s_1""#.utf8))
        }
    }

    @Test func idsSortByNumber() {
        #expect([WordID(number: 10), WordID(number: 9)].sorted() == [WordID(number: 9), WordID(number: 10)])
    }
}
