import Foundation
import Testing
@testable import ProjectKit

@Suite struct BetaExpiryTests {
    private func utc(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    @Test func endsNinetyDaysAfterTheBuild() throws {
        let expiry = try #require(BetaExpiry(builtOn: "2026-11-15"))
        #expect(BetaExpiry.days == 90)
        #expect(expiry.ends == (try utc("2027-02-13T00:00:00Z")))
        #expect(!expiry.hasEnded(at: try utc("2026-11-15T12:00:00Z")))
        #expect(!expiry.hasEnded(at: try utc("2027-02-12T23:59:59Z")))
        #expect(expiry.hasEnded(at: try utc("2027-02-13T00:00:00Z")))
        #expect(expiry.hasEnded(at: try utc("2028-01-01T00:00:00Z")))
    }

    @Test(arguments: [nil, "", "  ", "$(CUECAN_BUILT_ON)", "yesterday", "2026-13-40"] as [String?])
    func aBuildWithNoDayNeverEnds(builtOn: String?) {
        #expect(BetaExpiry(builtOn: builtOn) == nil)
    }

    @Test func ignoresSpacesAroundTheDay() {
        #expect(BetaExpiry(builtOn: " 2026-11-15 ") == BetaExpiry(builtOn: "2026-11-15"))
    }
}
