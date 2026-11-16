import Foundation
import Sparkle

/// Updates (docs/decisions.md, 91 and 97): a thin layer on Sparkle.
///
/// Sparkle looks for updates by itself about once a day, without asking first (`SUEnableAutomaticChecks`);
/// Check for Updates… looks at once. Nothing about the Mac is sent. Each request fetches the feed
/// named by `SUFeedURL` in the app's Info.plist; Sparkle then shows what's new, downloads the update,
/// checks it against `SUPublicEDKey` and installs it.
@MainActor
public final class AppUpdater {
    private let controller: SPUStandardUpdaterController

    /// Starts the updater for the running app. Call it once, at launch.
    public init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.sendsSystemProfile = false
    }

    /// Whether CueCan looks for updates, and for news, by itself. On unless the creator turns it off in
    /// Settings.
    public var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether a check can start now: false while one is already under way.
    public var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// Looks for a newer version and shows the result, whatever it is.
    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
