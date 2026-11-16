import Foundation
import Testing
@testable import ProjectKit

struct EditAuthorTests {
    @Test func rolesRoundTripWithoutInferringThemFromNames() throws {
        let authors: [EditAuthor] = [.app, .agent("app"), .commandLine("Claude"), .system("cuecan")]
        #expect(try JSONDecoder().decode([EditAuthor].self, from: JSONEncoder().encode(authors)) == authors)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(EditAuthor.self, from: Data("\"app\"".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(EditAuthor.self, from: Data("{\"role\":\"agent\"}".utf8)) }
    }

    @Test func oldProjectsAreRejectedBeforeTheirJournalIsTouched() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-old-format-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Old")
        var project = try folder.loadProject()
        project.formatVersion = 1
        try folder.write(project, to: folder.projectFileURL)
        let pending = folder.url.appending(path: ".pending-mutation.json")
        let bytes = Data("obsolete journal".utf8)
        try bytes.write(to: pending)
        #expect(throws: ProjectFolderError.olderFormat(folder.projectFileURL, 1)) { try ProjectFolder(opening: folder.url) }
        #expect(try Data(contentsOf: pending) == bytes)
    }
}
