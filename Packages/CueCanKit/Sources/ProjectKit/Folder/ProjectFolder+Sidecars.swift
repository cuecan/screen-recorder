import Foundation

/// Files that sit beside the transcripts and the mic recordings: vocabulary spellings and cleaned voices.
/// Neither is a change to the edit, so neither is snapshotted.
extension ProjectFolder {
    // MARK: - Vocabulary spellings

    /// Where a source's vocabulary spellings are stored, beside its transcript.
    public func spellingsURL(for source: SourceID) -> URL {
        url(for: .transcripts).appending(path: "\(source).spellings.json")
    }

    /// A source's vocabulary spellings, or nil if boosting hasn't run on it.
    public func loadSpellings(for source: SourceID) throws(ProjectFolderError) -> VocabularySpellings? {
        let fileURL = spellingsURL(for: source)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        return try read(fileURL)
    }

    /// Saves a source's vocabulary spellings, replacing any from earlier terms.
    public func saveSpellings(_ spellings: VocabularySpellings) throws {
        try withLock {
            guard try loadProject().source(spellings.source) != nil else { throw EditError.unknownSource(spellings.source) }
            try write(spellings, to: spellingsURL(for: spellings.source))
        }
    }

    /// A source's spellings, only if they were made with the project's current terms. Spellings from terms
    /// that have since changed or been cleared don't apply.
    public func currentSpellings(for source: SourceID, terms: [String]) throws(ProjectFolderError) -> VocabularySpellings? {
        guard !terms.isEmpty, let spellings = try loadSpellings(for: source), spellings.terms == terms else { return nil }
        return spellings
    }

    /// Removes every source's spellings, such as when the vocabulary is cleared.
    public func removeAllSpellings() throws {
        try withLock {
            for source in try loadProject().sources {
                let fileURL = spellingsURL(for: source.id)
                if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        throw ProjectFolderError.couldNotWrite(fileURL, error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - Cleaned audio

    /// Where the record of a source's cleaned voice is stored.
    public func cleanedAudioRecordURL(for source: SourceID, purpose: CleanedAudio.Purpose = .preview) -> URL {
        url(for: .audio).appending(path: "\(source)\(purpose == .handoff ? "-handoff" : "").json")
    }

    /// The record of a source's cleaned voice, if it has been cleaned.
    public func cleanedAudio(for source: SourceID, purpose: CleanedAudio.Purpose = .preview) throws(ProjectFolderError) -> CleanedAudio? {
        let fileURL = cleanedAudioRecordURL(for: source, purpose: purpose)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        return try read(fileURL)
    }

    /// The cleaned voice to play for a source, if one was made with exactly these settings from this track
    /// and its file is still there.
    public func cleanedAudioURL(for source: SourceID, settings: SourceAudioSettings, original: FileReference, purpose: CleanedAudio.Purpose = .preview) -> URL? {
        guard let record = try? cleanedAudio(for: source, purpose: purpose), record.settings == settings, record.original == original else {
            return nil
        }
        let fileURL = url(for: .audio).appending(path: record.file)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    /// The last cleaned voice made from this track, whatever its settings, if its file is still there: what the
    /// preview keeps playing while the voice is cleaned again with new ones.
    public func latestCleanedAudioURL(for source: SourceID, original: FileReference, purpose: CleanedAudio.Purpose = .preview) -> URL? {
        guard let record = try? cleanedAudio(for: source, purpose: purpose), record.original == original else { return nil }
        let fileURL = url(for: .audio).appending(path: record.file)
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) ? fileURL : nil
    }

    /// Records a cleaned voice whose file is already written in `audio/`.
    public func saveCleanedAudio(_ record: CleanedAudio, purpose: CleanedAudio.Purpose = .preview) throws {
        try withLock {
            guard try loadProject().source(record.source) != nil else { throw EditError.unknownSource(record.source) }
            let fileURL = url(for: .audio).appending(path: record.file)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                throw ProjectFolderError.couldNotRead(fileURL, "The cleaned file isn't there.")
            }
            let previous = try? cleanedAudio(for: record.source, purpose: purpose)
            try write(record, to: cleanedAudioRecordURL(for: record.source, purpose: purpose))
            removeSupersededCleanedAudio(for: record.source, keeping: [previous?.file])
        }
    }

    /// Each cleaning writes a new file, so one in use is never overwritten. Once a new one is recorded, the
    /// ones before it go, except those the preview's and the hand-off's records name, and the one just
    /// replaced, which an export started before it may still be reading.
    private func removeSupersededCleanedAudio(for source: SourceID, keeping extra: [String?]) {
        let manager = FileManager.default
        let folder = url(for: .audio)
        var kept = Set(extra.compactMap { $0 })
        for purpose in [CleanedAudio.Purpose.preview, .handoff] {
            if let file = (try? cleanedAudio(for: source, purpose: purpose))?.file { kept.insert(file) }
        }
        let names = (try? manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix("\(source)-") && name.hasSuffix(".wav") && !kept.contains(name) {
            try? manager.removeItem(at: folder.appending(path: name))
        }
    }
}
