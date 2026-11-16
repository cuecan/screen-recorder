import Foundation

/// Every transcript in a project, with the edit's fixes laid over them (docs/decisions.md, 69), for finding
/// which source a word or silence id belongs to.
///
/// This is the transcript everything reads: the editor, the tools, cutting and snapping, the SRT and the
/// text. The transcript files keep the model's output underneath.
public struct TranscriptIndex: Sendable {
    public let transcripts: [SourceID: Transcript]
    /// Words from a fix that couldn't be timed against the audio: each holds a whole fix and cuts as one.
    public let untimedWords: Set<WordID>
    private let sourceOfItem: [TranscriptItemID: SourceID]

    /// The transcripts with fixes laid over them in order. A fix whose words aren't there is skipped.
    public init(_ transcripts: [Transcript], fixes: [WordFix] = []) {
        var bySource: [SourceID: Transcript] = [:]
        for transcript in transcripts { bySource[transcript.source] = transcript }
        var untimed: Set<WordID> = []
        for fix in fixes {
            guard let source = bySource.first(where: { $0.value.contains(fix.replaces.first) })?.key,
                  let fixed = bySource[source]?.applying(fix)
            else { continue }
            bySource[source] = fixed
            if !fix.isTimed { untimed.formUnion(fix.words.map(\.id)) }
        }
        var sourceOfItem: [TranscriptItemID: SourceID] = [:]
        for transcript in bySource.values {
            for item in transcript.items { sourceOfItem[item.id] = transcript.source }
        }
        self.transcripts = bySource
        self.untimedWords = untimed.filter { sourceOfItem[.word($0)] != nil }
        self.sourceOfItem = sourceOfItem
    }

    public subscript(source: SourceID) -> Transcript? {
        transcripts[source]
    }

    /// The source an item is in, if it's in any.
    public func source(of item: TranscriptItemID) -> SourceID? {
        sourceOfItem[item]
    }

    /// The transcript that holds a whole range, checking that both ends are in the same one.
    public func transcript(containing range: ItemRange) throws(EditError) -> Transcript {
        guard let firstSource = sourceOfItem[range.first] else { throw .unknownItem(range.first) }
        guard let lastSource = sourceOfItem[range.last] else { throw .unknownItem(range.last) }
        guard firstSource == lastSource else { throw .rangeSpansSources(range) }
        guard let transcript = transcripts[firstSource] else { throw .unknownItem(range.first) }
        return transcript
    }
}
