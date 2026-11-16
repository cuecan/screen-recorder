import AppKit
import Foundation
import ProjectKit

/// The transcript in the inspector (docs/ui.md, "The transcript in the inspector"; docs/decisions.md, 69):
/// cutting by deleting words, putting cut words back, and fixing what it says.
extension EditorModel {
    /// The transcript laid out for the inspector, in its mode, from the files as last loaded.
    func makeReading() -> TranscriptReading? {
        guard let edit, let project else { return nil }
        var texts: [SourceID: [WordID: String]] = [:]
        for (source, transcript) in transcripts.transcripts {
            texts[source] = edit.exportTexts(of: transcript, spellings: spellings[source])
        }
        return TranscriptReading(mode: transcriptMode, placements: edit.placements,
                                 sources: project.sources.map(\.id), transcripts: transcripts, texts: texts, fronts: screenFronts)
    }

    /// Delete on picked words or silences: cuts them, each run where the edit plays it (`cut`).
    func cutTranscript(_ ranges: [ItemRange]) {
        guard !ranges.isEmpty else { return NSSound.beep() }
        let name = ranges.count == 1 ? ranges[0].description : "\(ranges.count) runs of words"
        change("Cut \(name)") { edit, transcripts in
            for range in ranges { _ = try edit.cut(range, transcripts: transcripts, byHand: true) }
        }
    }

    /// Put Back, on cut words in Full (`keep`).
    func putBack(_ ranges: [ItemRange]) {
        guard !ranges.isEmpty else { return NSSound.beep() }
        let name = ranges.count == 1 ? ranges[0].description : "\(ranges.count) runs of words"
        change("Put back \(name)") { edit, transcripts in
            for range in ranges { _ = try edit.keep(range, transcripts: transcripts, byHand: true) }
        }
    }

    /// Play from Here.
    func play(from time: TimeInterval) {
        seek(to: time)
        if !isPlaying { togglePlayback() }
    }

    /// Fix Text…: replaces the words with `text` at once in the transcript, times it against the audio in the
    /// bundled `cuecan` (the app can't load the model; docs/decisions.md, 47), then saves it as one change. A
    /// fix that can't be timed is saved untimed; only its help tag says so.
    func fixText(_ text: String, for range: ItemRange) {
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return NSSound.beep() }
        cancelFix()
        let request = fixing.begin(range, text: text)
        let folder = folder
        fixTask = Task { [weak self, alignFix] in
            let timings = await alignFix(text, range, folder.url)
            guard let self, !Task.isCancelled, self.fixing.contains(request) else { return }
            do {
                let (_, fix) = try folder.fixWords(range, as: text, timings: timings, author: .app, reason: "Fixed \(range) to “\(text)”")
                if selection.wordRange == range, let first = fix.words.first, let last = fix.words.last {
                    selection = .words(ItemRange(first: .word(first.id), last: .word(last.id)))
                }
                problem = nil
            } catch {
                problem = error.localizedDescription
                NSSound.beep()
            }
            await reload()
            fixing.finish(request)
        }
    }

    func cancelFix() {
        fixTask?.cancel()
        fixTask = nil
        fixing.cancel()
    }

    /// Times a fix in `cuecan --machine align`. Nil when it couldn't be, for whatever reason.
    nonisolated static func align(_ text: String, _ range: ItemRange, _ project: URL) async -> [AlignedWord]? {
        let arguments: [String: String] = [
            "project": project.path(percentEncoded: false),
            "start_id": range.first.description,
            "end_id": range.last.description,
            "text": text,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: arguments) else { return nil }
        do {
            let output = try await CommandRunner.run(executable: ProcessingCenter.cli,
                                                     arguments: ["--machine", "align", String(decoding: json, as: UTF8.self)])
            guard case .aligned(let words) = try HelperMessage.result(in: output), !words.isEmpty else { return nil }
            return words
        } catch {
            return nil
        }
    }
}
