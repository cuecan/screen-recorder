import Foundation

/// The signal the sync page plays, and what a calibration needs from it (docs/decisions.md, 83).
///
/// The page is in CueCan's web app (`resources/js/pages/sync.tsx` there): a phone's screen flashes white
/// and beeps at the same instant, every couple of seconds. Change the beep's pitch here and there together.
public enum SyncSignal {
    /// Where the page is. The app shows it as a QR code.
    public static let pageAddress = "https://cuecan.com/sync"
    /// The beep's pitch, in hertz. The mic's sound is searched for this tone.
    public static let beepFrequency = 3_000.0
    /// How far apart a flash and its beep can be found and still be one event, in seconds. The page's
    /// flashes are at least 1.8 s apart, so nearer than this is never the neighbouring one.
    public static let maximumOffset = 0.5
    /// How many flashes, each with its beep and agreeing with each other, finish a calibration.
    public static let readingsWanted = 5
    /// How near the middle reading a reading has to be to agree with it, in seconds. A starting value:
    /// under a frame of a 30 fps camera.
    public static let agreement = 0.025
    /// How many of one signal, with none of the other, before the other is said to be missing.
    public static let missingAfter = 3
}
