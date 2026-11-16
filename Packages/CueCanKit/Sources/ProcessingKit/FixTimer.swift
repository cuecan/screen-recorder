import AudioKit
import Foundation
import ProjectKit
import TranscribeKit

/// Times a fix to the transcript against the source's audio (docs/decisions.md, 69), for `set_word_text`
/// and the app's Fix Text…, which runs it through `cuecan --machine align`.
///
/// It loads the CTC model once; use one timer from one task at a time.
public final class FixTimer {
    private let aligner = CTCWordAligner()

    public init() {}

    /// The fix's words with their times, or nil when the text didn't match what was said well enough.
    ///
    /// The fix is aligned together with up to ``CTCWordAligner/context`` seconds of the transcript's words
    /// either side, which the model reads it better with; only the fix's own words are judged and kept.
    public func timings(for range: ItemRange, as text: String, in folder: ProjectFolder) async throws -> [AlignedWord]? {
        let (track, window) = try folder.withLock {
            let transcript = try folder.loadTranscripts().transcript(containing: range)
            guard let track = try folder.loadProject().source(transcript.source)?.primaryAudioTrack else {
                throw ProcessingError.noAudio(transcript.source)
            }
            return (track, try FixAlignmentContext(transcript: transcript, replacing: range, text: text,
                audioRange: TimeRange(start: track.startOffset, end: track.startOffset + track.media.duration),
                context: CTCWordAligner.context, padding: CTCWordAligner.padding))
        }
        guard let window else { return nil }

        let url = track.file.url(relativeTo: folder.url)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ProcessingError.missingFile(url) }
        // The transcript is in source time; the file starts at the track's offset in it.
        let audio = try await AudioFileReader.readMono(url, sampleRate: 16_000,
                                                       timeRange: window.fileRange)
        guard let result = try await aligner.align(window.text, in: audio, startsAt: window.sourceRange.start),
              result.words.count >= window.correctedWords.upperBound, result.matches(window.correctedWords) else { return nil }
        return Array(result.words[window.correctedWords])
    }
}
