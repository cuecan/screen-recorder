import Foundation

/// How the edit's audio sounds: Cleanup and Voice for each mic source, then Loudness on the final mix
/// (docs/decisions.md, 33 to 36). Levels are each clip's and each overlay's own (71).
///
/// Every mic source starts from ``defaults``. A source that has been adjusted on its own has an entry in
/// ``sources``, so one project can clean a studio mic and a camera mic differently. Loudness isn't per
/// source, because it's measured on everything mixed together at export.
public struct AudioSettings: Codable, Equatable, Sendable {
    /// The project's default Cleanup and Voice, for every mic source without its own.
    public var defaults: SourceAudioSettings
    /// Mic sources adjusted on their own, by the source whose audio they clean.
    public var sources: [SourceID: SourceAudioSettings]
    /// The final mix's integrated loudness at export, in LUFS (docs/decisions.md, 35).
    public var loudnessTarget: Double
    /// The highest true peak the final mix may reach at export, in dBTP (docs/decisions.md, 35).
    public var truePeakCeiling: Double

    public init(
        defaults: SourceAudioSettings = SourceAudioSettings(),
        sources: [SourceID: SourceAudioSettings] = [:],
        loudnessTarget: Double = -14,
        truePeakCeiling: Double = -1
    ) {
        self.defaults = defaults
        self.sources = sources
        self.loudnessTarget = loudnessTarget
        self.truePeakCeiling = truePeakCeiling
    }

    private enum CodingKeys: String, CodingKey { case defaults, sources, loudnessTarget, truePeakCeiling }


    /// The settings a mic source uses: its own if it has them, otherwise the project's default.
    public func settings(for source: SourceID) -> SourceAudioSettings {
        sources[source] ?? defaults
    }

    /// Gives a mic source its own settings. It keeps them even if the default changes later.
    public mutating func set(_ settings: SourceAudioSettings, for source: SourceID) {
        sources[source] = settings
    }

    /// Puts a mic source back on the project's default.
    public mutating func useDefaults(for source: SourceID) {
        sources[source] = nil
    }
}
