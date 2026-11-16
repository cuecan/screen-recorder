import Foundation
import Testing
@testable import ProjectKit

@Suite struct ProjectLibraryNamingTests {
    @Test(arguments: [-8, 9]) func folderDateUsesTheCreatorsTimeZone(hoursFromGMT: Int) throws {
        let root = URL.temporaryDirectory.appending(path: "cuecan-naming-\(UUID().uuidString)")
        let library = ProjectLibrary(projectsFolder: root, recentsFile: root.appending(path: "recents.json"))
        let date = try Date.ISO8601FormatStyle().parse("2026-11-09T02:00:00Z")
        let zone = try #require(TimeZone(secondsFromGMT: hoursFromGMT * 3600))
        let url = library.newProjectURL(title: "Screen recording 6.00 PM", date: date, timeZone: zone)
        let expectedDay = hoursFromGMT < 0 ? "2026-11-08" : "2026-11-09"
        #expect(url.lastPathComponent == "\(expectedDay) Screen recording 6.00 PM")
    }
}
