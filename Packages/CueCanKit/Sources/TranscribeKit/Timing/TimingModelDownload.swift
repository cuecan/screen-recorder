import AudioKit
import CoreML
import CryptoKit
import Foundation

/// Fetches and builds the timing model (``WordTimer``) the first time it's needed (docs/decisions.md, 95).
///
/// Everything comes from FluidInference's repository on Hugging Face, where Parakeet comes from too: their
/// 4-bit Core ML port of Nemotron 3.5 Transcribe's audio side, at one pinned revision. CueCan hosts nothing.
/// The one thing that port lacks is an output: its timing head returns only its best piece for each frame,
/// and placing known words needs every piece's probability, which the head works out one step earlier. So
/// the model's small description file is patched here (four edits, 85 bytes, checked by hash before and
/// after) to hand that table back as well, and the model is compiled on this Mac. The 388 MB of weights are
/// used exactly as published.
public enum TimingModelDownload {
    /// The repository and the revision every file is taken from, so nothing changes under a released app.
    static let repository = "FluidInference/nemotron-3.5-transcribe-lite-coreml"
    static let revision = "31ecb73ab8a541001c0952802b478384cf9f0691"
    static let package = "coreml/lite_ctc_p4.mlpackage"

    /// The published model description and what it becomes: sizes and SHA-256.
    static let descriptionByteCount = 645_297
    static let descriptionSHA256 = "2fe6d02c582c2242df000f6b7be6cdc8f2a65a3371433106b77d6af0721b827d"
    static let patchedSHA256 = "4e21a4a4817b1de9c93d1ba6972a81689cb600ba2df47fb5a71b424cd4afbc84"
    /// The weights, the bulk of the download.
    public static let weightsByteCount: Int64 = 388_149_678
    static let weightsSHA256 = "322578df1247c4830cb525e6d2ff75c8c7dfd433502d514f905a93d16f767600"

    /// One edit to the description: at `offset` in the published file, `drop` bytes go and `put` takes their place.
    struct Edit: Equatable {
        let offset: Int
        let drop: Int
        let put: [UInt8]
    }

    /// Adds `logp_cast_fp16`, a 16-bit float array of 1 × 750 × 23,863, to the model's outputs and to its main
    /// block's, and corrects the lengths of the messages around them. Made by
    /// `scripts/models/timing-model-patch.py`, which edits the protobuf in place.
    static let edits: [Edit] = [
        Edit(offset: 3, drop: 1, put: [0xe8]),
        Edit(offset: 331, drop: 19, put: hex("52200a0e6c6f67705f636173745f667031361a0e2a0c0a0601ee05b7ba0110908004b21ff1ae27080112ebae270a046d61696e12e1")),
        Edit(offset: 422, drop: 15, put: hex("98ae270a07436f72654d4c38128bae")),
        Edit(offset: 645_297, drop: 0, put: hex("120e6c6f67705f636173745f66703136")),
    ]

    private static func hex(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index..<next], radix: 16) ?? 0)
            index = next
        }
        return bytes
    }

    /// The data with the edits applied, in order of offset. Nil when an edit reaches past the data.
    static func applying(_ edits: [Edit], to data: Data) -> Data? {
        var result = Data(capacity: data.count + edits.reduce(0) { $0 + $1.put.count })
        var position = 0
        for edit in edits {
            guard edit.offset >= position, edit.offset + edit.drop <= data.count else { return nil }
            result.append(data[(data.startIndex + position)..<(data.startIndex + edit.offset)])
            result.append(contentsOf: edit.put)
            position = edit.offset + edit.drop
        }
        result.append(data[(data.startIndex + position)...])
        return result
    }

    static func address(of path: String) -> URL? {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")
    }

    /// Downloads, patches, compiles and installs the model into ``WordTimer/directory``, unless it's already
    /// there. `progress` gets the fraction downloaded, from 0 to 1.
    public static func install(to directory: URL = WordTimer.directory,
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if WordTimer.isInstalled(at: directory) {
            progress(1)
            return
        }
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let working = parent.appending(path: ".installing-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: working) }
        let sources = working.appending(path: "model.mlpackage/Data/com.apple.CoreML", directoryHint: .isDirectory)
        try manager.createDirectory(at: sources.appending(path: "weights"), withIntermediateDirectories: true)
        let result = working.appending(path: WordTimer.folderName, directoryHint: .isDirectory)
        try manager.createDirectory(at: result, withIntermediateDirectories: true)

        // The small files first: if the repository can't be reached, that's known before the long download.
        let published = try await small("\(package)/Data/com.apple.CoreML/model.mlmodel")
        guard published.count == descriptionByteCount, digest(of: published) == descriptionSHA256 else {
            throw failure("The model's description isn't the one this version of CueCan was made for.")
        }
        guard let patched = applying(edits, to: published), digest(of: patched) == patchedSHA256 else {
            throw failure("The model's description couldn't be prepared.")
        }
        try patched.write(to: sources.appending(path: "model.mlmodel"))
        try await small("\(package)/Manifest.json").write(to: working.appending(path: "model.mlpackage/Manifest.json"))
        for (path, name) in [("assets/vocab.json", "vocab.json"), ("assets/mel_window.bin", "mel_window.bin"),
                             ("assets/mel_filterbank.bin", "mel_filterbank.bin"), ("LICENSE", "LICENSE")] {
            try await small(path).write(to: result.appending(path: name))
        }

        guard let weights = address(of: "\(package)/Data/com.apple.CoreML/weights/weight.bin") else { throw failure("Its address is missing.") }
        let watcher = ProgressWatcher(expected: weightsByteCount, report: progress)
        let (downloaded, response) = try await URLSession.shared.download(from: weights, delegate: watcher)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw failure("The server answered \(http.statusCode).")
        }
        let weightsFile = sources.appending(path: "weights/weight.bin")
        try manager.moveItem(at: downloaded, to: weightsFile)
        guard try digest(of: weightsFile) == weightsSHA256 else { throw failure("The download didn't arrive whole.") }

        let compiled: URL
        do {
            compiled = try await MLModel.compileModel(at: working.appending(path: "model.mlpackage"))
        } catch {
            throw failure("It couldn't be prepared for this Mac: \(error.localizedDescription)")
        }
        try manager.moveItem(at: compiled, to: result.appending(path: "model.mlmodelc"))
        guard WordTimer.isInstalled(at: result) else { throw failure("The download is missing files.") }
        if manager.fileExists(atPath: directory.path(percentEncoded: false)) { try manager.removeItem(at: directory) }
        try manager.moveItem(at: result, to: directory)
        progress(1)
    }

    private static func small(_ path: String) async throws -> Data {
        guard let url = address(of: path) else { throw failure("Its address is missing.") }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw failure("The server answered \(http.statusCode) for \(path).")
        }
        return data
    }

    private static func failure(_ reason: String) -> AudioKitError {
        .modelFailed("Word timing", "Couldn't download the timing model. \(reason)")
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The file's SHA-256 as lowercase hex, read a piece at a time.
    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private final class ProgressWatcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let expected: Int64
        let report: @Sendable (Double) -> Void

        init(expected: Int64, report: @escaping @Sendable (Double) -> Void) {
            self.expected = expected
            self.report = report
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
            report(min(1, Double(totalBytesWritten) / Double(max(total, 1))))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
