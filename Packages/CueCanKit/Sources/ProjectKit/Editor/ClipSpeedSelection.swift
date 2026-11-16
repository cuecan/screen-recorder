/// The common speed values of selected clips. Nil means mixed (or no clips), so an inspector never
/// presents the first clip's value as if every selected clip had it.
public struct ClipSpeedSelection: Equatable, Sendable {
    public let rate: Double?
    public let sound: ClipSpeed.Sound?

    public init(clips: [Clip]) {
        rate = clips.first.flatMap { first in clips.allSatisfy { $0.speed.rate == first.speed.rate } ? first.speed.rate : nil }
        sound = clips.first.flatMap { first in clips.allSatisfy { $0.speed.sound == first.speed.sound } ? first.speed.sound : nil }
    }
}
