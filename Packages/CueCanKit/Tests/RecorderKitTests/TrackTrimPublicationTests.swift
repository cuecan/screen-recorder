import Foundation
import Testing
@testable import RecorderKit

struct TrackTrimPublicationTests {
    @Test func successfulPublicationKeepsOnlyTheCutsAtTheirOriginalNames() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-published-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "screen.mov"), copy = folder.appending(path: "cut-screen.mov")
        try Data("original".utf8).write(to: original)
        try Data("cut".utf8).write(to: copy)
        try TrackTrimPublication.replace([(original, copy)])
        #expect(try Data(contentsOf: original) == Data("cut".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["screen.mov"])
    }

    @Test func aBackupFailureLeavesOriginalsUntouchedAndCleansTheStagedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-backup-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appending(path: "screen.mov"), copy = folder.appending(path: "cut-screen.mov")
        let missing = folder.appending(path: "missing.mov"), secondCopy = folder.appending(path: "cut-missing.mov")
        try Data("original".utf8).write(to: original)
        try Data("cut".utf8).write(to: copy)
        try Data("second cut".utf8).write(to: secondCopy)
        var published = false
        #expect(throws: (any Error).self) {
            try TrackTrimPublication.replace([(original, copy), (missing, secondCopy)], publish: { _, _ in published = true })
        }
        #expect(!published)
        #expect(try Data(contentsOf: original) == Data("original".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["screen.mov"])
    }

    @Test(arguments: [0, 1, 2])
    func aReplacementFailureRestoresEveryOriginal(failingAt: Int) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-publication-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try ["screen", "camera", "microphone"].map { name in
            let original = folder.appending(path: name)
            let copy = folder.appending(path: "cut-\(name)")
            try Data("original \(name)".utf8).write(to: original)
            try Data("cut \(name)".utf8).write(to: copy)
            return (original: original, copy: copy)
        }
        var replaced = 0
        #expect(throws: CocoaError.self) {
            try TrackTrimPublication.replace(files, publish: { original, copy in
                if replaced == failingAt {
                    // A replacement is allowed to move its original before failing.
                    try FileManager.default.removeItem(at: original)
                    throw CocoaError(.fileWriteNoPermission)
                }
                _ = try FileManager.default.replaceItemAt(original, withItemAt: copy)
                replaced += 1
            })
        }
        #expect(replaced == failingAt)
        for file in files {
            #expect(try Data(contentsOf: file.original) == Data("original \(file.original.lastPathComponent)".utf8))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["camera", "microphone", "screen"])
    }

    @Test func aRestorationThatConsumesItsInputStillLeavesTheOriginalRecoveryCopy() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "cuecan-trim-recovery-\(UUID())")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let files = try ["screen", "camera"].map { name in
            let original = folder.appending(path: name), copy = folder.appending(path: "cut-\(name)")
            try Data("original \(name)".utf8).write(to: original)
            try Data("cut \(name)".utf8).write(to: copy)
            return (original: original, copy: copy)
        }
        var published = 0
        do {
            try TrackTrimPublication.replace(files, restore: { original, copy in
                if original.lastPathComponent == "screen" {
                    // Foundation may move either file before throwing. Consume both to prove that
                    // restoration never hands it the only recovery copy.
                    try manager.removeItem(at: original)
                    try manager.removeItem(at: copy)
                    throw CocoaError(.fileWriteUnknown)
                }
                _ = try manager.replaceItemAt(original, withItemAt: copy)
            }, publish: { original, copy in
                if published == 1 { throw CocoaError(.fileWriteNoPermission) }
                _ = try manager.replaceItemAt(original, withItemAt: copy)
                published += 1
            })
            Issue.record("The failed restoration must be reported.")
        } catch let failure as TrackTrimPublication.RestorationFailure {
            #expect(failure.files == [files[0].original])
            #expect(failure.localizedDescription.contains(folder.path))
        }
        let names = try manager.contentsOfDirectory(atPath: folder.path)
        let backups = names.filter { $0.hasPrefix("untrimmed-") }
        #expect(backups.count == 2, "Keep every recovery copy when the group cannot be restored.")
        let recovered = try backups.map { String(decoding: try Data(contentsOf: folder.appending(path: $0)), as: UTF8.self) }
        #expect(Set(recovered) == ["original screen", "original camera"])
        #expect(try Data(contentsOf: files[1].original) == Data("original camera".utf8))
        #expect(names.allSatisfy { !$0.hasPrefix("cut-") && !$0.hasPrefix("restoring-") })
    }
}
